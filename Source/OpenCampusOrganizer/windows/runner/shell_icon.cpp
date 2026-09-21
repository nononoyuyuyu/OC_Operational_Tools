#include "shell_icon.h"

#include <shlobj.h>
#include <wrl/client.h>
#include <bcrypt.h>
#include <array>
#include <fstream>
#include <iterator>
#include <vector>

namespace {
using Bytes = std::vector<unsigned char>;

Bytes Resource(WORD type, int id) {
  const auto instance = GetModuleHandleW(nullptr);
  const auto resource = FindResourceW(instance, MAKEINTRESOURCEW(id), MAKEINTRESOURCEW(type));
  if (!resource) return {};
  const DWORD size = SizeofResource(instance, resource);
  const auto data = static_cast<const unsigned char*>(LockResource(LoadResource(instance, resource)));
  return data && size ? Bytes(data, data + size) : Bytes{};
}

unsigned int Word(const Bytes& bytes, size_t offset) {
  return bytes[offset] | (static_cast<unsigned int>(bytes[offset + 1]) << 8);
}

void AppendDword(Bytes& bytes, DWORD value) {
  for (int shift = 0; shift < 32; shift += 8) bytes.push_back(static_cast<unsigned char>(value >> shift));
}

Bytes IconFile(int resource_id) {
  // RT_GROUP_ICONの14バイト項目を、ICOの16バイト項目へ変換する。
  // 画像本体（PNG/DIB）は再圧縮せず、全サイズをそのまま残す。
  const auto group = Resource(14, resource_id);
  if (group.size() < 6 || Word(group, 0) != 0 || Word(group, 2) != 1) return {};
  const unsigned int count = Word(group, 4);
  if (!count || count > 256 || group.size() < 6 + count * 14) return {};
  Bytes directory(group.begin(), group.begin() + 6), images;
  for (unsigned int i = 0; i < count; ++i) {
    const size_t entry = 6 + static_cast<size_t>(i) * 14;
    const auto frame = Resource(3, Word(group, entry + 12));
    if (frame.empty()) return {};
    directory.insert(directory.end(), group.begin() + entry, group.begin() + entry + 8);
    AppendDword(directory, static_cast<DWORD>(frame.size()));
    AppendDword(directory, static_cast<DWORD>(6 + count * 16 + images.size()));
    images.insert(images.end(), frame.begin(), frame.end());
  }
  directory.insert(directory.end(), images.begin(), images.end());
  return directory;
}

bool WriteIcon(const std::filesystem::path& path, const Bytes& bytes) {
  if (path.empty() || bytes.empty()) return false;
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) return false;
  // テーマ選択は直列化されている。別プロセスとの一時ファイル衝突も避ける。
  GUID id{};
  wchar_t suffix[40]{};
  if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, suffix, ARRAYSIZE(suffix))) return false;
  const auto temporary = path.wstring() + L"." + suffix + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool saved = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) &&
                     written == bytes.size() && FlushFileBuffers(file);
  CloseHandle(file);
  const bool replaced = saved && MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_WRITE_THROUGH);
  if (!replaced) DeleteFileW(temporary.c_str());
  return replaced;
}

std::wstring ContentHash(const Bytes& bytes) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return {};
  std::array<UCHAR, 32> digest{};
  const auto status = BCryptHash(algorithm, nullptr, 0, const_cast<PUCHAR>(bytes.data()),
                                 static_cast<ULONG>(bytes.size()), digest.data(),
                                 static_cast<ULONG>(digest.size()));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status < 0) return {};
  std::wstring hash;
  constexpr wchar_t hex[] = L"0123456789abcdef";
  for (auto value : digest) {
    hash += hex[value >> 4];
    hash += hex[value & 15];
  }
  return hash;
}
}  // namespace

ShellIconCacheEntry ReadShellIconCacheEntry(const std::filesystem::path& path) {
  ShellIconCacheEntry entry;
  if (path.empty()) return entry;
  PIDLIST_ABSOLUTE item = nullptr;
  if (FAILED(SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr))) return entry;
  Microsoft::WRL::ComPtr<IShellFolder> parent;
  PCUITEMID_CHILD child = nullptr;
  Microsoft::WRL::ComPtr<IExtractIconW> extractor;
  wchar_t file[32768]{};
  if (SUCCEEDED(SHBindToParent(item, IID_PPV_ARGS(&parent), &child)) &&
      SUCCEEDED(parent->GetUIObjectOf(nullptr, 1, &child, IID_IExtractIconW, nullptr, &extractor)) &&
      SUCCEEDED(extractor->GetIconLocation(GIL_FORSHELL, file, ARRAYSIZE(file),
                                           &entry.resource_index, &entry.flags))) {
    SHFILEINFOW info{};
    if (SHGetFileInfoW(path.c_str(), 0, &info, sizeof(info), SHGFI_SYSICONINDEX)) {
      entry.file = file;
      entry.image_index = info.iIcon;
    }
  }
  CoTaskMemFree(item);
  return entry;
}

void NotifyShellIconChanged(const ShellIconCacheEntry& entry) {
  if (entry.image_index >= 0 && !entry.file.empty()) {
    SHUpdateImageW(entry.file.c_str(), entry.resource_index, entry.flags, entry.image_index);
  }
}

std::filesystem::path UserAppearanceIconDirectory() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder))) return {};
  const auto path = std::filesystem::path(folder) / L"OpenCampusOrganizer" / L"appearance";
  CoTaskMemFree(folder);
  return path;
}

bool PrepareShellIconFile(const std::filesystem::path& directory, int resource_id,
                          std::filesystem::path* path) {
  const auto bytes = IconFile(resource_id);
  if (directory.empty() || bytes.empty() || !path) return false;
  const auto hash = ContentHash(bytes);
  if (hash.empty()) return false;
  const auto file_path = directory / (L"icon-" + hash + L".ico");
  bool unchanged = false;
  {
    std::ifstream file(file_path, std::ios::binary);
    // アイコンのサイズを先に確認し、未知の大きなファイルを読み込まない。
    std::error_code error;
    if (std::filesystem::file_size(file_path, error) == bytes.size() && !error && file) {
      const Bytes current{std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
      unchanged = current == bytes;
    }
  }
  if (!unchanged && !WriteIcon(file_path, bytes)) return false;
  *path = file_path;
  return true;
}
