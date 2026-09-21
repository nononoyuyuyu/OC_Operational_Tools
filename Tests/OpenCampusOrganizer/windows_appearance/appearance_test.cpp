#include <windows.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <flutter/standard_method_codec.h>
#include <iostream>
#include <fstream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include "window_appearance.h"
#include "app_identity.h"
#include "shortcut_appearance.h"
#include "shell_icon.h"
#include "taskbar_properties_test.h"
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

#include "shell_icon_test.h"

void TestIconFiles() {
  wchar_t temporary[MAX_PATH];
  GetTempPathW(ARRAYSIZE(temporary), temporary);
  const auto directory = std::filesystem::path(temporary) /
      (L"oco-icon-files-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
  std::set<std::filesystem::path> files;
  std::filesystem::path icon;
  for (int resource = 101; resource <= 105; ++resource) {
    Check(PrepareShellIconFile(directory, resource, &icon), "Cannot export embedded ICO");
    files.insert(icon);
    Check(icon.parent_path() == directory && icon.extension() == L".ico" &&
          icon.stem().wstring().size() == 69, "Icon filename lacks content hash");
    const auto timestamp = std::filesystem::last_write_time(icon);
    std::ifstream file(icon, std::ios::binary);
    unsigned char header[6]{};
    file.read(reinterpret_cast<char*>(header), sizeof(header));
    file.close();
    Check(header[0] == 0 && header[1] == 0 && header[2] == 1 && header[3] == 0 &&
          header[4] == 9 && header[5] == 0, "Export lost ICO frames");
    for (int size : {16, 20, 24, 32, 40, 48, 64, 128, 256}) {
      const auto actual = static_cast<HICON>(LoadImageW(nullptr, icon.c_str(), IMAGE_ICON, size, size, LR_LOADFROMFILE));
      const auto expected = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(resource),
                                                        IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
      Check(actual && expected, "Cannot load exported icon size");
      const bool equal = IconPixels(actual, size) == IconPixels(expected, size);
      DestroyIcon(actual);
      DestroyIcon(expected);
      Check(equal, "Export changed embedded image pixels");
    }
    SetFileAttributesW(icon.c_str(), FILE_ATTRIBUTE_READONLY);
    std::filesystem::path retry;
    Check(PrepareShellIconFile(directory, resource, &retry) && retry == icon, "Cannot reuse read-only icon");
    Check(std::filesystem::last_write_time(icon) == timestamp, "Same theme rewrote cached image");
    SetFileAttributesW(icon.c_str(), FILE_ATTRIBUTE_NORMAL);
  }
  Check(files.size() == 5, "Distinct themes reused one cached filename");
  for (int resource = 101; resource <= 105; ++resource) {
    Check(PrepareShellIconFile(directory, resource, &icon) && files.count(icon), "Returning to a theme created a new image");
    CheckShellIcon(icon, resource);
  }
  const auto before = icon;
  Check(!PrepareShellIconFile(directory, 9999, &icon) && before == icon, "Invalid resource changed the selected file");
  Check(!PrepareShellIconFile(directory, 101, nullptr), "Null destination accepted");
  const auto blocked = directory / L"blocked";
  { std::ofstream file(blocked); file << "preserve"; }
  Check(!PrepareShellIconFile(blocked, 101, &icon) && before == icon, "File write failure changed the selected icon");
  std::filesystem::remove(blocked);
  Check(PrepareShellIconFile(blocked, 101, &icon), "Cannot recover from icon write failure");
  std::filesystem::remove(icon);
  std::filesystem::remove(blocked);
  // ハッシュ名の既存ファイルが破損していても、読み込み済みファイルを上書きしない。
  { std::ofstream file(before, std::ios::binary | std::ios::trunc); file << "invalid"; }
  Check(!PrepareShellIconFile(directory, 105, &icon), "Corrupt cached image was silently accepted or overwritten");
  for (const auto& path : files) std::filesystem::remove(path);
  std::filesystem::remove(directory);
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
  const auto icon_directory = directory / L"appearance";
  std::filesystem::path shell_icon;
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
  CheckShellIcon(owned, 101);
  CheckShellIcon(owned, 101, true);
  for (int round = 0; round < 3; ++round) {
    for (int resource = 101; resource <= 105; ++resource) {
      Check(PrepareShellIconFile(icon_directory, resource, &shell_icon), "Cannot prepare shell icon");
      Check(UpdateAppearanceShortcuts(directory, executable, shell_icon), "Cannot update shortcut icons");
      Check(UpdateAppearanceShortcuts(directory, executable, shell_icon), "Cannot retry same shortcut theme");
      CheckShellIcon(owned, resource);
      CheckShellIcon(owned, resource, true);
      CheckShellIcon(foreign, 101);
      for (const auto& path : {owned, foreign}) {
        ComPtr<IShellLinkW> link;
        ComPtr<IPersistFile> file;
        CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
        link.As(&file);
        Check(SUCCEEDED(file->Load(path.c_str(), STGM_READ)), "Cannot load updated link");
        wchar_t icon[32768], arguments[256], working[32768];
        int index = 0;
        link->GetIconLocation(icon, ARRAYSIZE(icon), &index);
        Check(std::wstring(icon) == (path == owned ? shell_icon.wstring() : executable) &&
              index == (path == owned ? 0 : -101), "Wrong shortcut changed");
        ComPtr<IPropertyStore> properties;
        link.As(&properties);
        PROPVARIANT saved{};
        properties->GetValue(PKEY_AppUserModel_RelaunchIconResource, &saved);
        Check(path == owned ? saved.vt == VT_LPWSTR && std::wstring(saved.pwszVal) == shell_icon.wstring() + L",0" : saved.vt == VT_EMPTY,
              "Pinned relaunch icon did not follow theme");
        PropVariantClear(&saved);
        link->GetArguments(arguments, ARRAYSIZE(arguments));
        link->GetWorkingDirectory(working, ARRAYSIZE(working));
        Check(std::wstring(arguments) == L"--preserve-this" && directory == working, "Shortcut parameters lost");
      }
    }
  }
  SetFileAttributesW(owned.c_str(), FILE_ATTRIBUTE_READONLY);
  Check(UpdateAppearanceShortcuts(directory, executable, shell_icon), "Unchanged read-only shortcut should succeed");
  Check(PrepareShellIconFile(icon_directory, 101, &shell_icon), "Cannot prepare next theme");
  Check(!UpdateAppearanceShortcuts(directory, executable, shell_icon), "Write failure was hidden");
  CheckShellIcon(owned, 105);
  SetFileAttributesW(owned.c_str(), FILE_ATTRIBUTE_NORMAL);
  Check(UpdateAppearanceShortcuts(directory, executable, shell_icon), "Cannot recover shortcut update");
  CheckShellIcon(owned, 101);
  // アップデートで同じ名前のリンクがEXEの既定アイコンへ戻された状態。
  ComPtr<IShellLinkW> reinstalled;
  ComPtr<IPersistFile> reinstalled_file;
  CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&reinstalled));
  reinstalled.As(&reinstalled_file);
  reinstalled->SetPath(executable);
  reinstalled->SetIconLocation(executable, 0);
  Check(SUCCEEDED(reinstalled_file->Save(owned.c_str(), TRUE)), "Cannot simulate installer shortcut replacement");
  Check(PrepareShellIconFile(icon_directory, 104, &shell_icon), "Cannot restore saved theme");
  Check(UpdateAppearanceShortcuts(directory, executable, shell_icon), "Cannot repair reinstalled shortcut");
  CheckShellIcon(owned, 104);
  std::filesystem::remove(owned);
  std::filesystem::remove(foreign);
  for (const auto& entry : std::filesystem::directory_iterator(icon_directory)) std::filesystem::remove(entry.path());
  std::filesystem::remove(icon_directory);
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
  int argument_count = 0;
  auto arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (argument_count == 4 && std::wstring(arguments[1]) == L"--inspect-shortcut") {
    int result = 0;
    try {
      const auto entry = ReadShellIconCacheEntry(arguments[2]);
      std::wcout << L"Icon cache: " << entry.file << L" resource=" << entry.resource_index
                 << L" flags=" << entry.flags << L" image=" << entry.image_index << L'\n';
      CheckShellIcon(arguments[2], _wtoi(arguments[3]));
      std::cout << "PASS: installed shortcut shell pixels match resource\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
    LocalFree(arguments);
    CoUninitialize();
    return result;
  }
  LocalFree(arguments);
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
    ShellImageObserver shell;
    TestTaskbarProperties();
    TestIconFiles();
    TestShortcuts();
    Check(shell.updates > 0, "No image invalidation reached the shell consumer");
    Check(window != nullptr, "Cannot create test window");
    Messenger messenger;
    {
      wchar_t temporary[MAX_PATH];
      GetTempPathW(ARRAYSIZE(temporary), temporary);
      const auto icon_directory = std::filesystem::path(temporary) /
          (L"oco-window-icon-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
      std::filesystem::path shell_icon;
      WindowAppearance appearance(window, &messenger, icon_directory);
      Check(Property(window, PKEY_AppUserModel_ID) == kAppUserModelId, "Missing identity before settings load");
      wchar_t name[256];
      Check(SUCCEEDED(SHLoadIndirectString(Property(window, PKEY_AppUserModel_RelaunchDisplayNameResource).c_str(), name, ARRAYSIZE(name), nullptr)), "Cannot resolve shell display name");
      Check(std::wstring(name) == L"Open Campus Organizer", "Wrong shell display name");
      const char* themes[] = {"dark", "light", "warm", "sage", "orange"};
      wchar_t executable[32768];
      GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
      ShowWindow(window, SW_SHOWNOACTIVATE);
      for (int round = 0; round < 3; ++round) {
        for (int i = 0; i < 5; ++i) {
          Check(messenger.Theme(themes[i]), "Theme update failed");
          Check(messenger.Theme(themes[i]), "Same-theme retry failed");
          Check(PrepareShellIconFile(icon_directory, 101 + i, &shell_icon), "Cannot resolve expected icon file");
          Check(IsWindowVisible(window) != 0, "Theme update hid the window");
          Check(SendMessageW(window, WM_GETICON, ICON_BIG, 0) != 0, "Missing large icon");
          Check(SendMessageW(window, WM_GETICON, ICON_SMALL, 0) != 0, "Missing small icon");
          Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) ==
                    shell_icon.wstring() + L",0", "Wrong taskbar icon resource");
          CheckShellIcon(shell_icon, 101 + i);
          Check(Property(window, PKEY_AppUserModel_ID) == kAppUserModelId, "Wrong application ID");
          appearance.RefreshForDpi(144);
          ICONINFO info{};
          Check(GetIconInfo(reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, ICON_BIG, 0)), &info) != 0, "Cannot inspect DPI icon");
          BITMAP bitmap{};
          GetObject(info.hbmColor, sizeof(bitmap), &bitmap);
          DeleteObject(info.hbmColor); DeleteObject(info.hbmMask);
          Check(bitmap.bmWidth == GetSystemMetricsForDpi(SM_CXICON, 144), "Wrong DPI size");
          Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) ==
                    shell_icon.wstring() + L",0", "DPI update changed taskbar metadata");
          appearance.RefreshTaskbar();
          Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) ==
                    shell_icon.wstring() + L",0", "Theme lost after shell refresh");
          CheckShellIcon(shell_icon, 101 + i);
        }
      }
      ShowWindow(window, SW_MINIMIZE);
      Check(messenger.Theme("sage"), "Minimized theme update failed");
      Check(IsIconic(window) != 0, "Theme update restored a minimized window");
      const auto before = Property(window, PKEY_AppUserModel_RelaunchIconResource);
      Check(!messenger.Theme("unknown"), "Invalid theme accepted");
      Check(Property(window, PKEY_AppUserModel_RelaunchIconResource) == before, "Invalid theme changed icon");
      CheckShellIcon(std::filesystem::path(before.substr(0, before.size() - 2)), 104);
      for (const auto& entry : std::filesystem::directory_iterator(icon_directory)) std::filesystem::remove(entry.path());
      std::filesystem::remove(icon_directory);
    }
    Check(Property(window, PKEY_AppUserModel_ID).empty(), "Properties left after disposal");
    Check(SendMessageW(window, WM_GETICON, ICON_BIG, 0) == 0, "Icon left after disposal");
    std::cout << "PASS: 5 themes x 9 exported sizes, immutable cache, write failure/retry, shell pixels and image notifications, repeated shortcut updates, installer replacement, DPI, refresh, minimized window, disposal\n";
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
  if (window) DestroyWindow(window);
  CoUninitialize();
  return result;
}
