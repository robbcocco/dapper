import Cocoa
import FlutterMacOS

public class DriveDetectorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterEventChannel(
            name: "com.dapper/drive_detector",
            binaryMessenger: registrar.messenger
        )
        let instance = DriveDetectorPlugin()
        channel.setStreamHandler(instance)
        registrar.addApplicationDelegate(instance)
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events

        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        let mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendDrives()
        }

        let unmountObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendDrives()
        }

        observers = [mountObserver, unmountObserver]

        // Send the initial snapshot immediately.
        sendDrives()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        eventSink = nil
        return nil
    }

    private func sendDrives() {
        guard let sink = eventSink else { return }
        let drives = currentRemovableDrives()
        sink(drives)
    }

    private func currentRemovableDrives() -> [[String: Any]] {
        let keys: [URLResourceKey] = [
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: .skipHiddenVolumes
        ) else { return [] }

        var result: [[String: Any]] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            // Accept removable or ejectable volumes (covers USB, SD, external SSDs).
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            guard isRemovable || isEjectable else { continue }

            let path = url.path
            let label = values.volumeLocalizedName ?? url.lastPathComponent
            let total = values.volumeTotalCapacity ?? 0
            let available = values.volumeAvailableCapacity ?? 0

            result.append([
                "path": path,
                "label": label,
                "totalBytes": total,
                "availableBytes": available,
            ])
        }

        return result
    }
}
