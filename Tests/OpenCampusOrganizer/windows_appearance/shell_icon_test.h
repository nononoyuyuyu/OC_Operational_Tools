#ifndef TESTS_SHELL_ICON_TEST_H_
#define TESTS_SHELL_ICON_TEST_H_

#include <commctrl.h>
#include <shlobj.h>
#include <vector>

// Explorerと同じく通知を購読し、通知された画像だけをこのプロセスの画像リストへ反映する。
// 新しいプロセスから画像を読むだけでは、古い画像を保持する利用側の不具合を検出できない。
class ShellImageObserver {
 public:
  ShellImageObserver() {
    WNDCLASSW type{};
    type.lpfnWndProc = Handle;
    type.hInstance = GetModuleHandleW(nullptr);
    type.lpszClassName = L"OcoShellImageObserver";
    Check(RegisterClassW(&type) != 0, "Cannot register shell observer");
    window_ = CreateWindowW(type.lpszClassName, L"", 0, 0, 0, 0, 0,
                            nullptr, nullptr, type.hInstance, nullptr);
    Check(window_ != nullptr, "Cannot create shell observer");
    SetWindowLongPtrW(window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    SHChangeNotifyEntry entry{nullptr, TRUE};
    registration_ = SHChangeNotifyRegister(window_, SHCNRF_ShellLevel | SHCNRF_NewDelivery,
                                          SHCNE_UPDATEIMAGE, kMessage, 1, &entry);
    Check(registration_ != 0, "Cannot subscribe to shell image changes");
  }
  ~ShellImageObserver() {
    if (registration_) SHChangeNotifyDeregister(registration_);
    if (window_) DestroyWindow(window_);
    UnregisterClassW(L"OcoShellImageObserver", GetModuleHandleW(nullptr));
  }
  int updates = 0;

 private:
  static constexpr UINT kMessage = WM_APP + 73;
  static LRESULT CALLBACK Handle(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == kMessage) {
      PIDLIST_ABSOLUTE* items = nullptr;
      LONG event = 0;
      const auto lock = SHChangeNotification_Lock(reinterpret_cast<HANDLE>(wparam),
                                                  static_cast<DWORD>(lparam), &items, &event);
      if (lock) {
        if ((event & SHCNE_UPDATEIMAGE) && items && items[1]) {
          const int index = SHHandleUpdateImage(items[1]);
          auto self = reinterpret_cast<ShellImageObserver*>(GetWindowLongPtrW(window, GWLP_USERDATA));
          if (self && index >= 0) ++self->updates;
        }
        SHChangeNotification_Unlock(lock);
      }
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
  HWND window_ = nullptr;
  ULONG registration_ = 0;
};

// 画像の輪郭を含め、同じ背景へ描画して比較できる形式に揃える。
inline std::vector<DWORD> IconPixels(HICON icon, int size) {
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  void* bits = nullptr;
  HDC dc = CreateCompatibleDC(nullptr);
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  Check(dc && bitmap && bits, "Cannot create icon comparison bitmap");
  const auto previous = SelectObject(dc, bitmap);
  const size_t count = static_cast<size_t>(size) * size;
  ZeroMemory(bits, count * sizeof(DWORD));
  const bool drawn = DrawIconEx(dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL) != 0;
  std::vector<DWORD> pixels(static_cast<DWORD*>(bits), static_cast<DWORD*>(bits) + count);
  SelectObject(dc, previous);
  DeleteObject(bitmap);
  DeleteDC(dc);
  Check(drawn, "Cannot render icon");
  return pixels;
}

inline void CheckShellIcon(const std::filesystem::path& path, int resource, bool shell_item = false) {
  const auto deadline = GetTickCount64() + 50;
  do {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
  } while (GetTickCount64() < deadline);
  SHFILEINFOW info{};
  const auto images = reinterpret_cast<HIMAGELIST>(SHGetFileInfoW(
      path.c_str(), 0, &info, sizeof(info), SHGFI_SYSICONINDEX | SHGFI_LARGEICON));
  Check(images != nullptr, "Cannot read shell image list");
  int width = 0, height = 0;
  Check(ImageList_GetIconSize(images, &width, &height) != 0 && width == height,
        "Cannot read shell image size");
  const auto actual = ImageList_GetIcon(images, info.iIcon, ILD_NORMAL);
  const auto expected = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(resource), IMAGE_ICON,
      width, height, LR_DEFAULTCOLOR));
  Check(actual && expected, "Cannot load shell comparison icons");
  auto actual_pixels = IconPixels(actual, width);
  const auto expected_pixels = IconPixels(expected, width);
  if (shell_item) {
    Microsoft::WRL::ComPtr<IShellItemImageFactory> factory;
    Check(SUCCEEDED(SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&factory))),
          "Cannot read shell item image factory");
    HBITMAP bitmap = nullptr;
    Check(SUCCEEDED(factory->GetImage(SIZE{width, height}, SIIGBF_ICONONLY, &bitmap)),
          "Cannot read cached shell item image");
    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    const auto dc = GetDC(nullptr);
    const int lines = GetDIBits(dc, bitmap, 0, height, actual_pixels.data(), &bitmap_info, DIB_RGB_COLORS);
    ReleaseDC(nullptr, dc);
    DeleteObject(bitmap);
    Check(lines == height, "Cannot inspect shell item pixels");
  }
  // Shell側のアンチエイリアスによる輪郭の丸めは除き、内部の不透明な配色を比較する。
  int samples = 0, differences = 0;
  for (int y = 1; y < height - 1; ++y) {
    for (int x = 1; x < width - 1; ++x) {
      const size_t pixel = static_cast<size_t>(y) * width + x;
      const DWORD color = expected_pixels[pixel];
      if ((color >> 24) != 255) continue;
      bool solid = true;
      for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
          if (expected_pixels[static_cast<size_t>(y + dy) * width + x + dx] != color) solid = false;
        }
      }
      if (!solid) continue;
      ++samples;
      if ((actual_pixels[pixel] & 0x00ffffff) != (color & 0x00ffffff)) ++differences;
    }
  }
  const bool equal = samples >= 16 && differences == 0;
  DestroyIcon(actual);
  DestroyIcon(expected);
  if (!equal) {
    std::cerr << "Shell image mismatch: resource=" << resource << " index=" << info.iIcon
              << " size=" << width << " samples=" << samples << " RGB differences=" << differences
              << " actual=" << std::hex << actual_pixels[static_cast<size_t>(width) * width / 2 + width / 2]
              << " expected=" << expected_pixels[static_cast<size_t>(width) * width / 2 + width / 2]
              << std::dec << '\n';
  }
  Check(equal, "Shell image pixels did not follow theme");
}

#endif
