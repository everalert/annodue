const std = @import("std");
const testing = std.testing;
const LoadLibraryW = std.os.windows.LoadLibraryW;
const GetProcAddress = std.os.windows.kernel32.GetProcAddress;
const user32 = std.os.windows.user32;
const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;
const WINAPI = std.os.windows.WINAPI;
const DWORD = std.os.windows.DWORD;
const HRESULT = std.os.windows.HRESULT;
const LPVOID = std.os.windows.LPVOID;
const LPUNKNOWN = std.os.windows.LPUNKNOWN;
const HMODULE = std.os.windows.HMODULE;
const HINSTANCE = std.os.windows.HINSTANCE;
const print = std.debug.print;
const W = std.unicode.utf8ToUtf16LeStringLiteral;

const msg_title = "Zig DLL Hook Test";

const t_DirectInputCreateA = *fn (u32, u32, u32, u32) callconv(WINAPI) HRESULT;

fn DirectInputCreateA_detour(a: u32, b: u32, c: u32, d: u32) callconv(WINAPI) HRESULT {
    const msg = "Hooking DirectInputCreateA";
    print("{s}", .{msg});
    //_ = MessageBoxA(null, msg, msg_title, MB_OK | MB_ICONINFORMATION);

    const dll: HMODULE = LoadLibraryW(W("C:/windows/system32/dinput.dll")) catch return -1;
    const original_fn: t_DirectInputCreateA = @ptrCast(GetProcAddress(dll, "DirectInputCreateA"));

    return original_fn(a, b, c, d);
}

//fn main(hInst: HINSTANCE, fdwReason: DWORD, lpReserved: LPVOID) bool {
//    const msg = "Running hooked dinput.dll";
//    _ = MessageBoxA(null, msg, msg_title, MB_OK | MB_ICONINFORMATION);
//    print("{s}: {any} {any} {any}", .{ msg, hInst, fdwReason, lpReserved });
//
//    return true;
//}
