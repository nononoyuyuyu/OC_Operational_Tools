#ifndef RUNNER_SHORTCUT_APPEARANCE_H_
#define RUNNER_SHORTCUT_APPEARANCE_H_

#include <filesystem>
#include <string>

// 指定EXEを起動する既存リンクだけを更新する。ピン留めの追加・解除は行わない。
bool UpdateAppearanceShortcuts(const std::filesystem::path& directory,
                               const std::wstring& executable, int resource_id,
                               int max_depth = 4);
bool UpdateUserAppearanceShortcuts(const std::wstring& executable, int resource_id);

#endif
