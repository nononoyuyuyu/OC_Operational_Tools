#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// インストーラーのAppUserModelIDと同一に保つ。
#ifdef OCO_APPEARANCE_TEST
// 実行中の製品のタスクバーグループやピン留めにテストを混在させない。
inline constexpr wchar_t kAppUserModelId[] = L"Nononoyuyuyu.OpenCampusOrganizer.AppearanceTest";
#else
inline constexpr wchar_t kAppUserModelId[] = L"Nononoyuyuyu.OpenCampusOrganizer";
#endif

#endif  // RUNNER_APP_IDENTITY_H_
