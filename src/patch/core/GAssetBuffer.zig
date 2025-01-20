const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const coreAllocator = @import("Allocator.zig").allocator;

const x86 = @import("../util/x86.zig");
const mem = @import("../util/memory.zig");
const PPanic = @import("../util/debug.zig").PPanic;

// FIXME: remove, for testing
const dbg = @import("../util/debug.zig");

// TODO: test realloc to resize buf
// TODO: also resize asset buffer to 2x

const GAssetBuffer = struct {
    // 0x447471 .. 0x44748D
    const texbuf_init_src = [_]u8{
        0x7E, 0x02, 0xEB, 0xFE, 0xB9, 0xA4, 0x06, 0x00, 0x00, 0x33, 0xC0,
        0xBF, 0x60, 0x38, 0xE9, 0x00, 0x6A, 0x03, 0xF3, 0xAB, 0xE8, 0x66,
        0x62, 0xFE, 0xFF, 0x83, 0xC4, 0x04,
    };
    var texbuf_init_det: [32]u8 = undefined;

    fn init() callconv(.C) void {
        var d: x86.Detour = undefined;

        // patch TextureBuffer_Init (fn_447420)
        x86.detour_start(&d, 0x447471, 0x44748D, &texbuf_init_det);
        d.addr = x86.call(d.addr, @intFromPtr(&patch_texbuf_init));
        d.addr = x86.cdecl_call(d.addr, 0x42D6F0, &[_]x86.PushSrc{.{ .imm32 = 3 }}); // Block_Close(TEXTURE)
        x86.detour_end(&d);
        dbg.ConsoleOut("texbuf detour excess: {d} bytes", .{x86.detour_unused_space(&d)}) catch unreachable;
    }

    fn patch_texbuf_init() callconv(.C) void {
        // NOTE: original code for clearing the old static buffer
        //const dword_E93860: *[1700]i32 = @ptrFromInt(0xE93860);
        //@memset(dword_E93860, 0);

        const tex_count = @as(*u32, @ptrFromInt(0xE9823C)).*;
        var texbuf_replacement = (coreAllocator().alloc(u32, tex_count) catch unreachable);
        //@memset(texbuf_replacement, 0);  // NOTE: seems to be unnecessary

        const texbuf_ptr = texbuf_replacement.ptr;
        // patch TextureBuffer_LoadModelTexture (fn_447490)
        _ = mem.write(0x4474B1, u32, @intFromPtr(texbuf_ptr));
        _ = mem.write(0x4474C4, u32, @intFromPtr(texbuf_ptr));
        _ = mem.write(0x447555, u32, @intFromPtr(texbuf_ptr));
        // patch TextureBuffer_ClearBufferAfterPtr (fn_4475D0)
        _ = mem.write(0x4475D5, u32, @intFromPtr(texbuf_ptr));
        _ = mem.write(0x4475E7, u32, @intFromPtr(texbuf_ptr + tex_count));
    }
};

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GAssetBuffer.init();
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}
