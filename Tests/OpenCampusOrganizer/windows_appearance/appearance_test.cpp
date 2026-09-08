#include <windows.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <flutter/standard_method_codec.h>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include "window_appearance.h"
#include "app_identity.h"
#include "shortcut_appearance.h"
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

void TestShortcuts() {
  wchar_t temporary[MAX_PATH];
  GetTempPathW(ARRAYSIZE(temporary), temporary);
  const auto directory = std::filesystem::path(temporary) /
      (L"oco-shortcuts-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
  Check(std::filesystem::create_directory(directory), "Cannot create shortcut fixture");
  wchar_t executable[32768];
  GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  const auto owned = directory / L"Renamed OCO.lnk";
  const auto foreign = directory / L"Open Campus Organizer.lnk";
  for (const auto& path : {owned, foreign}) {
    ComPtr<IShellLinkW> link;
    ComPtr<IPersistFile> file;
    Check(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))), "Cannot create link");
    link->SetPath(path == owned ? executable : L"C:\\Windows\\notepad.exe");
    link->SetArguments(L"--preserve-this");
    link->SetWorkingDirectory(directory.c_str());
    link->SetIconLocation(executable, -101);
    link.As(&file);
    Check(SUCCEEDED(file->Save(path.c_str(), TRUE)), "Cannot save fixture");
  }
  for (int resource = 101; resource <= 105; ++resource) {
    Check(UpdateAppearanceShortcuts(directory, executable, resource), "Cannot update shortcut icons");
    for (const auto& path : {owned, foreign}) {
      ComPtr<IShellLinkW> link;
      ComPtr<IPersistFile> file;
      CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
      link.As(&file);
      Check(SUCCEEDED(file->Load(path.c_str(), STGM_READ)), "Cannot load updated link");
      wchar_t icon[32768], arguments[256], working[32768];
      int index = 0;
      link->GetIconLocation(icon, ARRAYSIZE(icon), &index);
      Check(std::wstring(icon) == executable && index == -(path == owned ? resource : 101), "Wrong shortcut changed");
      ComPtr<IPropertyStore> properties;
      link.As(&properties);
      PROPVARIANT saved{};
      properties->GetValue(PKEY_AppUserModel_RelaunchIconResource, &saved);
      Check(path == owned ? saved.vt == VT_LPWSTR && std::wstring(saved.pwszVal) == std::wstring(executable) + L",-" + std::to_wstring(resource) : saved.vt == VT_EMPTY,
            "Pinned relaunch icon did not follow theme");
      PropVariantClear(&saved);
      link->GetArguments(arguments, ARRAYSIZE(arguments));
      link->GetWorkingDirectory(working, ARRAYSIZE(working));
      Check(std::wstring(arguments) == L"--preserve-this" && directory == working, "Shortcut parameters lost");
    }
  }
  SetFileAttributesW(owned.c_str(), FILE_ATTRIBUTE_READONLY);
  Check(!UpdateAppearanceShortcuts(directory, executable, 101), "Write failure was hidden");
  SetFileAttributesW(owned.c_str(), FILE_ATTRIBUTE_NORMAL);
  std::filesystem::remove(owned);
  std::filesystem::remove(foreign);
  std::filesystem::remove(directory);
}

class Messenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply = nullptr) const override {}
  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    handlers[channel] = std::move(handler);
  }
  bool Theme(const std::string& theme) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto message = codec.EncodeMethodCall(flutter::MethodCall<flutter::EncodableValue>(
        "setTheme", std::make_unique<flutter::EncodableValue>(theme)));
    bool replied = false, success = false;
    handlers.at("jp.nononoyuyuyu.open_campus_organizer/appearance")(
        message->data(), message->size(), [&](const uint8_t* reply, size_t size) {
          replied = true;
          success = size > 0 && reply[0] == 0;
        });
    Check(replied, "No channel response");
    return success;
  }
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
};

std::wstring Property(HWND window, const PROPERTYKEY& key) {
  IPropertyStore* store = nullptr;
  Check(SUCCEEDED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&store))), "No window property store");
  PROPVARIANT value{};
  const HRESULT status = store->GetValue(key, &value);
  store->Release();
  Check(SUCCEEDED(status), "Cannot read window property");
  std::wstring result = value.vt == VT_LPWSTR ? value.pwszVal : L"";
  PropVariantClear(&value);
  return result;
}

int main() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  Check(SUCCEEDED(SetCurrentProcessExplicitAppUserModelID(kAppUserModelId)), "Cannot set process identity");
  PWSTR process_id = nullptr;
  Check(SUCCEEDED(GetCurrentProcessExplicitAppUserModelID(&process_id)), "Cannot read process identity");
  const bool correct_process_id = std::wstring(process_id) == kAppUserModelId;
  CoTaskMemFree(process_id);
  Check(correct_process_id, "Wrong startup identity");
  int result = 0;
  HWND window = CreateWindowExW(0, L"STATIC", L"OCO appearance test", WS_OVERLAPPEDWINDOW,
                               0, 0, 320, 240, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  try {
    TestShortcuts();
    Check(window != nullptr, "Cannot create hidden test window");
    Messenger messenger;
    {
      WindowAppearance appearance(window, &messenger);
      Check(Property(window, PKEY_AppUserModel_ID) == kAppUserModelId, "Missing identity before settings load");
      wchar_t name[256];
      Check(SUCCEEDED(SHLoadIndirectString(Property(window, PKEY_AppUserModel_RelaunchDisplayNameResource).c_str(), name, ARRAYSIZE(name), nullptr)), "Cannot resolve shell display name");
      Check(std::wstring(name) == L"Open Campus Organizer", "Wrong shell display name");
      const char* themes[] = {"dark", "light", "warm", "sage", "orange"};
      wchar_t executable[32768];
      GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
      for (int round = 0; round < 3; ++round) {
        for (int i = 0; i < 5; ++i) {
          Check(messenger.Theme(themes[i]), "Theme update failed");
          Check(SendMessageW(window, WM_GETICON, ICON_BIG, 0) != 0, "Missing large icon");
          Check(SendMessageW(window, WM_GETICON, ICON_SMALL, 0) != 0, "Missing small icon");
          Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) ==
                    std::wstring(executable) + L",-" + std::to_wstring(101 + i), "Wrong taskbar icon resource");
          Check(Property(window, PKEY_AppUserModel_ID) == L"Nononoyuyuyu.OpenCampusOrganizer", "Wrong application ID");
          appearance.RefreshForDpi(144);
          ICONINFO info{};
          Check(GetIconInfo(reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, ICON_BIG, 0)), &info) != 0, "Cannot inspect DPI icon");
          BITMAP bitmap{};
          GetObject(info.hbmColor, sizeof(bitmap), &bitmap);
          DeleteObject(info.hbmColor); DeleteObject(info.hbmMask);
          Check(bitmap.bmWidth == GetSystemMetricsForDpi(SM_CXICON, 144), "Wrong DPI size");
          appearance.RefreshTaskbar();
          Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) ==
                    std::wstring(executable) + L",-" + std::to_wstring(101 + i), "Theme lost after shell refresh");
        }
      }
      const auto before = Property(window, PKEY_AppUserModel_RelaunchIconResource);
      Check(!messenger.Theme("unknown"), "Invalid theme accepted");
      Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) == before, "Invalid theme changed icon");
    }
    Check(Property(window, PKEY_AppUserModel_ID).empty(), "Properties left after disposal");
    Check(SendMessageW(window, WM_GETICON, ICON_BIG, 0) == 0, "Icon left after disposal");
    std::cout << "PASS: 5 themes, repeated updates, shell properties, DPI, refresh, invalid theme, disposal\n";
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
  if (window) DestroyWindow(window);
  CoUninitialize();
  return result;
}
