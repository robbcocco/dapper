import Cocoa
import FlutterMacOS

/// macOS MTP plugin.
///
/// Drives the [MtpBridge] Objective-C layer (which wraps libmtp) and emits
/// hotplug events on the EventChannel. All work runs on a dedicated serial
/// queue so libmtp's per-device single-threaded contract is respected end
/// to end — the Dart side already serialises per-device transfers via
/// `MtpDeviceFs._putMutex`; this queue is the second layer of defence.
///
/// Hotplug is implemented as a periodic poll (every 2s while subscribed)
/// instead of IOKit USB notifications. libmtp's `LIBMTP_Detect_Raw_Devices`
/// returns the current set; we diff against the previous list. Polling
/// keeps the code simple and matches the Windows side's polling behaviour;
/// switch to IOKit later if hotplug latency matters.
public class MtpPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private let queue = DispatchQueue(label: "com.dapper.mtp.plugin",
                                      qos: .userInitiated)
    private var pollTimer: Timer?
    private var lastDeviceIds: Set<String> = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "com.dapper/mtp",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.dapper/mtp_events",
            binaryMessenger: registrar.messenger
        )
        let instance = MtpPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall,
                       result: @escaping FlutterResult) {
        // Each call dispatched onto our serial queue so libmtp never sees
        // two threads against the same device at once.
        queue.async {
            self.handleSync(call, result: result)
        }
    }

    private func handleSync(_ call: FlutterMethodCall,
                             result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        do {
            switch call.method {
            case "ping":
                result(MtpBridge.isAvailable())

            case "enumerate":
                result(MtpBridge.enumerate())

            case "openSession":
                let deviceId = try requireString(args, "deviceId")
                try MtpBridge.openSession(deviceId: deviceId)
                result(nil)

            case "closeSession":
                let deviceId = try requireString(args, "deviceId")
                MtpBridge.closeSession(deviceId: deviceId)
                result(nil)

            case "list":
                let deviceId = try requireString(args, "deviceId")
                let parent = try requireInt64(args, "parentObjectId")
                let entries = try MtpBridge.list(deviceId: deviceId,
                                                 parentObjectId: parent)
                result(entries)

            case "mkdir":
                let deviceId = try requireString(args, "deviceId")
                let parent = try requireInt64(args, "parentObjectId")
                let name = try requireString(args, "name")
                let objId = try MtpBridge.mkdir(deviceId: deviceId,
                                                parentObjectId: parent,
                                                name: name)
                result(objId)

            case "delete":
                let deviceId = try requireString(args, "deviceId")
                let objectId = try requireInt64(args, "objectId")
                try MtpBridge.delete(deviceId: deviceId, objectId: objectId)
                result(nil)

            case "freeSpace":
                let deviceId = try requireString(args, "deviceId")
                let v = MtpBridge.freeSpace(deviceId: deviceId)
                result(v < 0 ? nil : NSNumber(value: v))

            case "putBegin":
                let deviceId = try requireString(args, "deviceId")
                let parent = try requireInt64(args, "parentObjectId")
                let name = try requireString(args, "name")
                let total = try requireInt64(args, "totalBytes")
                let streamId = try MtpBridge.putBegin(deviceId: deviceId,
                                                      parentObjectId: parent,
                                                      name: name,
                                                      totalBytes: total)
                result(streamId)

            case "putChunk":
                let streamId = try requireString(args, "streamId")
                guard let bytes = args["bytes"] as? FlutterStandardTypedData
                else { throw ArgError(message: "Missing bytes") }
                try MtpBridge.putChunk(streamId: streamId, bytes: bytes.data)
                result(nil)

            case "putCommit":
                let streamId = try requireString(args, "streamId")
                let objId = try MtpBridge.putCommit(streamId: streamId)
                result(objId)

            case "putAbort":
                let streamId = try requireString(args, "streamId")
                MtpBridge.putAbort(streamId: streamId)
                result(nil)

            case "getBegin":
                let deviceId = try requireString(args, "deviceId")
                let objectId = try requireInt64(args, "objectId")
                let streamId = try MtpBridge.getBegin(deviceId: deviceId,
                                                      objectId: objectId)
                result(streamId)

            case "getChunk":
                let streamId = try requireString(args, "streamId")
                let maxBytes = try requireInt64(args, "maxBytes")
                let data = try MtpBridge.getChunk(streamId: streamId,
                                                  maxBytes: UInt(maxBytes))
                result(FlutterStandardTypedData(bytes: data))

            case "getEnd":
                let streamId = try requireString(args, "streamId")
                MtpBridge.getEnd(streamId: streamId)
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let argErr as ArgError {
            result(FlutterError(code: "BAD_ARGS",
                                message: argErr.message,
                                details: nil))
        } catch {
            result(FlutterError(code: "MTP_ERROR",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    // MARK: - EventChannel (hotplug)

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink)
            -> FlutterError? {
        self.eventSink = events
        startPolling()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopPolling()
        eventSink = nil
        return nil
    }

    private func startPolling() {
        stopPolling()
        // Fire one immediate snapshot so the Dart side sees the current set
        // without waiting for the first 2s tick.
        queue.async { self.emitDeviceList() }
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0,
                                                  repeats: true) { [weak self] _ in
                self?.queue.async { self?.emitDeviceList() }
            }
        }
    }

    private func stopPolling() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = nil
        }
    }

    private func emitDeviceList() {
        let devices = MtpBridge.enumerate()
        let ids = Set(devices.compactMap { $0["deviceId"] as? String })
        if ids == lastDeviceIds { return }
        lastDeviceIds = ids
        let sink = eventSink
        DispatchQueue.main.async {
            sink?([
                "kind": "deviceList",
                "devices": devices,
            ])
        }
    }

    // MARK: - Arg helpers

    private struct ArgError: Error { let message: String }

    private func requireString(_ args: [String: Any], _ key: String) throws
            -> String {
        guard let v = args[key] as? String else {
            throw ArgError(message: "Missing/invalid: \(key)")
        }
        return v
    }

    private func requireInt64(_ args: [String: Any], _ key: String) throws
            -> Int64 {
        if let n = args[key] as? NSNumber { return n.int64Value }
        if let i = args[key] as? Int { return Int64(i) }
        throw ArgError(message: "Missing/invalid int: \(key)")
    }
}
