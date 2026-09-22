#ifndef RUNNER_SHORTCUT_APPEARANCE_H_
#define RUNNER_SHORTCUT_APPEARANCE_H_

#include <filesystem>
#include <string>
#include <vector>
#include <shlobj.h>
#include "shell_icon.h"

struct AppearanceShortcutUpdate {
  std::filesystem::path path;
  ShellIconCacheEntry previous_icon;
};
using AppearanceShortcutUpdates = std::vector<AppearanceShortcutUpdate>;
using ShellChangeNotifier = decltype(&SHChangeNotify);
using AppearanceFolderResolver = decltype(&SHGetKnownFolderPath);

// 指定EXEを起動する既存リンクだけを更新する。ピン留めの追加・解除は行わない。
bool UpdateAppearanceShortcuts(const std::filesystem::path& directory,
                               const std::wstring& executable, const std::filesystem::path& icon_path,
                               int max_depth = 4, AppearanceShortcutUpdates* pending = nullptr);
bool UpdateUserAppearanceShortcuts(const std::wstring& executable, const std::filesystem::path& icon_path,
                                  AppearanceShortcutUpdates* pending = nullptr,
                                  AppearanceFolderResolver resolve_folder = SHGetKnownFolderPath);

// pendingを渡した更新では通知を保留する。リンクとウィンドウの情報を揃えてから呼ぶ。
// global_refreshはテーマ適用・再試行時だけ有効にし、DPI変更では呼ばない。
void NotifyAppearanceShortcuts(const AppearanceShortcutUpdates& updates, bool global_refresh,
                               ShellChangeNotifier notify = SHChangeNotify);

#endif
