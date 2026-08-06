const std = @import("std");

const w32 = @import("zigwin32");
const BOOL = w32.foundation.BOOL;
const HWND = w32.foundation.HWND;
const HINSTANCE = w32.foundation.HINSTANCE;
const LPARAM = w32.foundation.LPARAM;
const WPARAM = w32.foundation.WPARAM;

// GAME FUNCTIONS

pub const Window_SetActive: *const fn (hwnd: HWND, active: BOOL) callconv(.C) void =
    @ptrFromInt(0x423AE0);
pub const Window_ActivateApp: *const fn (hwnd: HWND, active: BOOL) callconv(.C) void =
    @ptrFromInt(0x423AA0); // window message 0x1C handler
pub const Window_Activate: *const fn (hwnd: HWND, active: BOOL) callconv(.C) void =
    @ptrFromInt(0x423AC0); // window message 0x06 handler

// GAME CONSTANTS

// Window

pub const WINDOW_HWND: *HWND = @ptrFromInt(0x52EE70);
pub const WINDOW_HINSTANCE: *HINSTANCE = @ptrFromInt(0x52EE74);
pub const WINDOW_ACTIVE: *BOOL = @ptrFromInt(0x50B5D0); // only accurate if game has been tabbed out and in

// Game State

pub const SCENE_ID: *u16 = @ptrFromInt(0xE9BA62); // u16
pub const IN_RACE: *u8 = @ptrFromInt(0xE9BB81); //u8
pub const IN_TOURNAMENT: *u8 = @ptrFromInt(0x50C450); // u8

// Pausing

pub const PAUSE_STATE: *u8 = @ptrFromInt(0x50C5F0);
pub const PAUSE_PAGE: *u8 = @ptrFromInt(0x50C07C);
pub const PAUSE_SCROLLINOUT: *f32 = @ptrFromInt(0xE9824C);

// HELPERS

// ...
