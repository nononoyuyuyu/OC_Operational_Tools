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
// 同じIDの再代入だけに依存せず、メタデータを揃えてから明示的に再通知する。
inline bool SetTaskbarAppearanceProperties(IPropertyStore* properties,
                                          const std::wstring& executable,
                                          int resource_id) {
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
           executable + L",-" + std::to_wstring(resource_id))) return false;

  // プロセスとショートカットの固定IDは変更しない。
  // ウィンドウの明示IDだけをリセットし、既存のグループへ最新情報を公開する。
  const PROPVARIANT empty{};
  if (FAILED(properties->SetValue(PKEY_AppUserModel_ID, empty))) return false;
  return set(PKEY_AppUserModel_ID, kAppUserModelId);
}

#endif  // RUNNER_TASKBAR_PROPERTIES_H_
