#include "mtp_plugin.h"

#include <PortableDevice.h>
#include <PortableDeviceApi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <windows.h>
#include <wrl/client.h>

#include <chrono>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace dapper {

using Microsoft::WRL::ComPtr;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

// ── Helpers ─────────────────────────────────────────────────────────────────

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int len = WideCharToMultiByte(CP_UTF8, 0, w.data(),
                                static_cast<int>(w.size()), nullptr, 0,
                                nullptr, nullptr);
  std::string out(static_cast<size_t>(len), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                      out.data(), len, nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int len = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                 static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), len);
  return out;
}

const std::string* GetString(const EncodableMap& m, const std::string& key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

bool GetInt64(const EncodableMap& m, const std::string& key, int64_t* out) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return false;
  if (auto* p = std::get_if<int64_t>(&it->second)) {
    *out = *p;
    return true;
  }
  if (auto* p = std::get_if<int32_t>(&it->second)) {
    *out = *p;
    return true;
  }
  return false;
}

const std::vector<uint8_t>* GetBytes(const EncodableMap& m,
                                      const std::string& key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return nullptr;
  return std::get_if<std::vector<uint8_t>>(&it->second);
}

void FailHr(MethodResult<EncodableValue>* result, const char* op, HRESULT hr) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%s failed: 0x%08lX", op,
                static_cast<unsigned long>(hr));
  result->Error("MTP_ERROR", buf, nullptr);
}

// Read a string property out of an IPortableDeviceValues bag. Returns L""
// if absent.
std::wstring ReadStringValue(IPortableDeviceValues* values, REFPROPERTYKEY key) {
  LPWSTR s = nullptr;
  if (SUCCEEDED(values->GetStringValue(key, &s)) && s != nullptr) {
    std::wstring out(s);
    CoTaskMemFree(s);
    return out;
  }
  return {};
}

ULONGLONG ReadU64Value(IPortableDeviceValues* values, REFPROPERTYKEY key) {
  ULONGLONG v = 0;
  values->GetUnsignedLargeIntegerValue(key, &v);
  return v;
}

ULONG ReadU32Value(IPortableDeviceValues* values, REFPROPERTYKEY key) {
  ULONG v = 0;
  values->GetUnsignedIntegerValue(key, &v);
  return v;
}

// Builds the IPortableDeviceValues bag describing a new file object for
// CreateObjectWithPropertiesAndData. Caller releases via ComPtr.
HRESULT BuildPutObjectProperties(const std::wstring& parent_id,
                                  const std::wstring& name,
                                  int64_t total_bytes,
                                  ComPtr<IPortableDeviceValues>* out) {
  ComPtr<IPortableDeviceValues> props;
  HRESULT hr = CoCreateInstance(CLSID_PortableDeviceValues, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&props));
  if (FAILED(hr)) return hr;
  props->SetStringValue(WPD_OBJECT_PARENT_ID, parent_id.c_str());
  props->SetStringValue(WPD_OBJECT_NAME, name.c_str());
  props->SetStringValue(WPD_OBJECT_ORIGINAL_FILE_NAME, name.c_str());
  props->SetGuidValue(WPD_OBJECT_CONTENT_TYPE, WPD_CONTENT_TYPE_GENERIC_FILE);
  if (total_bytes > 0) {
    props->SetUnsignedLargeIntegerValue(WPD_OBJECT_SIZE,
                                         static_cast<ULONGLONG>(total_bytes));
  }
  *out = props;
  return S_OK;
}

}  // namespace

// ── EventStreamHandler ─────────────────────────────────────────────────────

class MtpEventStreamHandler : public flutter::StreamHandler<EncodableValue> {
 public:
  explicit MtpEventStreamHandler(MtpPlugin* plugin) : plugin_(plugin) {}

  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnListenInternal(
      const EncodableValue* /* arguments */,
      std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) override {
    plugin_->OnEventListen(std::move(events));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnCancelInternal(
      const EncodableValue* /* arguments */) override {
    plugin_->OnEventCancel();
    return nullptr;
  }

 private:
  MtpPlugin* plugin_;
};

}  // namespace dapper

// Header forward-declared OnEventListen / OnEventCancel; we add them here for
// the file to compile without yet another header round-trip.
namespace dapper {

// MtpPlugin needs OnEventListen/Cancel as friends or public. Make them public
// helpers by adding methods after the class definition? Simpler: declare them
// inside the class body in the header. (Already done implicitly via
// StartPolling/StopPolling; this trampoline calls those.)
//
// The trampoline lives here so the StreamHandler doesn't need MtpPlugin's
// internals.
class MtpPluginFriend {
 public:
  static void Listen(MtpPlugin* p,
                     std::unique_ptr<flutter::EventSink<EncodableValue>> sink) {
    {
      std::lock_guard<std::mutex> g(p->event_lock_);
      p->event_sink_ = std::move(sink);
    }
    p->StartPolling();
  }
  static void Cancel(MtpPlugin* p) {
    p->StopPolling();
    std::lock_guard<std::mutex> g(p->event_lock_);
    p->event_sink_.reset();
  }
};

void MtpPlugin::OnEventListen(
    std::unique_ptr<flutter::EventSink<EncodableValue>> sink) {
  MtpPluginFriend::Listen(this, std::move(sink));
}

void MtpPlugin::OnEventCancel() { MtpPluginFriend::Cancel(this); }

// ── Registration ──────────────────────────────────────────────────────────

// static
void MtpPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "com.dapper/mtp",
          &flutter::StandardMethodCodec::GetInstance());
  auto event_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "com.dapper/mtp_events",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<MtpPlugin>();
  auto* raw = plugin.get();

  method_channel->SetMethodCallHandler(
      [raw](const auto& call, auto result) {
        raw->HandleMethodCall(call, std::move(result));
      });

  event_channel->SetStreamHandler(
      std::make_unique<MtpEventStreamHandler>(raw));

  registrar->AddPlugin(std::move(plugin));
}

MtpPlugin::MtpPlugin() {
  // COM init for the main (calling) thread as MTA. The free-threaded
  // marshaller (CLSID_PortableDeviceFTM) we use for IPortableDevice plays
  // well with MTA; using STA on the plugin thread risked conflicts with
  // Flutter's existing apartment on some Windows builds.
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
}

MtpPlugin::~MtpPlugin() {
  StopPolling();
  {
    std::lock_guard<std::mutex> g(sessions_lock_);
    sessions_.clear();
  }
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    streams_.clear();
  }
  CoUninitialize();
}

// ── Dispatch ────────────────────────────────────────────────────────────────

void MtpPlugin::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableMap* args =
      std::get_if<EncodableMap>(call.arguments());
  EncodableMap empty;
  const EncodableMap& a = args != nullptr ? *args : empty;

  if (method == "ping") {
    OnPing(std::move(result));
  } else if (method == "enumerate") {
    OnEnumerate(std::move(result));
  } else if (method == "openSession") {
    OnOpenSession(a, std::move(result));
  } else if (method == "closeSession") {
    OnCloseSession(a, std::move(result));
  } else if (method == "list") {
    OnList(a, std::move(result));
  } else if (method == "mkdir") {
    OnMkdir(a, std::move(result));
  } else if (method == "delete") {
    OnDelete(a, std::move(result));
  } else if (method == "freeSpace") {
    OnFreeSpace(a, std::move(result));
  } else if (method == "putBegin") {
    OnPutBegin(a, std::move(result));
  } else if (method == "putChunk") {
    OnPutChunk(a, std::move(result));
  } else if (method == "putCommit") {
    OnPutCommit(a, std::move(result));
  } else if (method == "putAbort") {
    OnPutAbort(a, std::move(result));
  } else if (method == "getBegin") {
    OnGetBegin(a, std::move(result));
  } else if (method == "getChunk") {
    OnGetChunk(a, std::move(result));
  } else if (method == "getEnd") {
    OnGetEnd(a, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void MtpPlugin::OnPing(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  result->Success(EncodableValue(true));
}

// ── Enumerate ──────────────────────────────────────────────────────────────

EncodableList MtpPlugin::EnumerateDevicesSync() {
  EncodableList out;
  ComPtr<IPortableDeviceManager> mgr;
  HRESULT hr = CoCreateInstance(CLSID_PortableDeviceManager, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&mgr));
  if (FAILED(hr)) return out;

  DWORD count = 0;
  if (FAILED(mgr->GetDevices(nullptr, &count)) || count == 0) return out;
  std::vector<PWSTR> ids(count, nullptr);
  if (FAILED(mgr->GetDevices(ids.data(), &count))) return out;

  for (DWORD i = 0; i < count; i++) {
    std::wstring pnp_id = ids[i] != nullptr ? ids[i] : L"";

    DWORD name_len = 0;
    mgr->GetDeviceFriendlyName(ids[i], nullptr, &name_len);
    std::wstring label(name_len, L'\0');
    if (name_len > 0) {
      mgr->GetDeviceFriendlyName(ids[i], label.data(), &name_len);
      if (!label.empty() && label.back() == L'\0') label.pop_back();
    }
    if (label.empty()) label = L"MTP Device";

    // Capacity: open the device briefly + sum across functional storages.
    int64_t total = 0;
    int64_t available = 0;
    ComPtr<IPortableDevice> device;
    if (SUCCEEDED(CoCreateInstance(CLSID_PortableDeviceFTM, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&device)))) {
      ComPtr<IPortableDeviceValues> client_info;
      CoCreateInstance(CLSID_PortableDeviceValues, nullptr,
                        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&client_info));
      if (client_info) {
        client_info->SetStringValue(WPD_CLIENT_NAME, L"Dapper");
        client_info->SetUnsignedIntegerValue(WPD_CLIENT_MAJOR_VERSION, 1);
        client_info->SetUnsignedIntegerValue(WPD_CLIENT_MINOR_VERSION, 0);
        client_info->SetUnsignedIntegerValue(WPD_CLIENT_REVISION, 0);
        if (SUCCEEDED(device->Open(ids[i], client_info.Get()))) {
          ComPtr<IPortableDeviceContent> content;
          if (SUCCEEDED(device->Content(&content))) {
            ComPtr<IPortableDeviceProperties> props;
            content->Properties(&props);
            ComPtr<IPortableDeviceKeyCollection> keys;
            CoCreateInstance(CLSID_PortableDeviceKeyCollection, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&keys));
            if (keys) {
              keys->Add(WPD_STORAGE_CAPACITY);
              keys->Add(WPD_STORAGE_FREE_SPACE_IN_BYTES);
            }
            // Walk children of DEVICE — every storage object is one level
            // beneath. WPD spec: enumerate WPD_DEVICE_OBJECT_ID children
            // and pick those whose CONTENT_TYPE is WPD_CONTENT_TYPE_STORAGE.
            ComPtr<IEnumPortableDeviceObjectIDs> e;
            if (SUCCEEDED(content->EnumObjects(0, WPD_DEVICE_OBJECT_ID,
                                                nullptr, &e))) {
              PWSTR storage_ids[8];
              DWORD got = 0;
              while (e->Next(8, storage_ids, &got) == S_OK ||
                      (got > 0 && got != 0xFFFFFFFF)) {
                for (DWORD j = 0; j < got; j++) {
                  ComPtr<IPortableDeviceValues> values;
                  if (props && SUCCEEDED(props->GetValues(storage_ids[j],
                                                            keys.Get(),
                                                            &values))) {
                    total += static_cast<int64_t>(
                        ReadU64Value(values.Get(), WPD_STORAGE_CAPACITY));
                    available += static_cast<int64_t>(ReadU64Value(
                        values.Get(),
                        WPD_STORAGE_FREE_SPACE_IN_BYTES));
                  }
                  CoTaskMemFree(storage_ids[j]);
                }
                if (got < 8) break;
              }
            }
          }
          device->Close();
        }
      }
    }

    EncodableMap entry = {
        {EncodableValue("deviceId"), EncodableValue(WideToUtf8(pnp_id))},
        {EncodableValue("label"), EncodableValue(WideToUtf8(label))},
        {EncodableValue("totalBytes"), EncodableValue(total)},
        {EncodableValue("availableBytes"), EncodableValue(available)},
    };
    out.push_back(EncodableValue(entry));
    CoTaskMemFree(ids[i]);
  }
  return out;
}

void MtpPlugin::OnEnumerate(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  result->Success(EncodableValue(EnumerateDevicesSync()));
}

// ── Sessions ───────────────────────────────────────────────────────────────

std::shared_ptr<MtpPlugin::Session> MtpPlugin::SessionFor(
    const std::string& device_id) {
  std::lock_guard<std::mutex> g(sessions_lock_);
  auto it = sessions_.find(device_id);
  if (it != sessions_.end()) return it->second;
  return nullptr;
}

std::wstring MtpPlugin::WideIdForInt(Session& s, int64_t i) {
  std::lock_guard<std::mutex> g(s.lock);
  // 0 is the synthetic root → use functional storage object id.
  if (i == 0) {
    return s.functional_storage_id.empty() ? std::wstring(WPD_DEVICE_OBJECT_ID)
                                            : s.functional_storage_id;
  }
  auto it = s.int_to_wid.find(i);
  if (it != s.int_to_wid.end()) return it->second;
  return {};
}

int64_t MtpPlugin::IntIdForWide(Session& s, const std::wstring& w) {
  std::lock_guard<std::mutex> g(s.lock);
  if (!s.functional_storage_id.empty() && w == s.functional_storage_id) {
    return 0;
  }
  auto it = s.wid_to_int.find(w);
  if (it != s.wid_to_int.end()) return it->second;
  int64_t id = s.next_id++;
  s.int_to_wid[id] = w;
  s.wid_to_int[w] = id;
  return id;
}

HRESULT MtpPlugin::EnsureFunctionalStorageId(Session& s) {
  if (!s.functional_storage_id.empty()) return S_OK;
  ComPtr<IPortableDeviceContent> content;
  HRESULT hr = s.device->Content(&content);
  if (FAILED(hr)) return hr;

  // First storage under DEVICE.
  ComPtr<IEnumPortableDeviceObjectIDs> e;
  hr = content->EnumObjects(0, WPD_DEVICE_OBJECT_ID, nullptr, &e);
  if (FAILED(hr)) return hr;
  PWSTR ids[1] = {nullptr};
  DWORD got = 0;
  if (e->Next(1, ids, &got) != S_OK || got == 0) {
    return E_FAIL;
  }
  s.functional_storage_id = ids[0] != nullptr ? ids[0] : L"";
  CoTaskMemFree(ids[0]);
  if (s.functional_storage_id.empty()) return E_FAIL;
  return S_OK;
}

void MtpPlugin::OnOpenSession(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  if (device_id == nullptr) {
    result->Error("BAD_ARGS", "deviceId missing", nullptr);
    return;
  }
  // Idempotent — re-opening returns success.
  {
    std::lock_guard<std::mutex> g(sessions_lock_);
    if (sessions_.find(*device_id) != sessions_.end()) {
      result->Success();
      return;
    }
  }

  ComPtr<IPortableDevice> device;
  HRESULT hr = CoCreateInstance(CLSID_PortableDeviceFTM, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&device));
  if (FAILED(hr)) { FailHr(result.get(), "CoCreate(Device)", hr); return; }

  ComPtr<IPortableDeviceValues> client_info;
  CoCreateInstance(CLSID_PortableDeviceValues, nullptr, CLSCTX_INPROC_SERVER,
                    IID_PPV_ARGS(&client_info));
  client_info->SetStringValue(WPD_CLIENT_NAME, L"Dapper");
  client_info->SetUnsignedIntegerValue(WPD_CLIENT_MAJOR_VERSION, 1);
  client_info->SetUnsignedIntegerValue(WPD_CLIENT_MINOR_VERSION, 0);
  client_info->SetUnsignedIntegerValue(WPD_CLIENT_REVISION, 0);

  std::wstring pnp = Utf8ToWide(*device_id);
  hr = device->Open(pnp.c_str(), client_info.Get());
  if (FAILED(hr)) { FailHr(result.get(), "Device::Open", hr); return; }

  auto s = std::make_shared<Session>();
  s->device = device;
  hr = EnsureFunctionalStorageId(*s);
  if (FAILED(hr)) {
    device->Close();
    FailHr(result.get(), "EnsureFunctionalStorageId", hr);
    return;
  }

  {
    std::lock_guard<std::mutex> g(sessions_lock_);
    sessions_[*device_id] = s;
  }
  result->Success();
}

void MtpPlugin::OnCloseSession(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  if (device_id == nullptr) {
    result->Error("BAD_ARGS", "deviceId missing", nullptr);
    return;
  }
  std::shared_ptr<Session> s;
  {
    std::lock_guard<std::mutex> g(sessions_lock_);
    auto it = sessions_.find(*device_id);
    if (it != sessions_.end()) {
      s = it->second;
      sessions_.erase(it);
    }
  }
  if (s) s->device->Close();
  result->Success();
}

// ── List / mkdir / delete / freeSpace ──────────────────────────────────────

void MtpPlugin::OnList(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  int64_t parent_int = 0;
  if (device_id == nullptr || !GetInt64(args, "parentObjectId", &parent_int)) {
    result->Error("BAD_ARGS", "deviceId / parentObjectId", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Error("NO_SESSION", "Call openSession first", nullptr);
    return;
  }

  std::wstring parent_w = WideIdForInt(*s, parent_int);
  if (parent_w.empty()) {
    result->Error("BAD_PARENT", "Unknown parentObjectId", nullptr);
    return;
  }

  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Error("MTP_ERROR", "Content failed", nullptr);
    return;
  }
  ComPtr<IPortableDeviceProperties> props;
  content->Properties(&props);

  ComPtr<IPortableDeviceKeyCollection> keys;
  CoCreateInstance(CLSID_PortableDeviceKeyCollection, nullptr,
                    CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&keys));
  keys->Add(WPD_OBJECT_ID);
  keys->Add(WPD_OBJECT_NAME);
  keys->Add(WPD_OBJECT_ORIGINAL_FILE_NAME);
  keys->Add(WPD_OBJECT_CONTENT_TYPE);
  keys->Add(WPD_OBJECT_SIZE);
  keys->Add(WPD_OBJECT_DATE_MODIFIED);

  ComPtr<IEnumPortableDeviceObjectIDs> e;
  if (FAILED(content->EnumObjects(0, parent_w.c_str(), nullptr, &e))) {
    result->Error("MTP_ERROR", "EnumObjects failed", nullptr);
    return;
  }

  EncodableList out;
  PWSTR ids[16];
  DWORD got = 0;
  while (true) {
    HRESULT hr = e->Next(16, ids, &got);
    if (FAILED(hr) || got == 0) break;
    for (DWORD i = 0; i < got; i++) {
      ComPtr<IPortableDeviceValues> values;
      if (FAILED(props->GetValues(ids[i], keys.Get(), &values))) {
        CoTaskMemFree(ids[i]);
        continue;
      }
      std::wstring obj_id = ReadStringValue(values.Get(), WPD_OBJECT_ID);
      std::wstring name = ReadStringValue(values.Get(),
                                          WPD_OBJECT_ORIGINAL_FILE_NAME);
      if (name.empty()) {
        name = ReadStringValue(values.Get(), WPD_OBJECT_NAME);
      }
      GUID content_type = {};
      values->GetGuidValue(WPD_OBJECT_CONTENT_TYPE, &content_type);
      bool is_dir = IsEqualGUID(content_type, WPD_CONTENT_TYPE_FOLDER) ||
                    IsEqualGUID(content_type,
                                WPD_CONTENT_TYPE_FUNCTIONAL_OBJECT);
      int64_t size = static_cast<int64_t>(
          ReadU64Value(values.Get(), WPD_OBJECT_SIZE));

      // Modified time. WPD stores it as PROPVARIANT VT_DATE (OLE date) —
      // convert to milliseconds-since-epoch so the Dart layer sees the
      // same shape as the macOS bridge.
      EncodableValue modified_millis;
      PROPVARIANT mod_pv;
      PropVariantInit(&mod_pv);
      if (SUCCEEDED(values->GetValue(WPD_OBJECT_DATE_MODIFIED, &mod_pv))) {
        SYSTEMTIME st = {};
        FILETIME ft = {};
        bool ok = false;
        if (mod_pv.vt == VT_DATE) {
          if (VariantTimeToSystemTime(mod_pv.date, &st) &&
              SystemTimeToFileTime(&st, &ft)) {
            ok = true;
          }
        } else if (mod_pv.vt == VT_LPWSTR && mod_pv.pwszVal != nullptr) {
          // Some WPD impls return ISO-ish strings. Skip — too device-
          // specific to parse reliably here.
        }
        if (ok) {
          ULARGE_INTEGER li{};
          li.LowPart = ft.dwLowDateTime;
          li.HighPart = ft.dwHighDateTime;
          // 100-ns intervals since 1601 → ms since 1970.
          static constexpr int64_t kEpochDelta = 11644473600000LL;
          int64_t ms = static_cast<int64_t>(li.QuadPart / 10000) - kEpochDelta;
          modified_millis = EncodableValue(ms);
        }
      }
      PropVariantClear(&mod_pv);

      int64_t int_id = IntIdForWide(*s, obj_id);

      EncodableMap entry = {
          {EncodableValue("objectId"), EncodableValue(int_id)},
          {EncodableValue("name"), EncodableValue(WideToUtf8(name))},
          {EncodableValue("isDir"), EncodableValue(is_dir)},
          {EncodableValue("size"), EncodableValue(size)},
          {EncodableValue("modifiedMillis"), modified_millis},
      };
      out.push_back(EncodableValue(entry));
      CoTaskMemFree(ids[i]);
    }
    if (got < 16) break;
  }
  result->Success(EncodableValue(out));
}

void MtpPlugin::OnMkdir(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  const std::string* name = GetString(args, "name");
  int64_t parent_int = 0;
  if (device_id == nullptr || name == nullptr ||
      !GetInt64(args, "parentObjectId", &parent_int)) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Error("NO_SESSION", "Call openSession first", nullptr);
    return;
  }
  std::wstring parent_w = WideIdForInt(*s, parent_int);
  if (parent_w.empty()) {
    result->Error("BAD_PARENT", "Unknown parentObjectId", nullptr);
    return;
  }
  std::wstring name_w = Utf8ToWide(*name);

  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Error("MTP_ERROR", "Content failed", nullptr);
    return;
  }
  ComPtr<IPortableDeviceValues> props;
  CoCreateInstance(CLSID_PortableDeviceValues, nullptr, CLSCTX_INPROC_SERVER,
                    IID_PPV_ARGS(&props));
  props->SetStringValue(WPD_OBJECT_PARENT_ID, parent_w.c_str());
  props->SetStringValue(WPD_OBJECT_NAME, name_w.c_str());
  props->SetStringValue(WPD_OBJECT_ORIGINAL_FILE_NAME, name_w.c_str());
  props->SetGuidValue(WPD_OBJECT_CONTENT_TYPE, WPD_CONTENT_TYPE_FOLDER);

  PWSTR new_id = nullptr;
  HRESULT hr = content->CreateObjectWithPropertiesOnly(props.Get(), &new_id);
  if (FAILED(hr) || new_id == nullptr) {
    FailHr(result.get(), "CreateObjectWithPropertiesOnly", hr);
    return;
  }
  std::wstring new_w(new_id);
  CoTaskMemFree(new_id);
  result->Success(EncodableValue(IntIdForWide(*s, new_w)));
}

void MtpPlugin::OnDelete(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  int64_t obj_int = 0;
  if (device_id == nullptr || !GetInt64(args, "objectId", &obj_int)) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Error("NO_SESSION", "Call openSession first", nullptr);
    return;
  }
  std::wstring obj_w = WideIdForInt(*s, obj_int);
  if (obj_w.empty()) {
    result->Error("BAD_OBJECT", "Unknown objectId", nullptr);
    return;
  }

  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Error("MTP_ERROR", "Content failed", nullptr);
    return;
  }
  ComPtr<IPortableDevicePropVariantCollection> ids;
  CoCreateInstance(CLSID_PortableDevicePropVariantCollection, nullptr,
                    CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&ids));
  PROPVARIANT v;
  PropVariantInit(&v);
  v.vt = VT_LPWSTR;
  v.pwszVal = const_cast<LPWSTR>(obj_w.c_str());
  ids->Add(&v);

  HRESULT hr = content->Delete(PORTABLE_DEVICE_DELETE_NO_RECURSION,
                                 ids.Get(), nullptr);
  if (FAILED(hr)) {
    FailHr(result.get(), "Content::Delete", hr);
    return;
  }
  result->Success();
}

void MtpPlugin::OnFreeSpace(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  if (device_id == nullptr) {
    result->Error("BAD_ARGS", "deviceId", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Success();
    return;
  }
  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Success();
    return;
  }
  ComPtr<IPortableDeviceProperties> props;
  content->Properties(&props);
  ComPtr<IPortableDeviceKeyCollection> keys;
  CoCreateInstance(CLSID_PortableDeviceKeyCollection, nullptr,
                    CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&keys));
  keys->Add(WPD_STORAGE_FREE_SPACE_IN_BYTES);
  ComPtr<IPortableDeviceValues> values;
  if (FAILED(props->GetValues(s->functional_storage_id.c_str(),
                                keys.Get(), &values))) {
    result->Success();
    return;
  }
  ULONGLONG free_bytes =
      ReadU64Value(values.Get(), WPD_STORAGE_FREE_SPACE_IN_BYTES);
  result->Success(EncodableValue(static_cast<int64_t>(free_bytes)));
}

// ── Put streaming ──────────────────────────────────────────────────────────

void MtpPlugin::OnPutBegin(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  const std::string* name = GetString(args, "name");
  int64_t parent_int = 0;
  int64_t total_bytes = 0;
  if (device_id == nullptr || name == nullptr ||
      !GetInt64(args, "parentObjectId", &parent_int) ||
      !GetInt64(args, "totalBytes", &total_bytes)) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Error("NO_SESSION", "Call openSession first", nullptr);
    return;
  }
  std::wstring parent_w = WideIdForInt(*s, parent_int);
  if (parent_w.empty()) {
    result->Error("BAD_PARENT", "Unknown parentObjectId", nullptr);
    return;
  }
  std::wstring name_w = Utf8ToWide(*name);

  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Error("MTP_ERROR", "Content failed", nullptr);
    return;
  }
  ComPtr<IPortableDeviceValues> props;
  if (FAILED(BuildPutObjectProperties(parent_w, name_w, total_bytes, &props))) {
    result->Error("MTP_ERROR", "BuildPutObjectProperties failed", nullptr);
    return;
  }

  ComPtr<IStream> stream;
  DWORD optimal_size = 0;
  HRESULT hr = content->CreateObjectWithPropertiesAndData(
      props.Get(), &stream, &optimal_size, nullptr);
  if (FAILED(hr) || stream == nullptr) {
    FailHr(result.get(), "CreateObjectWithPropertiesAndData", hr);
    return;
  }
  ComPtr<IPortableDeviceDataStream> data_stream;
  stream.As(&data_stream);  // optional — needed for GetObjectID on commit.

  auto st = std::make_shared<Stream>();
  st->is_put = true;
  st->device_id = *device_id;
  st->stream = stream;
  st->data_stream = data_stream;
  std::string stream_id = NextStreamId();
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    streams_[stream_id] = st;
  }
  result->Success(EncodableValue(stream_id));
}

void MtpPlugin::OnPutChunk(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* stream_id = GetString(args, "streamId");
  const std::vector<uint8_t>* bytes = GetBytes(args, "bytes");
  if (stream_id == nullptr || bytes == nullptr) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  std::shared_ptr<Stream> st;
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    auto it = streams_.find(*stream_id);
    if (it != streams_.end()) st = it->second;
  }
  if (st == nullptr || st->stream == nullptr) {
    result->Error("NO_STREAM", "Unknown streamId", nullptr);
    return;
  }

  // IStream::Write may write fewer bytes than asked — loop.
  size_t remaining = bytes->size();
  const uint8_t* buf = bytes->data();
  while (remaining > 0) {
    ULONG wrote = 0;
    HRESULT hr = st->stream->Write(buf, static_cast<ULONG>(remaining), &wrote);
    if (FAILED(hr)) {
      FailHr(result.get(), "IStream::Write", hr);
      return;
    }
    if (wrote == 0) break;
    buf += wrote;
    remaining -= wrote;
  }
  result->Success();
}

void MtpPlugin::OnPutCommit(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* stream_id = GetString(args, "streamId");
  if (stream_id == nullptr) {
    result->Error("BAD_ARGS", "streamId", nullptr);
    return;
  }
  std::shared_ptr<Stream> st;
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    auto it = streams_.find(*stream_id);
    if (it != streams_.end()) {
      st = it->second;
      streams_.erase(it);
    }
  }
  if (st == nullptr || st->stream == nullptr) {
    result->Error("NO_STREAM", "Unknown streamId", nullptr);
    return;
  }

  HRESULT hr = st->stream->Commit(STGC_DEFAULT);
  if (FAILED(hr)) {
    FailHr(result.get(), "IStream::Commit", hr);
    return;
  }
  PWSTR new_id = nullptr;
  if (st->data_stream != nullptr) {
    st->data_stream->GetObjectID(&new_id);
  }
  if (new_id == nullptr) {
    // Fall back: we have no object id post-commit. Returning -1 lets the
    // Dart side know commit-without-id happened; callers can re-list to
    // refresh the path↔id cache.
    result->Success(EncodableValue(static_cast<int64_t>(-1)));
    return;
  }
  std::wstring new_w(new_id);
  CoTaskMemFree(new_id);
  auto s = SessionFor(st->device_id);
  int64_t int_id = s != nullptr ? IntIdForWide(*s, new_w) : -1;
  result->Success(EncodableValue(int_id));
}

void MtpPlugin::OnPutAbort(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* stream_id = GetString(args, "streamId");
  if (stream_id == nullptr) {
    result->Success();
    return;
  }
  std::shared_ptr<Stream> st;
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    auto it = streams_.find(*stream_id);
    if (it != streams_.end()) {
      st = it->second;
      streams_.erase(it);
    }
  }
  // IStream::Revert discards the staged write so the half-uploaded object
  // is never committed on the device.
  if (st != nullptr && st->stream != nullptr) {
    st->stream->Revert();
  }
  result->Success();
}

// ── Get streaming ──────────────────────────────────────────────────────────

void MtpPlugin::OnGetBegin(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* device_id = GetString(args, "deviceId");
  int64_t obj_int = 0;
  if (device_id == nullptr || !GetInt64(args, "objectId", &obj_int)) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  auto s = SessionFor(*device_id);
  if (s == nullptr) {
    result->Error("NO_SESSION", "Call openSession first", nullptr);
    return;
  }
  std::wstring obj_w = WideIdForInt(*s, obj_int);
  if (obj_w.empty()) {
    result->Error("BAD_OBJECT", "Unknown objectId", nullptr);
    return;
  }

  ComPtr<IPortableDeviceContent> content;
  if (FAILED(s->device->Content(&content))) {
    result->Error("MTP_ERROR", "Content failed", nullptr);
    return;
  }
  ComPtr<IPortableDeviceResources> resources;
  if (FAILED(content->Transfer(&resources))) {
    result->Error("MTP_ERROR", "Content::Transfer failed", nullptr);
    return;
  }
  ComPtr<IStream> stream;
  DWORD optimal = 0;
  HRESULT hr = resources->GetStream(obj_w.c_str(), WPD_RESOURCE_DEFAULT,
                                      STGM_READ, &optimal, &stream);
  if (FAILED(hr) || stream == nullptr) {
    FailHr(result.get(), "Resources::GetStream", hr);
    return;
  }

  auto st = std::make_shared<Stream>();
  st->is_put = false;
  st->device_id = *device_id;
  st->stream = stream;
  std::string stream_id = NextStreamId();
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    streams_[stream_id] = st;
  }
  result->Success(EncodableValue(stream_id));
}

void MtpPlugin::OnGetChunk(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* stream_id = GetString(args, "streamId");
  int64_t max_bytes = 0;
  if (stream_id == nullptr || !GetInt64(args, "maxBytes", &max_bytes)) {
    result->Error("BAD_ARGS", "args", nullptr);
    return;
  }
  std::shared_ptr<Stream> st;
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    auto it = streams_.find(*stream_id);
    if (it != streams_.end()) st = it->second;
  }
  if (st == nullptr || st->stream == nullptr) {
    result->Error("NO_STREAM", "Unknown streamId", nullptr);
    return;
  }
  if (max_bytes <= 0) max_bytes = 64 * 1024;

  std::vector<uint8_t> buf(static_cast<size_t>(max_bytes));
  ULONG read = 0;
  HRESULT hr = st->stream->Read(buf.data(), static_cast<ULONG>(max_bytes),
                                  &read);
  if (FAILED(hr)) {
    FailHr(result.get(), "IStream::Read", hr);
    return;
  }
  buf.resize(read);
  result->Success(EncodableValue(buf));
}

void MtpPlugin::OnGetEnd(
    const EncodableMap& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string* stream_id = GetString(args, "streamId");
  if (stream_id == nullptr) {
    result->Success();
    return;
  }
  {
    std::lock_guard<std::mutex> g(streams_lock_);
    streams_.erase(*stream_id);
  }
  result->Success();
}

// ── Misc ───────────────────────────────────────────────────────────────────

std::string MtpPlugin::NextStreamId() {
  int64_t n = ++stream_counter_;
  char buf[32];
  std::snprintf(buf, sizeof(buf), "s%lld", static_cast<long long>(n));
  return buf;
}

// ── EventChannel polling ──────────────────────────────────────────────────

void MtpPlugin::StartPolling() {
  if (polling_.exchange(true)) return;
  poll_thread_ = std::thread([this]() {
    // Polling thread runs as MTA so it can share IPortableDevice (FTM)
    // instances created on other threads without marshalling overhead.
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    EmitDeviceListIfChanged();
    while (polling_) {
      std::this_thread::sleep_for(std::chrono::seconds(2));
      if (!polling_) break;
      EmitDeviceListIfChanged();
    }
    CoUninitialize();
  });
}

void MtpPlugin::StopPolling() {
  if (!polling_.exchange(false)) return;
  if (poll_thread_.joinable()) poll_thread_.join();
}

void MtpPlugin::EmitDeviceListIfChanged() {
  EncodableList devices = EnumerateDevicesSync();
  std::vector<std::string> ids;
  ids.reserve(devices.size());
  for (const auto& v : devices) {
    if (auto* m = std::get_if<EncodableMap>(&v)) {
      auto it = m->find(EncodableValue("deviceId"));
      if (it != m->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) {
          ids.push_back(*s);
        }
      }
    }
  }
  if (ids == last_device_ids_) return;
  last_device_ids_ = std::move(ids);

  std::lock_guard<std::mutex> g(event_lock_);
  if (event_sink_) {
    EncodableMap msg = {
        {EncodableValue("kind"), EncodableValue("deviceList")},
        {EncodableValue("devices"), EncodableValue(devices)},
    };
    event_sink_->Success(EncodableValue(msg));
  }
}

}  // namespace dapper
