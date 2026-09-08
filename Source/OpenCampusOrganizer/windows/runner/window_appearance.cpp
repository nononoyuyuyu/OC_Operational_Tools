#include "window_appearance.h"

#include <flutter/standard_method_codec.h>
#include <string>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include "resource.h"
#include "app_identity.h"
#include "shortcut_appearance.h"

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

bool WindowAppearance::SetIcon(int resource_id, UINT dpi) {
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
  resource_id_ = resource_id;
  if (!UpdateTaskbarIcon(resource_id)) return false;
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  if (!length || length >= ARRAYSIZE(executable)) return false;
  const bool shortcuts_updated = UpdateUserAppearanceShortcuts(executable, resource_id);
  // Explorerが保持するグループ表示も再取得させる。ウィンドウ自体は隠さない。
  if (IsWindowVisible(window_)) {
    Microsoft::WRL::ComPtr<ITaskbarList> taskbar;
    if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&taskbar))) && SUCCEEDED(taskbar->HrInit())) {
      if (SUCCEEDED(taskbar->DeleteTab(window_))) taskbar->AddTab(window_);
    }
  }
  return shortcuts_updated;
}

void WindowAppearance::RefreshForDpi(UINT dpi) {
  SetIcon(resource_id_, dpi);
}

bool WindowAppearance::UpdateTaskbarIcon(int resource_id) {
  // WM_SETICONだけではショートカット由来のグループアイコンが残る。
  // ウィンドウとインストーラーのAppUserModelIDを一致させ、参照リソースも更新する。
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(SHGetPropertyStoreForWindow(window_, IID_PPV_ARGS(&properties)))) return false;
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  if (!length || length >= ARRAYSIZE(executable)) return false;
  auto set = [&](const PROPERTYKEY& key, const std::wstring& text) {
    PROPVARIANT value{};
    HRESULT status = InitPropVariantFromString(text.c_str(), &value);
    if (SUCCEEDED(status)) status = properties->SetValue(key, value);
    PropVariantClear(&value);
    return SUCCEEDED(status);
  };
  const std::wstring path(executable, length);
  return set(PKEY_AppUserModel_RelaunchCommand, L"\"" + path + L"\"") &&
         set(PKEY_AppUserModel_RelaunchDisplayNameResource,
             L"@" + path + L",-" + std::to_wstring(IDS_APP_NAME)) &&
         set(PKEY_AppUserModel_RelaunchIconResource,
             path + L",-" + std::to_wstring(resource_id)) &&
         set(PKEY_AppUserModel_ID, kAppUserModelId);
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
