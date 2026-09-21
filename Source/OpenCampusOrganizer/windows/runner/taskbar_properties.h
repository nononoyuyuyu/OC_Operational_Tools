#ifndef RUNNER_TASKBAR_PROPERTIES_H_
#define RUNNER_TASKBAR_PROPERTIES_H_

#include <windows.h>
#include <propsys.h>
#include <propkey.h>
#include <propvarutil.h>
#include <string>

#include "app_identity.h"
#include "resource.h"

// ショートカットの変更通知を配達した後で呼ぶ。
// IDは固定する。表示済み画像の更新はshell_icon側のSHUpdateImageが担当する。
inline bool SetTaskbarAppearanceProperties(IPropertyStore* properties,
                                          const std::wstring& executable,
                                          const std::wstring& icon_path) {
  const auto set = [&](const PROPERTYKEY& key, const std::wstring& text) {
    PROPVARIANT value{};
    HRESULT status = InitPropVariantFromString(text.c_str(), &value);
    if (SUCCEEDED(status)) status = properties->SetValue(key, value);
    PropVariantClear(&value);
    return SUCCEEDED(status);
  };
  if (!set(PKEY_AppUserModel_RelaunchCommand, L"\"" + executable + L"\"") ||
      !set(PKEY_AppUserModel_RelaunchDisplayNameResource,
           L"@" + executable + L",-" + std::to_wstring(IDS_APP_NAME)) ||
      !set(PKEY_AppUserModel_RelaunchIconResource,
           icon_path + L",0")) return false;

  // 空にしてもプロセスの同じIDを継承するため、キャッシュ無効化にはならない。
  return set(PKEY_AppUserModel_ID, kAppUserModelId);
}

#endif  // RUNNER_TASKBAR_PROPERTIES_H_
