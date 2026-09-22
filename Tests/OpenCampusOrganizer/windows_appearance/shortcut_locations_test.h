#ifndef TESTS_SHORTCUT_LOCATIONS_TEST_H_
#define TESTS_SHORTCUT_LOCATIONS_TEST_H_

// Known Folderの解決だけを差し替え、製品と同じ走査経路を一時領域で検証する。
namespace shortcut_locations_test {
inline std::filesystem::path root;

HRESULT WINAPI ResolveFolder(REFKNOWNFOLDERID folder, DWORD, HANDLE, PWSTR* result) {
  const wchar_t* name = nullptr;
  if (IsEqualGUID(folder, FOLDERID_Programs)) name = L"Programs";
  if (IsEqualGUID(folder, FOLDERID_Desktop)) name = L"Desktop";
  if (IsEqualGUID(folder, FOLDERID_RoamingAppData)) name = L"Roaming";
  if (IsEqualGUID(folder, FOLDERID_ImplicitAppShortcuts)) name = L"Implicit";
  if (!name) return E_INVALIDARG;
  return SHStrDupW((root / name).c_str(), result);
}
}

void TestUserShortcutLocations() {
  using namespace shortcut_locations_test;
  wchar_t temporary[MAX_PATH]{};
  Check(GetTempPathW(ARRAYSIZE(temporary), temporary) != 0, "No test temporary directory");
  root = std::filesystem::path(temporary) /
      (L"oco-shortcut-locations-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
       std::to_wstring(GetTickCount64()));
  Check(std::filesystem::create_directory(root), "Cannot create location fixture");
  struct Cleanup {
    std::filesystem::path directory;
    ~Cleanup() { std::error_code error; std::filesystem::remove_all(directory, error); }
  } cleanup{root};
  struct Fixture { const wchar_t* relative; bool owned; bool updated; };
  const Fixture fixtures[] = {
    {L"Programs/Organizer/App.lnk", true, true},
    {L"Desktop/App.lnk", true, true},
    {L"Desktop/Private/App.lnk", true, false},
    {L"Roaming/Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar/App.lnk", true, true},
    {L"Roaming/Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar/Private/App.lnk", true, false},
    {L"Implicit/group-one/App.lnk", true, true},
    {L"Implicit/group-two/Renamed.lnk", true, true},
    {L"Implicit/group-one/Other.lnk", false, false},
    {L"Implicit/group-one/Private/App.lnk", true, false},
  };
  wchar_t executable[32768]{};
  GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  std::set<std::filesystem::path> expected;
  for (const auto& fixture : fixtures) {
    const auto path = root / fixture.relative;
    std::filesystem::create_directories(path.parent_path());
    ComPtr<IShellLinkW> link;
    ComPtr<IPersistFile> file;
    Check(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&link))) && SUCCEEDED(link.As(&file)),
          "Cannot create location shortcut");
    Check(SUCCEEDED(link->SetPath(fixture.owned ? executable : L"C:\\Windows\\notepad.exe")) &&
          SUCCEEDED(link->SetIconLocation(executable, -101)) &&
          SUCCEEDED(link->SetArguments(L"--keep-argument")) &&
          SUCCEEDED(file->Save(path.c_str(), TRUE)), "Cannot save location shortcut");
    if (fixture.updated) expected.insert(path);
  }
  for (int resource : {104, 101, 105, 104}) {
    std::filesystem::path icon;
    Check(PrepareShellIconFile(root / L"icons", resource, &icon), "Cannot prepare location icon");
    AppearanceShortcutUpdates pending;
    Check(UpdateUserAppearanceShortcuts(executable, icon, &pending, ResolveFolder),
          "Cannot update user shortcut locations");
    std::set<std::filesystem::path> actual;
    for (const auto& update : pending) actual.insert(update.path);
    Check(actual == expected && pending.size() == expected.size(),
          "Taskbar or implicit shortcut omitted, or unrelated directory traversed");
    for (const auto& fixture : fixtures) {
      ComPtr<IShellLinkW> link;
      ComPtr<IPersistFile> file;
      Check(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&link))) && SUCCEEDED(link.As(&file)) &&
            SUCCEEDED(file->Load((root / fixture.relative).c_str(), STGM_READ)),
            "Cannot reload location shortcut");
      wchar_t actual_icon[32768]{}, arguments[256]{};
      int index = 0;
      Check(SUCCEEDED(link->GetIconLocation(actual_icon, ARRAYSIZE(actual_icon), &index)) &&
            std::wstring(actual_icon) == (fixture.updated ? icon.wstring() : executable) &&
            index == (fixture.updated ? 0 : -101), "Wrong location icon");
      Check(SUCCEEDED(link->GetArguments(arguments, ARRAYSIZE(arguments))) &&
            std::wstring(arguments) == L"--keep-argument", "Location update lost launch argument");
    }
  }
}

#endif
