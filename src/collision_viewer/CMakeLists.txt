cmake_minimum_required(VERSION 3.16)
project(SW_RACER_RE)

# TODO hack: enable optimizations for this target
add_compile_options(-O3)

file(GLOB HOOK_SOURCES *.c *.cpp *.h)
add_library(annodue_collision_viewer SHARED ${HOOK_SOURCES})
target_link_libraries(annodue_collision_viewer PRIVATE imgui detours shcore)
target_link_options(annodue_collision_viewer PRIVATE "-Wl,--kill-at")

if (GAME_DIR)
    set_target_properties(annodue_collision_viewer PROPERTIES
            OUTPUT_NAME plugin_collision_viewer
            PREFIX ""
            RUNTIME_OUTPUT_DIRECTORY "${GAME_DIR}/annodue/plugin")
else()
    message(WARNING "Set 'GAME_DIR' to the directory of the game to automatically place 'dinput.dll' there when building.")
endif()