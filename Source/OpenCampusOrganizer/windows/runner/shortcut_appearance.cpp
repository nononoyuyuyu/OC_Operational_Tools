#include "shortcut_appearance.h"

#include <windows.h>
#include <shlobj.h>
#include <wrl/client.h>
#include <propkey.h>
#include <propvarutil.h>
#include "app_identity.h"
#include "shell_icon.h"

namespace {
bool UpdateLink(const std::filesystem::path& path,
                const std::wstring& executable, const std::filesystem::path& icon_path,
                AppearanceShortcutUpdates* pending) {
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  Microsoft::WRL::ComPtr<IPersistFile> file;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&link))) ||
      FAILED(link.As(&file)) || FAILED(file->Load(path.c_str(), STGM_READ))) return true;
  wchar_t target[32768]{};
  // Resolveはリンク先へのアクセスやダイアログを起こすため使わない。
  if (FAILED(link->GetPath(target, ARRAYSIZE(target), nullptr, SLGP_RAWPATH)) ||
      _wcsicmp(target, executable.c_str()) != 0) return true;
  wchar_t icon[32768]{};
  int index = 0;
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(link.As(&properties))) return false;
  const auto read = [&](const PROPERTYKEY& key) {
    PROPVARIANT value{};
    PWSTR raw = nullptr;
    std::wstring text;
    // インストーラーはVT_BSTR、アプリ自身はVT_LPWSTRで保存する。
    // 同じ文字列を別型でSetValueしても既存の型は残るため、両方を読む。
    if (SUCCEEDED(properties->GetValue(key, &value)) &&
        (value.vt == VT_LPWSTR || value.vt == VT_BSTR) &&
        SUCCEEDED(PropVariantToStringAlloc(value, &raw)) && raw) text = raw;
    CoTaskMemFree(raw);
    PropVariantClear(&value);
    return text;
  };
  const auto previous = ReadShellIconCacheEntry(path);
  const std::wstring relaunch_icon = icon_path.wstring() + L",0";
  if (SUCCEEDED(link->GetIconLocation(icon, ARRAYSIZE(icon), &index)) &&
      _wcsicmp(icon, icon_path.c_str()) == 0 && index == 0 &&
      read(PKEY_AppUserModel_ID) == kAppUserModelId &&
      read(PKEY_AppUserModel_RelaunchIconResource) == relaunch_icon) {
    // 再試行ではファイルを再保存せず通知だけをやり直す。
    pending->push_back({path, previous});
    return true;
  }
  // 変更不要な読取専用リンクは成功とし、書換えが必要な場合だけ書込権限を要求する。
  if (FAILED(file->Load(path.c_str(), STGM_READWRITE))) return false;
  const auto set = [&](const PROPERTYKEY& key, const wchar_t* text) {
    PROPVARIANT value{};
    HRESULT status = InitPropVariantFromString(text, &value);
    if (SUCCEEDED(status)) status = properties->SetValue(key, value);
    PropVariantClear(&value);
    return SUCCEEDED(status);
  };
  // ピン留めで複製された再起動情報に旧リソースが残る場合も揃える。
  if (!set(PKEY_AppUserModel_RelaunchIconResource, relaunch_icon.c_str()) ||
      !set(PKEY_AppUserModel_ID, kAppUserModelId) || FAILED(properties->Commit())) return false;
  if (FAILED(link->SetIconLocation(icon_path.c_str(), 0)) ||
      FAILED(file->Save(path.c_str(), TRUE))) return false;
  // COMオブジェクトを解放する前には通知しない。呼出側で全更新後に通知する。
  pending->push_back({path, previous});
  return true;
}
}

bool UpdateAppearanceShortcuts(const std::filesystem::path& directory,
                               const std::wstring& executable, const std::filesystem::path& icon_path,
                               int max_depth, AppearanceShortcutUpdates* pending) {
  AppearanceShortcutUpdates local_updates;
  auto* updates = pending ? pending : &local_updates;
  std::error_code error;
  if (!std::filesystem::exists(directory, error)) return !error;
  // 走査開始点も、配下の項目と同様にリパースポイントをたどらない。
  const DWORD root_attributes = GetFileAttributesW(directory.c_str());
  if (root_attributes == INVALID_FILE_ATTRIBUTES) return false;
  if (root_attributes & FILE_ATTRIBUTE_REPARSE_POINT) return true;
  bool success = true;
  std::filesystem::recursive_directory_iterator iterator(
      directory, std::filesystem::directory_options::skip_permission_denied, error), end;
  while (!error && iterator != end) {
    const auto path = iterator->path();
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
      iterator.disable_recursion_pending();
    } else if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
      if (iterator.depth() >= max_depth) iterator.disable_recursion_pending();
    } else if (_wcsicmp(path.extension().c_str(), L".lnk") == 0) {
      success = UpdateLink(path, executable, icon_path, updates) && success;
    }
    iterator.increment(error);
  }
  if (!pending) NotifyAppearanceShortcuts(local_updates, false);
  return success && !error;
}

bool UpdateUserAppearanceShortcuts(const std::wstring& executable, const std::filesystem::path& icon_path,
                                  AppearanceShortcutUpdates* pending,
                                  AppearanceFolderResolver resolve_folder) {
  AppearanceShortcutUpdates local_updates;
  auto* updates = pending ? pending : &local_updates;
  bool success = true;
  for (const auto& folder : {FOLDERID_Programs, FOLDERID_Desktop, FOLDERID_RoamingAppData,
                            FOLDERID_ImplicitAppShortcuts}) {
    PWSTR raw = nullptr;
    if (FAILED(resolve_folder(folder, 0, nullptr, &raw))) continue;
    std::filesystem::path directory(raw);
    CoTaskMemFree(raw);
    if (IsEqualGUID(folder, FOLDERID_RoamingAppData)) {
      directory /= L"Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar";
    }
    // デスクトップ配下のユーザーフォルダーを走査しない。
    // Windowsがグループ用に保持するリンクはImplicitAppShortcutsの1階層下にもある。
    const int depth = IsEqualGUID(folder, FOLDERID_Programs) ? 4 :
                      IsEqualGUID(folder, FOLDERID_ImplicitAppShortcuts) ? 1 : 0;
    success = UpdateAppearanceShortcuts(directory, executable, icon_path, depth, updates) && success;
  }
  if (!pending) NotifyAppearanceShortcuts(local_updates, false);
  return success;
}

void NotifyAppearanceShortcuts(const AppearanceShortcutUpdates& updates, bool global_refresh,
                               ShellChangeNotifier notify) {
  for (const auto& update : updates) {
    NotifyShellIconChanged(update.previous_icon);
    NotifyShellIconChanged(ReadShellIconCacheEntry(update.path));
  }
  // SHUpdateImageだけではWindows 11の表示済みグループが再取得されない。
  // 全参照の保存後にキャッシュ更新を通知し、その後に個別リンクを再通知する。
  // 順序はChromiumのWindows 11向けショートカット更新も参照。
  if (global_refresh) notify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST | SHCNF_FLUSH, nullptr, nullptr);
  const auto update_item = [&](const std::wstring& name) {
    PIDLIST_ABSOLUTE item = nullptr;
    if (SUCCEEDED(SHParseDisplayName(name.c_str(), nullptr, &item, 0, nullptr))) {
      notify(SHCNE_UPDATEITEM, SHCNF_IDLIST | SHCNF_FLUSH, item, nullptr);
      CoTaskMemFree(item);
    }
  };
  for (const auto& update : updates) update_item(update.path.wstring());
  if (global_refresh) {
    // スタートはファイルの.lnkとは別のAppsFolder項目も保持する。
    // 未登録のポータブル起動では項目がないため通知を省く。
    update_item(std::wstring(L"shell:AppsFolder\\") + kAppUserModelId);
  }
}
