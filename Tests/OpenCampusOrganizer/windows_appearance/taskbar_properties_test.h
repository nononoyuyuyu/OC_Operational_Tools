#ifndef TESTS_TASKBAR_PROPERTIES_TEST_H_
#define TESTS_TASKBAR_PROPERTIES_TEST_H_

#include <wrl/implements.h>
#include <vector>
#include "taskbar_properties.h"

void Check(bool value, const char* message);

// 公開順序だけを記録する。AppIDの再設定を画像再取得の証拠にはしない。
// ウィンドウIDを消してもプロセスIDを継承するため、実効IDは変わらない。
class RecordingTaskbarProperties final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IPropertyStore> {
 public:
  HRESULT STDMETHODCALLTYPE GetCount(DWORD*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetAt(DWORD, PROPERTYKEY*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetValue(REFPROPERTYKEY, PROPVARIANT*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE Commit() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE SetValue(REFPROPERTYKEY key, REFPROPVARIANT property_value) override {
    if (fail_icon && IsEqualPropertyKey(key, PKEY_AppUserModel_RelaunchIconResource)) return E_FAIL;
    if (IsEqualPropertyKey(key, PKEY_AppUserModel_ID)) {
      if (property_value.vt == VT_EMPTY) {
        identity = kAppUserModelId;
        writes.push_back(L"clear");
        return S_OK;
      }
      if (property_value.vt != VT_LPWSTR) return E_INVALIDARG;
      if (identity != property_value.pwszVal) {
        ++refreshes;
      }
      identity = property_value.pwszVal;
      writes.push_back(L"publish");
    } else {
      if (property_value.vt != VT_LPWSTR) return E_INVALIDARG;
      if (IsEqualPropertyKey(key, PKEY_AppUserModel_RelaunchCommand)) {
        writes.push_back(L"command");
      } else if (IsEqualPropertyKey(key, PKEY_AppUserModel_RelaunchDisplayNameResource)) {
        writes.push_back(L"name");
      } else if (IsEqualPropertyKey(key, PKEY_AppUserModel_RelaunchIconResource)) {
        icon = property_value.pwszVal;
        writes.push_back(L"icon");
      }
    }
    return S_OK;
  }
  std::wstring identity = kAppUserModelId;
  std::wstring icon;
  std::vector<std::wstring> writes;
  int refreshes = 0;
  bool fail_icon = false;
};

inline void TestTaskbarProperties() {
  const auto properties = Microsoft::WRL::Make<RecordingTaskbarProperties>();
  const std::wstring executable = L"C:\\OCO Test\\OpenCampusOrganizer.exe";
  std::wstring icon;
  const std::vector<std::wstring> expected = {L"command", L"name", L"icon", L"publish"};
  for (int round = 0; round < 3; ++round) {
    for (int resource = 101; resource <= 105; ++resource) {
      icon = L"C:\\OCO Test\\appearance\\theme-" + std::to_wstring(resource) + L".ico";
      properties->writes.clear();
      Check(SetTaskbarAppearanceProperties(properties.Get(), executable, icon), "Cannot publish taskbar properties");
      Check(properties->writes == expected, "Taskbar metadata was published before it was ready");
      Check(properties->icon == icon + L",0", "Wrong shared icon path");
      Check(properties->identity == kAppUserModelId, "Theme changed stable application identity");
    }
  }
  Check(properties->refreshes == 0, "Theme change regrouped the application");
  Check(SetTaskbarAppearanceProperties(properties.Get(), executable, icon), "Cannot retry same theme");
  properties->fail_icon = true;
  properties->writes.clear();
  Check(!SetTaskbarAppearanceProperties(properties.Get(), executable, icon), "Property failure was hidden");
  Check(properties->identity == kAppUserModelId && properties->refreshes == 0, "Incomplete metadata was published");
  properties->fail_icon = false;
  Check(SetTaskbarAppearanceProperties(properties.Get(), executable, icon), "Cannot recover from property failure");
  Check(properties->refreshes == 0, "Recovery regrouped the application");
}

#endif  // TESTS_TASKBAR_PROPERTIES_TEST_H_
