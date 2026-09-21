#ifndef RUNNER_SHELL_ICON_H_
#define RUNNER_SHELL_ICON_H_

#include <windows.h>
#include <filesystem>
#include <string>

// SHUpdateImageへは、変更前にShellが参照していた画像の場所とインデックスを渡す。
struct ShellIconCacheEntry {
  std::wstring file;
  int resource_index = 0;
  UINT flags = 0;
  int image_index = -1;
};

ShellIconCacheEntry ReadShellIconCacheEntry(const std::filesystem::path& path);
void NotifyShellIconChanged(const ShellIconCacheEntry& entry);
std::filesystem::path UserAppearanceIconDirectory();

// 全サイズの埋込ICOをユーザー専用ディレクトリへ保存する。
// 内容のSHA-256をファイル名に含め、読み込み済みの画像を上書きしない。
// 成功時だけpathを設定する。既存画像はバイト列まで一致を確認して再利用する。
bool PrepareShellIconFile(const std::filesystem::path& directory, int resource_id,
                          std::filesystem::path* path);

#endif  // RUNNER_SHELL_ICON_H_
