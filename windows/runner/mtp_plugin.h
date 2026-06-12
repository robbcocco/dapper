#ifndef RUNNER_MTP_PLUGIN_H_
#define RUNNER_MTP_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include <PortableDevice.h>
#include <PortableDeviceApi.h>
#include <wrl/client.h>

// Windows MTP plugin via WPD COM.
//
// Implements the same MethodChannel surface as the macOS plugin so the Dart
// `MtpClient` works unchanged across platforms.
//
// Threading model: every method call runs on a dedicated worker queue (one
// std::thread blocking on a moodycamel-style queue would be cleaner, but a
// simpler approach is used here — each WPD COM call is wrapped in a per-
// device std::mutex). For put/get streaming, an in-flight transfer is held
// in a `Stream` object that owns the IPortableDeviceDataStream + a small
// in-memory FIFO between Dart's `putChunk` calls and WPD's IStream::Write
// callbacks.

namespace dapper {

class MtpPlugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  MtpPlugin();
  ~MtpPlugin();

  MtpPlugin(const MtpPlugin&) = delete;
  MtpPlugin& operator=(const MtpPlugin&) = delete;

  // EventChannel trampolines invoked by `MtpEventStreamHandler` (defined in
  // mtp_plugin.cpp). Public so the trampoline can reach them without a
  // friend declaration.
  void OnEventListen(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  void OnEventCancel();

 private:
  using EncodableValue = flutter::EncodableValue;
  using EncodableMap = flutter::EncodableMap;
  using EncodableList = flutter::EncodableList;

  // ── Sessions / objectId mapping ─────────────────────────────────────────

  // Per-device session record. WPD object ids are wide strings; we hand the
  // Dart layer 32-bit ints for compatibility with libmtp's int-based ids.
  // The mapping is bidirectional: every list() / mkdir() / putCommit() that
  // observes a new object id assigns it a stable int.
  struct Session {
    Microsoft::WRL::ComPtr<IPortableDevice> device;
    std::wstring functional_storage_id;  // WPD storage object id
    std::unordered_map<int64_t, std::wstring> int_to_wid;
    std::unordered_map<std::wstring, int64_t> wid_to_int;
    int64_t next_id = 100;  // 0 is reserved for "root"
    std::mutex lock;
  };

  // In-flight put/get session.
  struct Stream {
    bool is_put = false;
    Microsoft::WRL::ComPtr<IPortableDeviceDataStream> data_stream;
    Microsoft::WRL::ComPtr<IStream> stream;
    std::string device_id;
    std::wstring new_object_id;  // set on put commit
  };

  std::mutex sessions_lock_;
  std::unordered_map<std::string, std::shared_ptr<Session>> sessions_;
  std::mutex streams_lock_;
  std::unordered_map<std::string, std::shared_ptr<Stream>> streams_;
  std::atomic<int64_t> stream_counter_{0};

  // ── EventChannel state ──────────────────────────────────────────────────

  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;
  std::mutex event_lock_;
  std::atomic<bool> polling_{false};
  std::thread poll_thread_;
  std::vector<std::string> last_device_ids_;

  // ── Dispatch ────────────────────────────────────────────────────────────

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // RPCs ----------------------------------------------------------------
  void OnPing(std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnEnumerate(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnOpenSession(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnCloseSession(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnList(const EncodableMap& args,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnMkdir(const EncodableMap& args,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnDelete(const EncodableMap& args,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnFreeSpace(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnPutBegin(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnPutChunk(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnPutCommit(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnPutAbort(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnGetBegin(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnGetChunk(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void OnGetEnd(
      const EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // Helpers -------------------------------------------------------------
  std::shared_ptr<Session> SessionFor(const std::string& device_id);
  std::wstring WideIdForInt(Session& s, int64_t i);
  int64_t IntIdForWide(Session& s, const std::wstring& w);
  HRESULT EnsureFunctionalStorageId(Session& s);
  std::string NextStreamId();
  EncodableList EnumerateDevicesSync();

  // EventChannel ---------------------------------------------------------
  void StartPolling();
  void StopPolling();
  void EmitDeviceListIfChanged();
};

}  // namespace dapper

#endif  // RUNNER_MTP_PLUGIN_H_
