//! adapted and expanded from:
//! https://gist.github.com/BOT-Man-JL/9206a62b067f4c3a84da57bd3ba04a97
const PDBParse = @This();

const std = @import("std");
const assert = std.debug.assert;

const w32 = @import("zigwin32");
const FALSE = w32.zig.FALSE;
const MAX_PATH = w32.foundation.MAX_PATH;
const MAX_PATH_SENTINEL = MAX_PATH - 1;
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
const RoundIntUp = @import("../base/base_math.zig").RoundIntUp;

const PARSER_HANDLE: HANDLE = @ptrFromInt(0x493);
const MAX_NAME_LENGTH = w32.foundation.MAX_PATH;
const MAX_NAME_LENGTH_SENTINEL = MAX_NAME_LENGTH - 1;

// TODO: ?? maybe take a translation list for replacing beginnings of filepaths
//  with keywords in LineInfo output, for both aesthetic and obfuscation purposes;
//  main issue is unsure how to get all the right paths programmatically from zig

Handle: HANDLE,
BaseAddress: usize,

pub fn Init(pdb: [:0]const u8, handle: ?HANDLE) ?PDBParse {
    var parser = PDBParse{
        .Handle = handle orelse PARSER_HANDLE,
        .BaseAddress = ModuleBaseAddress(),
    };

    var opts = SymGetOptions();
    opts &= ~w32.system.diagnostics.debug.SYMOPT_DEFERRED_LOADS;
    opts |= w32.system.diagnostics.debug.SYMOPT_LOAD_LINES;
    opts |= w32.system.diagnostics.debug.SYMOPT_IGNORE_NT_SYMPATH;
    opts |= w32.system.diagnostics.debug.SYMOPT_DEBUG;
    opts |= w32.system.diagnostics.debug.SYMOPT_UNDNAME;
    _ = SymSetOptions(opts);

    // TODO: do something with error message?
    if (FALSE == SymInitialize(parser.Handle, null, FALSE))
        //std.debug.panic("SymInitialize: {s}", .{@tagName(GetLastError())});
        return null;

    // TODO: do something with error message?
    if (FALSE == SymLoadModule64(parser.Handle, null, pdb, null, parser.BaseAddress, 0x7FFFFFFF)) blk: {
        const e = GetLastError();
        if (e == .NO_ERROR) break :blk; // zigwin32 NO_ERROR == ERROR_SUCCESS
        //std.debug.panic("SymLoadModule64: {s}", .{@tagName(e)});
        return null;
    }

    return parser;
}

pub fn Deinit(self: *PDBParse) void {
    _ = SymUnloadModule64(self.Handle, self.BaseAddress);
    _ = SymCleanup(self.Handle);
    self.* = std.mem.zeroes(PDBParse);
}

pub fn GetLineInfo(self: *const PDBParse, address: usize, out: *LineInfo) bool {
    var line_disp: u32 = 0;
    var line = std.mem.zeroes(IMAGEHLP_LINE64);
    line.SizeOfStruct = @sizeOf(IMAGEHLP_LINE64);

    // TODO: do something with error message?
    if (FALSE == SymGetLineFromAddr64(self.Handle, address, &line_disp, &line))
        //std.debug.panic("SymGetLineFromAddr64: {s} ({X:0>8})\n", .{ @tagName(GetLastError()), address });
        return false;

    const SYM_ALIGNMENT = @alignOf(IMAGEHLP_SYMBOL64);
    const SYM_BUF_SIZE = @sizeOf(IMAGEHLP_SYMBOL64) + SYM_ALIGNMENT + MAX_NAME_LENGTH;
    var sym_disp: u64 = 0;
    var sym_buf = std.mem.zeroes([SYM_BUF_SIZE]u8);
    var sym = @as(*IMAGEHLP_SYMBOL64, @ptrFromInt(RoundIntUp(usize, @intFromPtr(&sym_buf), SYM_ALIGNMENT)));
    sym.SizeOfStruct = @sizeOf(IMAGEHLP_SYMBOL64) - 1;
    sym.MaxNameLength = MAX_NAME_LENGTH;

    // TODO: do something with error message?
    if (FALSE == SymGetSymFromAddr64(self.Handle, address, &sym_disp, sym))
        //std.debug.panic("SymGetSymFromAddr64: {s} ({X:0>8})\n", .{ @tagName(GetLastError()), address });
        return false;

    out.* = LineInfo.Init();
    out.Address = line.Address;
    out.SymbolDisplacement = sym_disp;
    out.SymbolSize = sym.Size;
    out.SymbolFlags = sym.Flags;
    out.LineNumber = line.LineNumber;
    out.LineDisplacement = line_disp;
    if (line.FileName) |name| {
        out.FileNameLen = @truncate(std.mem.len(@as([*:0]const u8, @ptrCast(name))));
        @memcpy(out.FileName[0..out.FileNameLen], name);
    }
    const p_symname = @as([*:0]const u8, @ptrCast(&sym.Name));
    const symname_len = std.mem.len(p_symname);
    if (symname_len > 0) {
        out.SymbolNameLen = @truncate(symname_len);
        @memcpy(out.SymbolName[0..symname_len], p_symname);
    }

    return true;
}

pub const LineInfo = struct {
    const FALLBACK_LABEL = "???";

    Address: u64,
    FileName: [MAX_PATH_SENTINEL:0]u8,
    FileNameLen: u16,
    SymbolName: [MAX_NAME_LENGTH_SENTINEL:0]u8,
    SymbolNameLen: u16,
    SymbolDisplacement: u64,
    SymbolSize: u32,
    SymbolFlags: u32,
    LineNumber: u32,
    LineDisplacement: u32,

    // TODO: convert to decl literal after updating zig ver
    pub fn Init() LineInfo {
        var out = std.mem.zeroes(LineInfo);
        out.FileNameLen = LineInfo.FALLBACK_LABEL.len;
        @memcpy(out.FileName[0..LineInfo.FALLBACK_LABEL.len], LineInfo.FALLBACK_LABEL);
        out.SymbolNameLen = LineInfo.FALLBACK_LABEL.len;
        @memcpy(out.SymbolName[0..LineInfo.FALLBACK_LABEL.len], LineInfo.FALLBACK_LABEL);
        return out;
    }
};
