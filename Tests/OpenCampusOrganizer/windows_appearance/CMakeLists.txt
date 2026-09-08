# runnerと同じ外観実装・ICOを隠しウィンドウで検証する。
set(RUNNER_DIR "${CMAKE_SOURCE_DIR}/runner")
add_executable(oco_appearance_test EXCLUDE_FROM_ALL
  "appearance_test.cpp"
  "${RUNNER_DIR}/window_appearance.cpp"
  "${RUNNER_DIR}/shortcut_appearance.cpp"
  "${RUNNER_DIR}/Runner.rc"
)
apply_standard_settings(oco_appearance_test)
target_compile_definitions(oco_appearance_test PRIVATE NOMINMAX)
target_include_directories(oco_appearance_test PRIVATE "${RUNNER_DIR}")
target_link_libraries(oco_appearance_test PRIVATE flutter_wrapper_app shell32 shlwapi propsys ole32)
