//! adapted and expanded from:
//! https://gist.github.com/BOT-Man-JL/9206a62b067f4c3a84da57bd3ba04a97
const PDBParse = @This();

const std = @import("std");
const assert = std.debug.assert;

const w32 = @import("zigwin32");
const FALSE = w32.zig.FALSE;
const HANDLE = w32.foundation.HANDLE;
const SYSTEM_INFO = w32.system.system_information.SYSTEM_INFO;
const IMAGEHLP_LINE64 = w32.system.diagnostics.debug.IMAGEHLP_LINE64;
const IMAGEHLP_SYMBOL64 = w32.system.diagnostics.debug.IMAGEHLP_SYMBOL64;
const GetLastError = w32.foundation.GetLastError;
const GetSystemInfo = w32.system.system_information.GetSystemInfo;
const SymGetOptions = w32.system.diagnostics.debug.SymGetOptions;
const SymSetOptions = w32.system.diagnostics.debug.SymSetOptions;
const SymInitialize = w32.system.diagnostics.debug.SymInitialize;
const SymLoadModule64 = w32.system.diagnostics.debug.SymLoadModule64;
const SymGetLineFromAddr64 = w32.system.diagnostics.debug.SymGetLineFromAddr64;
const SymGetSymFromAddr64 = w32.system.diagnostics.debug.SymGetSymFromAddr64;
const SymUnloadModule64 = w32.system.diagnostics.debug.SymUnloadModule64;
const SymCleanup = w32.system.diagnostics.debug.SymCleanup;

const ModuleBaseAddress = @import("../base/base_debug.zig").ModuleBaseAddress;
const ConsoleOut = @import("../base/base_debug.zig").ConsoleOut;

const PARSER_HANDLE: HANDLE = @ptrFromInt(0x493);

pub fn testbed(pdb: [:0]const u8) void {
    // init
    const options: u32 = blk: {
        var opts = SymGetOptions();
        opts &= ~w32.system.diagnostics.debug.SYMOPT_DEFERRED_LOADS;
        opts |= w32.system.diagnostics.debug.SYMOPT_LOAD_LINES;
        opts |= w32.system.diagnostics.debug.SYMOPT_IGNORE_NT_SYMPATH;
        opts |= w32.system.diagnostics.debug.SYMOPT_DEBUG;
        opts |= w32.system.diagnostics.debug.SYMOPT_UNDNAME;
        break :blk opts;
    };
    _ = SymSetOptions(options);

    if (FALSE == SymInitialize(PARSER_HANDLE, null, FALSE))
        std.debug.panic("SymInitialize: {s}", .{@tagName(GetLastError())});

    // NOTE: was SymLoadModuleEx(..., null, 0) in ref, but non-64 versions not defined in zigwin32
    const base = ModuleBaseAddress();
    if (FALSE == SymLoadModule64(PARSER_HANDLE, null, pdb, null, base, 0x7FFFFFFF))
        std.debug.panic("SymLoadModule64: {s}", .{@tagName(GetLastError())});

    // SymGetLineFromAddr for each stacktrace entry
    // NOTE: ref had SymEnumSymbols etc. here, but we have different goals than just listing everything
    const test_addresses = [_]usize{ base + 0x1AF16, base + 0x01AA5, base + 0x126AF, base + 0x5F825 };
    const MAX_NAME_LENGTH = 260;
    for (test_addresses) |addr| {
        var line_disp: u32 = 0;
        var sym_disp: u64 = 0;
        var line = std.mem.zeroes(IMAGEHLP_LINE64);
        var sym_buf = std.mem.zeroes([@sizeOf(IMAGEHLP_SYMBOL64) + MAX_NAME_LENGTH]u8);
        var sym = @as(*IMAGEHLP_SYMBOL64, @alignCast(@ptrCast(&sym_buf)));
        line.SizeOfStruct = @sizeOf(IMAGEHLP_LINE64);
        sym.SizeOfStruct = @sizeOf(IMAGEHLP_SYMBOL64) - 1;
        sym.MaxNameLength = MAX_NAME_LENGTH;

        if (FALSE == SymGetLineFromAddr64(PARSER_HANDLE, addr, &line_disp, &line)) {
            _ = ConsoleOut("SymGetLineFromAddr64: {s} ({X:0>8})\n", .{ @tagName(GetLastError()), addr }) catch continue;
            continue;
        }
        if (FALSE == SymGetSymFromAddr64(PARSER_HANDLE, addr, &sym_disp, sym)) {
            _ = ConsoleOut("SymGetSymFromAddr64: {s} ({X:0>8})\n", .{ @tagName(GetLastError()), addr }) catch continue;
            continue;
        }

        const filename = if (line.FileName) |n| @as([*:0]const u8, @ptrCast(n)) else "???";
        const symname = @as([*:0]const u8, @ptrCast(&sym.Name));
        _ = ConsoleOut(
            "0x{X:0>8}  {s} at {s}:{d}:{d}\n",
            .{ line.Address, symname, filename, line.LineNumber, line_disp },
        ) catch unreachable;
    }

    // deinit: close sym stuff, close file? etc.
    _ = SymUnloadModule64(PARSER_HANDLE, base);
    _ = SymCleanup(PARSER_HANDLE);
}
