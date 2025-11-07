pub const Self = @This();

const std = @import("std");
const mem = @import("memory.zig");
const assert = std.debug.assert;
const bytesToHex = std.fmt.bytesToHex;

// NOTE: supporting x86 only, not x86_64

const SegReg = enum { cs, ss, ds, es, fs, gs }; // segment register
const OpEn = enum { mem, reg, imm, zo }; // operator encoding
const EffAdd = enum(u8) { mem, mem8, mem32, reg }; // effective address

// general registers
// TODO: separate index/pointer registers from 16/32-bit register enum
const GenReg8 = enum(u8) { al, cl, dl, bl, ah, ch, dh, bh };
const GenReg16 = enum(u8) { ax, cx, dx, bx, sp, bp, si, di };
const GenReg32 = enum(u8) { eax, ecx, edx, ebx, esp, ebp, esi, edi };

// helpers

inline fn parseRM(comptime reg: GenReg32) u8 {
    return @intFromEnum(reg) * 0x08;
}

inline fn parseMod(comptime mod: EffAdd) u8 {
    return @intFromEnum(mod) * 0x40;
}

inline fn parseModRM(
    comptime mod: EffAdd,
    comptime dst: GenReg32, // rm
    comptime src: GenReg32, // reg
) u8 {
    return parseMod(mod) + @intFromEnum(src) + parseRM(dst);
}

inline fn parseModMR(
    comptime mod: EffAdd,
    comptime dst: GenReg32, // rm
    comptime src: GenReg32, // reg
) u8 {
    return parseMod(mod) + @intFromEnum(dst) + parseRM(src);
}

// TODO: op_r16, op_r32 reg and base+reg should be comptime, not sure why zig
// complains about them when e.g. push() is called with runtime .imm32 value,
// they should not be called in that case anyway

pub inline fn op_r16(
    write_at: usize,
    comptime base: u8,
    reg: GenReg16,
) usize {
    return mem.write_bytes(write_at, &[2]u8{ 0x66, base + @intFromEnum(reg) }, 2);
}

pub inline fn op_r32(
    write_at: usize,
    comptime base: u8,
    reg: GenReg32,
) usize {
    return mem.write(write_at, u8, base + @intFromEnum(reg));
}

pub inline fn op_imm8(
    write_at: usize,
    comptime op: u8,
    value: u8,
) usize {
    return mem.write_bytes(write_at, &[2]u8{ op, value }, 2);
}

pub inline fn op_imm32(
    write_at: usize,
    comptime op: u8,
    value: u32,
) usize {
    var addr = mem.write(write_at, u8, op);
    return mem.write(addr, u32, value);
}

pub inline fn op_modRM(
    write_at: usize,
    op: u8,
    comptime mod: EffAdd,
    comptime dest: GenReg32,
    comptime src: GenReg32,
) usize {
    var addr = mem.write(write_at, u8, op);
    return mem.write(addr, u8, comptime parseModRM(mod, dest, src));
}

pub inline fn op_modMR(
    write_at: usize,
    op: u8,
    comptime mod: EffAdd,
    comptime dest: GenReg32,
    comptime src: GenReg32,
) usize {
    var addr = mem.write(write_at, u8, op);
    return mem.write(addr, u8, comptime parseModMR(mod, dest, src));
}

// stuff

pub fn add_rm32_imm8(write_at: usize, rm32: u8, imm8: u8) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x83);
    addr = mem.write(addr, u8, rm32);
    addr = mem.write(addr, u8, imm8);
    return addr;
}

pub fn sub_rm32_imm8(write_at: usize, rm32: u8, imm8: i8) usize {
    const imm8_u8: u8 = @bitCast(imm8);
    var addr = write_at;
    addr = mem.write(addr, u8, 0x83);
    addr = mem.write(addr, u8, rm32);
    addr = mem.write(addr, u8, imm8_u8);
    return addr;
}

pub fn add_esp8(write_at: usize, value: u8) usize {
    return add_rm32_imm8(write_at, 0xC4, value);
}

pub fn add_rm32_imm32(write_at: usize, rm32: u8, imm32: u32) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x81);
    addr = mem.write(addr, u8, rm32);
    addr = mem.write(addr, u32, imm32);
    return addr;
}

pub fn add_esp32(write_at: usize, value: u32) usize {
    return add_rm32_imm32(write_at, 0xC4, value);
}

pub fn test_rm32_r32(write_at: usize, r32: u8) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x85);
    addr = mem.write(addr, u8, r32);
    return addr;
}

pub fn test_eax_eax(write_at: usize) usize {
    return test_rm32_r32(write_at, 0xC0);
}

pub fn test_edx_edx(write_at: usize) usize {
    return test_rm32_r32(write_at, 0xD2);
}

pub fn mov_ecx_imm32(write_at: usize, comptime T: type, imm32: T) usize {
    assert(T == u8 or T == u32);
    var addr = write_at;
    addr = mem.write(addr, u8, 0xB9); // EDX=BA, EBX=BB
    addr = mem.write(addr, T, imm32);
    return addr;
}

pub fn mov_eax_imm32(write_at: usize, comptime T: type, imm32: T) usize {
    assert(T == u8 or T == u32);
    var addr = write_at;
    addr = mem.write(addr, u8, 0xB8);
    addr = mem.write(addr, T, imm32);
    return addr;
}

pub fn mov_esi_imm32(write_at: usize, comptime T: type, imm32: T) usize {
    assert(T == u8 or T == u32);
    var addr = write_at;
    addr = mem.write(addr, u8, 0xBE);
    addr = mem.write(addr, T, imm32);
    return addr;
}

pub fn mov_eax_moffs32(write_at: usize, moffs32: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xA1);
    addr = mem.write(addr, usize, moffs32);
    return addr;
}

// mov r32, [esp+<delta>]
pub fn mov_r32_esp_add(write_at: usize, r32: u8, delta: i8) usize {
    // values less than zero have the upper bit set
    var delta_u8: u8 = @bitCast(delta);
    var addr = write_at;
    addr = mem.write(addr, u8, 0x8B);
    addr = mem.write(addr, u8, r32);
    addr = mem.write(addr, u8, 0x24);
    addr = mem.write(addr, u8, delta_u8);
    return addr;
}

pub fn mov_eax_esp_add(write_at: usize, delta: i8) usize {
    return mov_r32_esp_add(write_at, 0x44, delta);
}

pub fn mov_ebx_esp_add(write_at: usize, delta: i8) usize {
    return mov_r32_esp_add(write_at, 0x5C, delta);
}

pub fn mov_ecx_esp_add(write_at: usize, delta: i8) usize {
    return mov_r32_esp_add(write_at, 0x4C, delta);
}

pub fn mov_edx_esp_add(write_at: usize, delta: i8) usize {
    return mov_r32_esp_add(write_at, 0x54, delta);
}

// mov r/m32 imm32
pub fn mov_espoff_imm32(write_at: usize, off8: u8, imm32: u32) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xC7);
    addr = mem.write(addr, u8, 0x44);
    addr = mem.write(addr, u8, 0x24);
    addr = mem.write(addr, u8, off8);
    addr = mem.write(addr, u32, imm32);
    return addr;
}

// TODO: impl different offset sizes (not just .reg)?? afaik should be same as
// `mov_rm32_r32` but modRM instead of modMR; both are incomplete (other is newer)?
/// mov r32(@dst), r/m32(@src)
pub fn mov_r32_rm32(write_at: usize, r32: u8, comptime T: type, rm32: T) usize {
    assert(T == u8 or T == u32);
    var addr = write_at;
    addr = mem.write(addr, u8, 0x8B);
    addr = mem.write(addr, u8, r32);
    addr = mem.write(addr, T, rm32);
    return addr;
}

pub fn mov_eax_esp(write_at: usize) usize {
    return mov_rm32_r32(write_at, .eax, .esp);
}

// actually, register + u32 offset
pub fn mov_ecx_u32(write_at: usize, u: u32) usize {
    return mov_r32_rm32(write_at, 0x8E, u32, u);
}

// actually, register + u8 offset
pub fn mov_ecx_b(write_at: usize, b: u8) usize {
    return mov_r32_rm32(write_at, 0x4E, u8, b);
}

pub fn mov_edx(write_at: usize, value: u32) usize {
    return mov_r32_rm32(write_at, 0x15, u32, value);
}

// TODO: impl different offset sizes? (not just .reg)
/// mov r/m32(@dst), r32(@src)
pub fn mov_rm32_r32(write_at: usize, comptime dst: GenReg32, comptime src: GenReg32) usize {
    return op_modMR(write_at, 0x89, .reg, dst, src);
}

test "mov_rm32_r32" {
    const test_cases = [_]struct { GenReg32, GenReg32, [2]u8 }{
        .{ .edx, .esp, [2]u8{ 0x89, 0xE2 } },
        .{ .ebp, .esp, [2]u8{ 0x89, 0xE5 } },
        .{ .esp, .ebp, [2]u8{ 0x89, 0xEC } },
        .{ .ebp, .eax, [2]u8{ 0x89, 0xC5 } },
        .{ .eax, .ebp, [2]u8{ 0x89, 0xE8 } },
    };

    var output: [2]u8 = undefined;
    errdefer std.debug.print("\n", .{});
    inline for (test_cases, 0..) |t, i| {
        const expected = t[2];
        errdefer std.debug.print("FAILED {d:0>2} :: i: mov {s}, {s}  o: {s}  e: {s}\n", .{
            i, @tagName(t[0]), @tagName(t[1]), bytesToHex(&output, .upper), bytesToHex(&expected, .upper),
        });
        _ = mov_rm32_r32(@intFromPtr(&output), t[0], t[1]);
        try std.testing.expectEqualSlices(u8, &expected, &output);
    }
}

// FIXME: not functional, in progress
//pub inline fn mov(
//    write_at: usize,
//    tgt: union(enum) { r16: GenReg16, r32: GenReg32 },
//    src: union(enum) { rm16: GenReg16, rm32: GenReg32, imm32: u32 },
//    reg_offset: ?i32,
//) usize {
//    _ = reg_offset;
//    var off = write_at;
//    off = switch (tgt) {
//        .r32 => |dest| switch (src) {
//            .rm16 => @panic("mov: r32->rm16 not impl"),
//            .rm32 => |source| op_modRM(off, 0x8B, .mem8, dest, source),
//            else => @panic("mov: r32 invalid src"),
//        },
//        .r16 => @panic("mov: r16 not impl"),
//    };
//    return off;
//}

// https://www.felixcloutier.com/x86/lea
// TODO: figure out if anything different needs to happen for GenReg16
// TODO: impl different offset sizes?
/// lea dst, [src+off]
pub inline fn lea(write_at: usize, dst: GenReg32, src: GenReg32, off: i8) usize {
    var addr = write_at;
    addr = op_modRM(addr, 0x8D, .mem8, dst, src);
    addr = mem.write(addr, i8, off);
    return addr;
}

test "lea" {
    const test_cases = [_]struct { GenReg32, GenReg32, i8, [3]u8 }{
        .{ .eax, .ebp, -4, [3]u8{ 0x8D, 0x45, 0xFC } },
    };

    var output: [3]u8 = undefined;
    errdefer std.debug.print("\n", .{});
    inline for (test_cases, 0..) |t, i| {
        const expected = t[3];
        errdefer std.debug.print("FAILED {d:0>2} :: i: lea {s}, [{s} + {d}]  o: {s}  e: {s}\n", .{
            i, @tagName(t[0]), @tagName(t[1]), t[2], bytesToHex(&output, .upper), bytesToHex(&expected, .upper),
        });
        _ = lea(@intFromPtr(&output), t[0], t[1], t[2]);
        try std.testing.expectEqualSlices(u8, &expected, &output);
    }
}

pub const PushSrc = union(enum) { imm8: u8, imm16: u16, imm32: u32, seg: SegReg, r16: GenReg16, r32: GenReg32 };

// TODO: r/m16, r/m32 (FF /6)
pub inline fn push(write_at: usize, src: PushSrc) usize {
    switch (src) {
        .r16 => |reg| return op_r16(write_at, 0x50, reg),
        .r32 => |reg| return op_r32(write_at, 0x50, reg),
        .imm8 => |imm| return op_imm8(write_at, 0x6A, imm),
        .imm16, .imm32 => |imm| return op_imm32(write_at, 0x68, imm),
        .seg => |seg| return switch (seg) {
            .cs => mem.write(write_at, u8, 0x0E),
            .ss => mem.write(write_at, u8, 0x16),
            .ds => mem.write(write_at, u8, 0x1E),
            .es => mem.write(write_at, u8, 0x06),
            .fs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA0 }, 2),
            .gs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA8 }, 2),
        },
    }
}

pub const PopDest = union(enum) { seg: SegReg, r16: GenReg16, r32: GenReg32 };

// TODO: r/m16, r/m32 (8F /0)
pub inline fn pop(write_at: usize, dest: PopDest) usize {
    switch (dest) {
        .r16 => |reg| return op_r16(write_at, 0x58, reg),
        .r32 => |reg| return op_r32(write_at, 0x58, reg),
        .seg => |seg| return switch (seg) {
            .ds => mem.write(write_at, u8, 0x1F),
            .es => mem.write(write_at, u8, 0x07),
            .ss => mem.write(write_at, u8, 0x17),
            .fs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA1 }, 2),
            .gs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA9 }, 2),
            else => @panic("pop(): invalid segment register"),
        },
    }
}

// helpers to move register values around

/// save value at register @reg in register @into, preserving @into on the stack
/// in the meantime. pair with `reg_restore`.
pub fn reg_save(write_at: usize, comptime reg: GenReg32, comptime into: GenReg32) usize {
    var addr: usize = write_at;
    addr = push(addr, .{ .r32 = into });
    addr = mov_rm32_r32(addr, into, reg);
    return addr;
}

/// counterpart to `reg_save` used to clean up stack and registers.
pub fn reg_restore(write_at: usize, comptime reg: GenReg32, comptime from: GenReg32) usize {
    var addr: usize = write_at;
    addr = mov_rm32_r32(addr, reg, from);
    addr = pop(addr, .{ .r32 = from });
    return addr;
}

// --------
// call
// --------

// WARN: could underflow, but not likely for our use case i guess
// call_rel32
pub fn call(write_at: usize, fn_addr: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xE8);
    addr = mem.write(addr, i32, @as(i32, @bitCast(fn_addr)) - (@as(i32, @bitCast(addr)) + 4));
    return addr;
}
pub fn call_rm32(write_at: usize, fn_addr: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xFF);
    addr = mem.write(addr, u32, fn_addr);
    return addr;
}

pub fn call_one_u32_param(write_at: usize, fn_addr: usize) usize {
    var addr = write_at;
    addr = reg_save(addr, .esp, .ebp);
    addr = mov_eax_esp_add(addr, 0x08);
    addr = push(addr, .{ .r32 = .eax });
    addr = call(addr, fn_addr);
    addr = reg_restore(addr, .esp, .ebp);
    return addr;
}

// --------
// jump/jcc
// --------

// TODO: generalized fn that automatically checks for short jumps, etc.
// TODO: same for all jcc stuff
// WARN: could underflow, but not likely for our use case i guess
// jmp_rel32
pub fn jmp(write_at: usize, jmp_addr: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xE9);
    addr = mem.write(addr, i32, @as(i32, @bitCast(jmp_addr)) - (@as(i32, @bitCast(addr)) + 4));
    return addr;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jnz_rel32
pub fn jnz(write_at: usize, jmp_addr: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x0F);
    addr = mem.write(addr, u8, 0x85);
    addr = mem.write(addr, i32, @as(i32, @bitCast(jmp_addr)) - (@as(i32, @bitCast(addr)) + 4));
    return addr;
}

// TODO: auto-calculate offset like the other jcc fns
pub fn jz_rel8(write_at: usize, value: i8) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x74);
    addr = mem.write(addr, i8, value);
    return addr;
}

// TODO: auto-calculate offset like the other jcc fns
pub fn jnz_rel8(write_at: usize, value: i8) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x75);
    addr = mem.write(addr, i8, value);
    return addr;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jz_rel32
pub fn jz(write_at: usize, jmp_addr: usize) usize {
    var addr = write_at;
    addr = mem.write(addr, u8, 0x0F);
    addr = mem.write(addr, u8, 0x84);
    addr = mem.write(addr, i32, @as(i32, @bitCast(jmp_addr)) - (@as(i32, @bitCast(addr)) + 4));
    return addr;
}

// --------
// return
// --------

pub fn retn(write_at: usize) usize {
    return mem.write(write_at, u8, 0xC3);
}

pub fn retn_imm16(write_at: u32, bytes: u16) u32 {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xC2);
    addr = mem.write(addr, u16, bytes);
    return addr;
}

// --------
// no-op
// --------

pub fn nop(write_at: usize) usize {
    return mem.write(write_at, u8, 0x90);
}

pub fn nop_align(write_at: usize, increment: usize) usize {
    var addr: usize = write_at;
    while (addr % increment > 0) {
        addr = nop(addr);
    }
    return addr;
}

pub fn nop_until(write_at: usize, end: usize) usize {
    var addr: usize = write_at;
    while (addr < end) {
        addr = nop(addr);
    }
    return addr;
}

// --------
// function calls
// https://en.wikibooks.org/wiki/X86_Disassembly/Calling_Conventions
// https://blog.aaronballman.com/2012/02/describing-the-msvc-abi-for-structure-return-types/
// --------

pub fn stackframe_start(write_at: u32) u32 {
    return reg_save(write_at, .esp, .ebp);
}

// NOTE: not sure if 'mov esp, ebp' needed, seems always skipped in practice?
pub fn stackframe_end(write_at: u32) u32 {
    return reg_restore(write_at, .esp, .ebp);
}

// cdecl: _FunctionName

pub fn cdecl_call(write_at: u32, fn_ptr: u32, arguments: ?[]const PushSrc) u32 {
    var addr = write_at;
    if (arguments) |args| {
        assert(args.len > 0);
        assert(args.len < 32);
        for (args, 0..) |_, i|
            addr = push(addr, args[args.len - i - 1]);
    }
    addr = call(addr, fn_ptr);
    if (arguments) |args|
        addr = add_esp8(addr, @intCast(4 * args.len));
    return addr;
}

pub fn cdecl_body_entry(write_at: u32) u32 {
    return stackframe_start(write_at);
}

pub fn cdecl_body_exit(write_at: u32) u32 {
    var addr = write_at;
    // TODO: return value; 4b=eax, 8b=eax/edx
    addr = stackframe_end(addr);
    addr = retn(addr);
    addr = nop_align(addr, 0x10);
    return addr;
}

// stdcall: _FunctionName@<args*4>

pub fn stdcall_call(write_at: u32, fn_ptr: u32, arguments: ?[]const PushSrc) u32 {
    var addr = write_at;
    if (arguments) |args| {
        assert(args.len > 0);
        assert(args.len < 32);
        for (args, 0..) |_, i|
            addr = push(addr, args[args.len - i - 1]);
    }
    addr = call(addr, fn_ptr);
    return addr;
}

pub fn stdcall_body_entry(write_at: u32) u32 {
    return stackframe_start(write_at);
}

pub fn stdcall_body_exit(write_at: u32, num_args: u16) u32 {
    assert(num_args < 32);
    var addr = write_at;
    // TODO: return value; 4b=eax, 8b=eax/edx
    addr = stackframe_end(addr);
    addr = retn_imm16(addr, num_args * 4);
    addr = nop_align(addr, 0x10);
    return addr;
}

// fastcall: @FunctionName@<args*4>

// assert arguments.len <= 3
// not standardized; i.e. this will only guarantee compatibility with itself
// pub fn fastcall_call(write_at: u32, arguments: []u32)
// pub fn fastcall_body_entry(write_at: u32)
// pub fn fastcall_body_exit(write_at: u32, arguments: u16)

// --------
// detour
// --------

pub const Detour = struct {
    const AlignSize: u32 = 16;

    entry_addr: u32,
    return_addr: u32,
    buf: []u8,
    addr: u32,
};

// TODO: optional nop_until
// TODO: option to auto copy overwritten bytes to detour buffer
pub fn detour_start(data: *Detour, write_at: u32, return_to: u32, buf: []u8) void {
    assert(buf.len % Detour.AlignSize == 0);
    assert(return_to > write_at);
    assert(return_to - write_at >= 5); // jmp long instruction size
    data.entry_addr = write_at;
    data.return_addr = return_to;
    data.buf = buf;
    data.addr = @intFromPtr(buf.ptr);
    var addr = write_at;
    addr = jmp(write_at, data.addr);
    addr = nop_until(addr, return_to);
}

// between these two functions, write to buf the usual way using Detour.addr
// example: my_detour.addr = jmp(my_detour.addr, 0xDEADBEEF);

// TODO: optional nop_align
pub fn detour_end(data: *Detour) void {
    data.addr = jmp(data.addr, data.return_addr);
    data.addr = nop_align(data.addr, Detour.AlignSize);
    assert(data.addr - @intFromPtr(data.buf.ptr) <= data.buf.len);
}

pub fn detour_unused_space(data: *Detour) u32 {
    return data.buf.len - (data.addr - @intFromPtr(data.buf.ptr));
}
