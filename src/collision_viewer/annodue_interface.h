#pragma once

#include <stdint.h>

struct GlobalState
{
    uint8_t* patch_memory;
    size_t patch_size;
    size_t patch_offset;
    bool init_late_passed;
    bool practice_mode;
    void* hwnd;
    void* hinstance;
    float dt_t;
    float fps;
    float fps_avg;
    uint32_t timestamp;
    uint32_t framecount;
    enum ActiveState
    {
        OFF, ON, JUST_OFF, JUST_ON
    } in_race;
};

struct GlobalFunction
{
   /*
    // Settings
    SettingGetB: *const @TypeOf(settings.get_bool) = &settings.get_bool,
                          SettingGetI: *const @TypeOf(settings.get_i32) = &settings.get_i32,
                          SettingGetU: *const @TypeOf(settings.get_u32) = &settings.get_u32,
                          SettingGetF: *const @TypeOf(settings.get_f32) = &settings.get_f32,
                          // Input
        InputGetKb: *const @TypeOf(input.get_kb) = &input.get_kb,
                          InputGetKbRaw: *const @TypeOf(input.get_kb_raw) = &input.get_kb_raw,
                          InputGetMouse: *const @TypeOf(input.get_mouse_raw) = &input.get_mouse_raw,
                          InputGetMouseDelta: *const @TypeOf(input.get_mouse_raw_d) = &input.get_mouse_raw_d,
                          InputLockMouse: *const @TypeOf(input.lock_mouse) = &input.lock_mouse,
                          //InputGetMouseInWindow: *const @TypeOf(input.get_mouse_inside) = &input.get_mouse_inside,
        InputGetXInputButton: *const @TypeOf(input.get_xinput_button) = &input.get_xinput_button,
                          InputGetXInputAxis: *const @TypeOf(input.get_xinput_axis) = &input.get_xinput_axis,
                          // Game
        GameFreezeEnable: *const @TypeOf(freeze.Freeze.freeze) = &freeze.Freeze.freeze,
                          GameFreezeDisable: *const @TypeOf(freeze.Freeze.unfreeze) = &freeze.Freeze.unfreeze,
                          GameFreezeIsFrozen: *const @TypeOf(freeze.Freeze.is_frozen) = &freeze.Freeze.is_frozen,
                          // Toast
        ToastNew: *const @TypeOf(toast.ToastSystem.NewToast) = &toast.ToastSystem.NewToast,*/
};