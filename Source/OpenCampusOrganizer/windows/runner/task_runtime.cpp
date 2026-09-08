#include "task_runtime.h"
#include <flutter/standard_method_codec.h>
#include <string>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 42;
std::wstring Wide(const std::string& text) {
  if (text.empty()) return L"";
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}
}

TaskRuntime::TaskRuntime(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window), taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")),
      channel_(messenger, "jp.nononoyuyuyu.open_campus_organizer/runtime", &flutter::StandardMethodCodec::GetInstance()) {
  icon_.cbSize = sizeof(icon_);
  icon_.hWnd = window_;
  icon_.uID = 1;
  icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  icon_.uCallbackMessage = kTrayMessage;
  icon_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon_.szTip, L"Open Campus Organizer");
  channel_.SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    auto get = [args](const char* key) -> const flutter::EncodableValue* {
      if (!args) return nullptr;
      auto it = args->find(flutter::EncodableValue(key));
      return it == args->end() ? nullptr : &it->second;
    };
    const auto& method = call.method_name();
    if (method == "configure") {
      const auto* value = get("trayEnabled");
      if (!value || !std::holds_alternative<bool>(*value)) { result->Error("invalid_settings", "設定を確認してください。"); return; }
      ready_ = true;
      Tray(std::get<bool>(*value));
      if (!tray_ && !IsWindowVisible(window_)) Open();
      if (std::get<bool>(*value) && !tray_) { result->Error("tray_unavailable", "タスクトレイを表示できませんでした。"); return; }
    } else if (method == "progress" || method == "finish") {
      const auto* value = get("message");
      if (value && std::holds_alternative<std::string>(*value)) {
        const auto text = Wide(std::get<std::string>(*value));
        wcsncpy_s(icon_.szTip, text.c_str(), _TRUNCATE);
        if (tray_) Shell_NotifyIconW(NIM_MODIFY, &icon_);
      }
    } else if (method == "exit") {
      exiting_ = true;
      PostMessageW(window_, WM_CLOSE, 0, 0);
    } else if (method != "begin") { result->NotImplemented(); return; }
    result->Success();
  });
}
TaskRuntime::~TaskRuntime() { Tray(false); channel_.SetMethodCallHandler(nullptr); }
void TaskRuntime::Tray(bool enabled) {
  if (enabled && !tray_) {
    if (!Shell_NotifyIconW(NIM_ADD, &icon_)) return;
  } else if (!enabled && tray_) { Shell_NotifyIconW(NIM_DELETE, &icon_); }
  tray_ = enabled;
}
void TaskRuntime::Open() {
  ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
  channel_.InvokeMethod("foreground", nullptr);
}
void TaskRuntime::RequestExit() {
  Open();
  if (ready_) channel_.InvokeMethod("closeRequested", nullptr);
  else if (MessageBoxW(window_, L"Open Campus Organizerを終了しますか？", L"終了の確認", MB_OKCANCEL | MB_ICONQUESTION) == IDOK) {
    exiting_ = true;
    PostMessageW(window_, WM_CLOSE, 0, 0);
  }
}
std::optional<LRESULT> TaskRuntime::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == taskbar_created_ && tray_) { tray_ = false; Tray(true); return 0; }
  switch (message) {
    case WM_CLOSE:
      if (exiting_) return std::nullopt;
      if (tray_) { ShowWindow(window_, SW_HIDE); channel_.InvokeMethod("background", nullptr); }
      else RequestExit();
      return 0;
    case WM_QUERYENDSESSION:
      channel_.InvokeMethod("suspend", nullptr);
      return TRUE;
    case WM_ENDSESSION:
      if (wparam) { exiting_ = true; PostMessageW(window_, WM_CLOSE, 0, 0); }
      break;
    case WM_SETICON:
      if (wparam == ICON_SMALL && lparam) {
        icon_.hIcon = reinterpret_cast<HICON>(lparam);
        if (tray_) Shell_NotifyIconW(NIM_MODIFY, &icon_);
      }
      break;
    case kTrayMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) Open();
      else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
        POINT cursor; GetCursorPos(&cursor);
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, 1, L"開く");
        AppendMenuW(menu, MF_STRING, 2, L"終了");
        SetForegroundWindow(window_);
        const int action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, window_, nullptr);
        DestroyMenu(menu);
        if (action == 1) Open();
        if (action == 2) RequestExit();
        PostMessageW(window_, WM_NULL, 0, 0);
      }
      return 0;
  }
  return std::nullopt;
}
