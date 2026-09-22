#ifndef RUNNER_WINDOW_APPEARANCE_H_
#define RUNNER_WINDOW_APPEARANCE_H_

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <filesystem>
#include "shortcut_appearance.h"

// ウィンドウ表示とOSリソースの所有権をFlutter画面から分離する。
class WindowAppearance {
 public:
  WindowAppearance(HWND window, flutter::BinaryMessenger* messenger,
                   const std::filesystem::path& shell_icon_directory = {},
                   ShellChangeNotifier notify = SHChangeNotify);
  ~WindowAppearance();
  void RefreshForDpi(UINT dpi);
  void RefreshTaskbar();

 private:
  bool SetIcon(int resource_id, UINT dpi);
  bool SetWindowIcons(int resource_id, UINT dpi);
  bool UpdateTaskbarIcon();
  void ClearTaskbarProperties();
  HWND window_;
  int resource_id_;
  std::filesystem::path shell_icon_directory_;
  std::filesystem::path shell_icon_path_;
  HICON large_icon_ = nullptr;
  HICON small_icon_ = nullptr;
  ShellChangeNotifier notify_;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif  // RUNNER_WINDOW_APPEARANCE_H_
