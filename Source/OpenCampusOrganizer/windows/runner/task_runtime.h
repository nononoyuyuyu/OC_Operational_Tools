#ifndef RUNNER_TASK_RUNTIME_H_
#define RUNNER_TASK_RUNTIME_H_
#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <optional>

class TaskRuntime {
 public:
  TaskRuntime(HWND window, flutter::BinaryMessenger* messenger);
  ~TaskRuntime();
  std::optional<LRESULT> Handle(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  void Tray(bool enabled);
  void Open();
  void RequestExit();
  HWND window_;
  bool tray_ = false, ready_ = false, exiting_ = false;
  UINT taskbar_created_;
  NOTIFYICONDATAW icon_{};
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};
#endif
