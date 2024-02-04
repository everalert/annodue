const std = @import("std");
const WINAPI = std.os.windows.WINAPI;

pub const HOOKPROC = *opaque {};
pub const HHOOK = *anyopaque;

pub extern "user32" fn SetWindowsHookExA(idHook: i32, lpfn: *opaque {}, hmod: *opaque {}, dwThreadId: u32) callconv(WINAPI) ?c_int;

pub extern "user32" fn CallNextHookEx(hhk: *anyopaque, ncode: i32, wParam: usize, lParam: isize) callconv(WINAPI) isize;

pub extern "user32" fn UnhookWindowsHookEx(hhk: *anyopaque) callconv(WINAPI) isize;
