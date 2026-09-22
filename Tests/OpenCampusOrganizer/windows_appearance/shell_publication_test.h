#ifndef TESTS_SHELL_PUBLICATION_TEST_H_
#define TESTS_SHELL_PUBLICATION_TEST_H_

// Shellの描画成功を模擬しない。再取得を促す時点の実ウィンドウ・実リンクを検査する。
// グローバル通知は記録だけにして、通常のCI/単体テストで利用者のデスクトップを更新しない。
class ShellPublicationObserver {
 public:
  explicit ShellPublicationObserver(HWND window) : window_(window) {
    Check(active_ == nullptr, "Overlapping publication observers");
    active_ = this;
    Check(SetWindowSubclass(window_, Handle, 1, reinterpret_cast<DWORD_PTR>(this)) != 0,
          "Cannot observe window icon publication");
  }
  ~ShellPublicationObserver() {
    RemoveWindowSubclass(window_, Handle, 1);
    active_ = nullptr;
  }
  std::wstring expected_icon;
  int expected_resource = 0;
  int associations = 0;
  int items = 0;
  bool metadata_ready = true;
  bool pixels_ready = true;
  bool links_readable = true;
  std::vector<LONG> events;

  static void WINAPI Notify(LONG event, UINT flags, LPCVOID first, LPCVOID second) {
    auto& self = *active_;
    self.events.push_back(event);
    self.metadata_ready &= Property(self.window_, PKEY_AppUserModel_RelaunchIconResource) == self.expected_icon;
    if (self.expected_resource) {
      const auto expected = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr),
          MAKEINTRESOURCEW(self.expected_resource), IMAGE_ICON, 32, 32, 0));
      const auto actual = reinterpret_cast<HICON>(SendMessageW(self.window_, WM_GETICON, ICON_BIG, 0));
      self.pixels_ready &= expected && actual &&
          IconPixels(actual, 32)[16 * 32 + 16] == IconPixels(expected, 32)[16 * 32 + 16];
      if (expected) DestroyIcon(expected);
    }
    if (event == SHCNE_ASSOCCHANGED) {
      ++self.associations;
      Check((flags & SHCNF_TYPE) == SHCNF_IDLIST && !first && !second,
            "Invalid association notification");
      return;
    }
    if (event == SHCNE_UPDATEITEM) {
      ++self.items;
      Check((flags & SHCNF_TYPE) == SHCNF_IDLIST && first && !second,
            "Item notification needs an absolute PIDL");
      wchar_t path[32768]{};
      if (SHGetPathFromIDListEx(static_cast<PCIDLIST_ABSOLUTE>(first), path, ARRAYSIZE(path), GPFIDL_DEFAULT)) {
        ComPtr<IShellLinkW> link;
        ComPtr<IPersistFile> file;
        bool readable = SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                                   IID_PPV_ARGS(&link))) &&
                        SUCCEEDED(link.As(&file)) && SUCCEEDED(file->Load(path, STGM_READ));
        wchar_t icon[32768]{};
        int index = 0;
        readable = readable && SUCCEEDED(link->GetIconLocation(icon, ARRAYSIZE(icon), &index)) &&
                   std::wstring(icon) + L",0" == self.expected_icon && index == 0;
        self.links_readable &= readable;
      }
      // 個別のテスト用リンク通知は実際のShellへも届ける。
      SHChangeNotify(event, flags, first, second);
    }
  }

 private:
  static LRESULT CALLBACK Handle(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                                 UINT_PTR, DWORD_PTR context) {
    auto& self = *reinterpret_cast<ShellPublicationObserver*>(context);
    if (message == WM_SETICON && lparam && !self.expected_icon.empty()) {
      self.metadata_ready &= Property(window, PKEY_AppUserModel_RelaunchIconResource) == self.expected_icon;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }
  inline static ShellPublicationObserver* active_ = nullptr;
  HWND window_;
};

void TestDeferredShortcutPublication(ShellPublicationObserver& observer,
                                     const std::filesystem::path& icon_directory,
                                     const std::filesystem::path& icon) {
  const auto directory = icon_directory / L"shortcuts";
  Check(std::filesystem::create_directory(directory), "Cannot create notification fixture");
  const auto path = directory / L"Deferred OCO.lnk";
  wchar_t executable[32768]{};
  GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  {
    ComPtr<IShellLinkW> link;
    ComPtr<IPersistFile> file;
    Check(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&link))), "Cannot create deferred shortcut");
    link->SetPath(executable);
    link->SetIconLocation(executable, -101);
    link.As(&file);
    Check(SUCCEEDED(file->Save(path.c_str(), TRUE)), "Cannot save deferred shortcut");
  }
  for (int retry = 0; retry < 2; ++retry) {
    AppearanceShortcutUpdates pending;
    const auto timestamp = std::filesystem::last_write_time(path);
    Check(UpdateAppearanceShortcuts(directory, executable, icon, 0, &pending),
          "Cannot stage shortcut publication");
    Check(pending.size() == 1 && pending[0].path == path, "Updated link lost its pending notification");
    if (retry) Check(std::filesystem::last_write_time(path) == timestamp,
                     "Notification retry rewrote an unchanged shortcut");
    observer.events.clear();
    const int items_before = observer.items;
    NotifyAppearanceShortcuts(pending, true, ShellPublicationObserver::Notify);
    Check(observer.events.size() >= 2 && observer.events[0] == SHCNE_ASSOCCHANGED &&
          observer.events[1] == SHCNE_UPDATEITEM, "Shortcut refresh preceded cache invalidation");
    Check(observer.items > items_before && observer.links_readable,
          "Consumer could not reread the new shortcut icon at notification time");
    CheckShellIcon(path, 104, true);
  }
  std::filesystem::remove(path);
  std::filesystem::remove(directory);
}

#endif
