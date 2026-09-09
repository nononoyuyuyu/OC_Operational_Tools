#include "window_appearance.h"

#include <flutter/standard_method_codec.h>
#include <string>
#include <shobjidl.h>
#include <propkey.h>
#include <wrl/client.h>

#include "resource.h"
#include "shortcut_appearance.h"
#include "taskbar_properties.h"

WindowAppearance::WindowAppearance(HWND window,
                                   flutter::BinaryMessenger* messenger)
    : window_(window),
      resource_id_(IDI_APP_ICON),
      channel_(messenger, "jp.nononoyuyuyu.open_campus_organizer/appearance",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setTheme") {
          result->NotImplemented();
          return;
        }
        const auto* theme = call.arguments()
                                ? std::get_if<std::string>(call.arguments())
                                : nullptr;
        int resource_id = 0;
        if (theme) {
          if (*theme == "dark") resource_id = IDI_APP_ICON;
          if (*theme == "light") resource_id = IDI_APP_ICON_LIGHT;
          if (*theme == "warm") resource_id = IDI_APP_ICON_WARM;
          if (*theme == "sage") resource_id = IDI_APP_ICON_SAGE;
          if (*theme == "orange") resource_id = IDI_APP_ICON_ORANGE;
        }
        if (resource_id == 0) {
          result->Error("invalid_theme", "配色を確認してください。");
        } else if (!SetIcon(resource_id, GetDpiForWindow(window_))) {
          result->Error("icon_unavailable", "アイコンを変更できませんでした。");
        } else {
          result->Success();
        }
      });
  // 最初のフレームを表示する前に既定の再起動情報を渡す。
  // 保存済み配色は後続のsetThemeで更新し、失敗時も同経路で再試行する。
  UpdateTaskbarIcon(resource_id_);
}

WindowAppearance::~WindowAppearance() {
  channel_.SetMethodCallHandler(nullptr);
  if (IsWindow(window_)) {
    ClearTaskbarProperties();
    SendMessageW(window_, WM_SETICON, ICON_BIG, 0);
    SendMessageW(window_, WM_SETICON, ICON_SMALL, 0);
  }
  if (large_icon_) DestroyIcon(large_icon_);
  if (small_icon_) DestroyIcon(small_icon_);
}

bool WindowAppearance::SetWindowIcons(int resource_id, UINT dpi) {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  // サイズごとに専用ハンドルを作り、切替後に自分が所有する旧ハンドルだけ解放する。
  const auto next_large_icon = static_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(resource_id), IMAGE_ICON,
      GetSystemMetricsForDpi(SM_CXICON, dpi),
      GetSystemMetricsForDpi(SM_CYICON, dpi), LR_DEFAULTCOLOR));
  const auto next_small_icon = static_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(resource_id), IMAGE_ICON,
      GetSystemMetricsForDpi(SM_CXSMICON, dpi),
      GetSystemMetricsForDpi(SM_CYSMICON, dpi), LR_DEFAULTCOLOR));
  if (!next_large_icon || !next_small_icon) {
    if (next_large_icon) DestroyIcon(next_large_icon);
    if (next_small_icon) DestroyIcon(next_small_icon);
    return false;
  }
  SendMessageW(window_, WM_SETICON, ICON_BIG,
               reinterpret_cast<LPARAM>(next_large_icon));
  SendMessageW(window_, WM_SETICON, ICON_SMALL,
               reinterpret_cast<LPARAM>(next_small_icon));
  if (large_icon_) DestroyIcon(large_icon_);
  if (small_icon_) DestroyIcon(small_icon_);
  large_icon_ = next_large_icon;
  small_icon_ = next_small_icon;
  return true;
}

bool WindowAppearance::SetIcon(int resource_id, UINT dpi) {
  if (!SetWindowIcons(resource_id, dpi)) return false;
  resource_id_ = resource_id;
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  if (!length || length >= ARRAYSIZE(executable)) return false;
  // グループが参照するリンクを先に保存し、通知の配達を終えてから公開する。
  const bool shortcuts_updated = UpdateUserAppearanceShortcuts(executable, resource_id);
  // 一部リンクが書込不可でも実行中ウィンドウの更新と再試行経路は維持する。
  const bool taskbar_updated = UpdateTaskbarIcon(resource_id);
  // DeleteTab/AddTabでは既存グループのキャッシュ更新を保証できない。
  // 明示IDの再通知を使い、ボタンの削除・追加やウィンドウの非表示は行わない。
  return shortcuts_updated && taskbar_updated;
}

void WindowAppearance::RefreshForDpi(UINT dpi) {
  // DPI変更でリンクを再走査・再保存したり、タスクバーの所属を変更したりしない。
  SetWindowIcons(resource_id_, dpi);
}

bool WindowAppearance::UpdateTaskbarIcon(int resource_id) {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(SHGetPropertyStoreForWindow(window_, IID_PPV_ARGS(&properties)))) return false;
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  if (!length || length >= ARRAYSIZE(executable)) return false;
  return SetTaskbarAppearanceProperties(properties.Get(),
                                       std::wstring(executable, length), resource_id);
}

void WindowAppearance::ClearTaskbarProperties() {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(SHGetPropertyStoreForWindow(window_, IID_PPV_ARGS(&properties)))) return;
  const PROPVARIANT empty{};
  for (const auto& key : {PKEY_AppUserModel_ID, PKEY_AppUserModel_RelaunchCommand,
                         PKEY_AppUserModel_RelaunchDisplayNameResource,
                         PKEY_AppUserModel_RelaunchIconResource}) {
    properties->SetValue(key, empty);
  }
}

void WindowAppearance::RefreshTaskbar() {
  SetIcon(resource_id_, GetDpiForWindow(window_));
}
