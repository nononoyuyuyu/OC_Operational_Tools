#include "shortcut_appearance.h"

#include <windows.h>
#include <shlobj.h>
#include <wrl/client.h>
#include <propkey.h>
#include <propvarutil.h>
#include "app_identity.h"

namespace {
bool UpdateLink(const std::filesystem::path& path,
                const std::wstring& executable, int resource_id) {
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  Microsoft::WRL::ComPtr<IPersistFile> file;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&link))) ||
      FAILED(link.As(&file)) || FAILED(file->Load(path.c_str(), STGM_READ))) return true;
  wchar_t target[32768]{};
  // Resolveはリンク先へのアクセスやダイアログを起こすため使わない。
  if (FAILED(link->GetPath(target, ARRAYSIZE(target), nullptr, SLGP_RAWPATH)) ||
      _wcsicmp(target, executable.c_str()) != 0) return true;
  if (FAILED(file->Load(path.c_str(), STGM_READWRITE))) return false;
  wchar_t icon[32768]{};
  int index = 0;
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(link.As(&properties))) return false;
  const auto read = [&](const PROPERTYKEY& key) {
    PROPVARIANT value{};
    properties->GetValue(key, &value);
    const std::wstring text = value.vt == VT_LPWSTR ? value.pwszVal : L"";
    PropVariantClear(&value);
    return text;
  };
  const std::wstring relaunch_icon = executable + L",-" + std::to_wstring(resource_id);
  if (SUCCEEDED(link->GetIconLocation(icon, ARRAYSIZE(icon), &index)) &&
      _wcsicmp(icon, executable.c_str()) == 0 && index == -resource_id &&
      read(PKEY_AppUserModel_ID) == kAppUserModelId &&
      read(PKEY_AppUserModel_RelaunchIconResource) == relaunch_icon) return true;
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
  if (FAILED(link->SetIconLocation(executable.c_str(), -resource_id)) ||
      FAILED(file->Save(path.c_str(), TRUE))) return false;
  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSHNOWAIT, path.c_str(), nullptr);
  return true;
}
}

bool UpdateAppearanceShortcuts(const std::filesystem::path& directory,
                               const std::wstring& executable, int resource_id, int max_depth) {
  std::error_code error;
  if (!std::filesystem::exists(directory, error)) return true;
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
      success = UpdateLink(path, executable, resource_id) && success;
    }
    iterator.increment(error);
  }
  return success && !error;
}

bool UpdateUserAppearanceShortcuts(const std::wstring& executable, int resource_id) {
  bool success = true;
  for (const auto& folder : {FOLDERID_Programs, FOLDERID_Desktop, FOLDERID_RoamingAppData}) {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder, 0, nullptr, &raw))) continue;
    std::filesystem::path directory(raw);
    CoTaskMemFree(raw);
    if (IsEqualGUID(folder, FOLDERID_RoamingAppData)) {
      directory /= L"Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar";
    }
    // デスクトップ配下のユーザーフォルダーを走査しない。
    const int depth = IsEqualGUID(folder, FOLDERID_Programs) ? 4 : 0;
    success = UpdateAppearanceShortcuts(directory, executable, resource_id, depth) && success;
  }
  return success;
}
