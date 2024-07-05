pub const Self = @This();

const std = @import("std");
const mem = @import("memory.zig");

// NOTE: supporting x86 only, not x86_64

const GenReg32 = enum(u8) { eax, ecx, edx, ebx, esp, ebp, esi, edi }; // general register
const GenReg16 = enum(u8) { ax, cx, dx, bx, sp, bp, si, di }; // general register
const SegReg = enum { cs, ss, ds, es, fs, gs }; // segment register
const OpEn = enum { mem, reg, imm, zo }; // operator encoding
const EffAdd = enum(u8) { mem, mem8, mem32, reg }; // effective address

// helpers

inline fn parseRM(comptime reg: GenReg32) u8 {
    return @intFromEnum(reg) * 0x08;
}

inline fn parseMod(comptime mod: EffAdd) u8 {
    return @intFromEnum(mod) * 0x40;
}

inline fn parseModRM(
    comptime mod: EffAdd,
    comptime rm: GenReg32, // dest
    comptime reg: GenReg32, // src
) u8 {
    return @intFromEnum(mod) * 0x40 + @intFromEnum(reg) + @intFromEnum(rm) * 0x08;
}

// TODO: op_r16, op_r32 reg and base+reg should be comptime, not sure why zig
// complains about them when e.g. push() is called with runtime .imm32 value,
// they should not be called in that case anyway

pub inline fn op_r16(
    offset: usize,
    comptime base: u8,
    reg: GenReg16,
) usize {
    return mem.write_bytes(offset, &[2]u8{ 0x66, base + @intFromEnum(reg) }, 2);
}

pub inline fn op_r32(
    offset: usize,
    comptime base: u8,
    reg: GenReg32,
) usize {
    return mem.write(offset, u8, base + @intFromEnum(reg));
}

pub inline fn op_imm8(
    offset: usize,
    comptime op: u8,
    value: u8,
) usize {
    return mem.write_bytes(offset, &[2]u8{ op, value }, 2);
}

pub inline fn op_imm32(
    offset: usize,
    comptime op: u8,
    value: u32,
) usize {
    var addr = mem.write(offset, u8, op);
    return mem.write(addr, u32, value);
}

pub inline fn op_modRM(
    offset: usize,
    op: u8,
    comptime mod: EffAdd,
    comptime dest: GenReg32,
    comptime src: GenReg32,
) usize {
    var addr = mem.write(offset, u8, op);
    return mem.write(addr, u32, comptime parseModRM(mod, dest, src));
}

// stuff

pub fn add_rm32_imm8(memory_offset: usize, rm32: u8, imm8: u8) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x83);
    offset = mem.write(offset, u8, rm32);
    offset = mem.write(offset, u8, imm8);
    return offset;
}

pub fn sub_rm32_imm8(memory_offset: usize, rm32: u8, imm8: i8) usize {
    const imm8_u8: u8 = @bitCast(imm8);
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x83);
    offset = mem.write(offset, u8, rm32);
    offset = mem.write(offset, u8, imm8_u8);
    return offset;
}

pub fn add_esp8(memory_offset: usize, value: u8) usize {
    return add_rm32_imm8(memory_offset, 0xC4, value);
}

pub fn add_rm32_imm32(memory_offset: usize, rm32: u8, imm32: u32) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x81);
    offset = mem.write(offset, u8, rm32);
    offset = mem.write(offset, u32, imm32);
    return offset;
}

pub fn add_esp32(memory_offset: usize, value: u32) usize {
    return add_rm32_imm32(memory_offset, 0xC4, value);
}

pub fn test_rm32_r32(memory_offset: usize, r32: u8) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x85);
    offset = mem.write(offset, u8, r32);
    return offset;
}

pub fn test_eax_eax(memory_offset: usize) usize {
    return test_rm32_r32(memory_offset, 0xC0);
}

pub fn test_edx_edx(memory_offset: usize) usize {
    return test_rm32_r32(memory_offset, 0xD2);
}

pub fn mov_ecx_imm32(memory_offset: usize, comptime T: type, imm32: T) usize {
    std.debug.assert(T == u8 or T == u32);
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xB9); // EDX=BA, EBX=BB
    offset = mem.write(offset, T, imm32);
    return offset;
}
pub fn mov_eax_imm32(memory_offset: usize, comptime T: type, imm32: T) usize {
    std.debug.assert(T == u8 or T == u32);
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xB8);
    offset = mem.write(offset, T, imm32);
    return offset;
}

pub fn mov_eax_moffs32(memory_offset: usize, moffs32: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xA1);
    offset = mem.write(offset, usize, moffs32);
    return offset;
}

pub fn mov_r32_rm32(memory_offset: usize, r32: u8, comptime T: type, rm32: T) usize {
    std.debug.assert(T == u8 or T == u32);
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x8B);
    offset = mem.write(offset, u8, r32);
    offset = mem.write(offset, T, rm32);
    return offset;
}

pub fn mov_eax_esp(memory_offset: usize) usize {
    return mov_rm32_r32(memory_offset, 0xC4);
}

// actually, register + u32 offset
pub fn mov_ecx_u32(memory: usize, u: u32) usize {
    return mov_r32_rm32(memory, 0x8E, u32, u);
}

// actually, register + u8 offset
pub fn mov_ecx_b(memory: usize, b: u8) usize {
    return mov_r32_rm32(memory, 0x4E, u8, b);
}

pub fn mov_edx(memory_offset: usize, value: u32) usize {
    return mov_r32_rm32(memory_offset, 0x15, u32, value);
}

// mov r32, [esp+<delta>]
pub fn mov_r32_esp_add(memory_offset: usize, r32: u8, delta: i8) usize {
    // values less than zero have the upper bit set
    var delta_u8: u8 = @bitCast(delta);
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x8B);
    offset = mem.write(offset, u8, r32);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, delta_u8);
    return offset;
}

pub fn mov_eax_esp_add(memory_offset: usize, delta: i8) usize {
    return mov_r32_esp_add(memory_offset, 0x44, delta);
}

pub fn mov_ebx_esp_add(memory_offset: usize, delta: i8) usize {
    return mov_r32_esp_add(memory_offset, 0x5C, delta);
}

pub fn mov_ecx_esp_add(memory_offset: usize, delta: i8) usize {
    return mov_r32_esp_add(memory_offset, 0x4C, delta);
}

pub fn mov_edx_esp_add(memory_offset: usize, delta: i8) usize {
    return mov_r32_esp_add(memory_offset, 0x54, delta);
}

// mov r/m32 imm32
pub fn mov_espoff_imm32(memory_offset: usize, off8: u8, imm32: u32) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xC7);
    offset = mem.write(offset, u8, 0x44);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, off8);
    offset = mem.write(offset, u32, imm32);
    return offset;
}

pub fn mov_rm32_r32(memory_offset: usize, r32: u8) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x89);
    offset = mem.write(offset, u8, r32);
    return offset;
}

pub fn mov_edx_esp(memory_offset: usize) usize {
    return mov_rm32_r32(memory_offset, 0xE2);
}

// TODO: r/m16, r/m32 (FF /6)
pub inline fn push(
    offset: usize,
    operand: union(enum) { imm8: u8, imm16: u16, imm32: u32, seg: SegReg, r16: GenReg16, r32: GenReg32 },
) usize {
    switch (operand) {
        .r16 => |reg| return op_r16(offset, 0x50, reg),
        .r32 => |reg| return op_r32(offset, 0x50, reg),
        .imm8 => |imm| return op_imm8(offset, 0x6A, imm),
        .imm16, .imm32 => |imm| return op_imm32(offset, 0x68, imm),
        .seg => |seg| return switch (seg) {
            .cs => mem.write(offset, u8, 0x0E),
            .ss => mem.write(offset, u8, 0x16),
            .ds => mem.write(offset, u8, 0x1E),
            .es => mem.write(offset, u8, 0x06),
            .fs => mem.write_bytes(offset, &[2]u8{ 0x0F, 0xA0 }, 2),
            .gs => mem.write_bytes(offset, &[2]u8{ 0x0F, 0xA8 }, 2),
        },
    }
}

// TODO: r/m16, r/m32 (8F /0)
pub inline fn pop(
    offset: usize,
    operand: union(enum) { seg: SegReg, r16: GenReg16, r32: GenReg32 },
) usize {
    switch (operand) {
        .r16 => |reg| return op_r16(offset, 0x58, reg),
        .r32 => |reg| return op_r32(offset, 0x58, reg),
        .seg => |seg| return switch (seg) {
            .ds => mem.write(offset, u8, 0x1F),
            .es => mem.write(offset, u8, 0x07),
            .ss => mem.write(offset, u8, 0x17),
            .fs => mem.write_bytes(offset, &[2]u8{ 0x0F, 0xA1 }, 2),
            .gs => mem.write_bytes(offset, &[2]u8{ 0x0F, 0xA9 }, 2),
            else => @panic("pop(): invalid segment register"),
        },
    }
}

pub fn save_esp(memory_offset: usize) usize {
    var offset: usize = memory_offset;
    // ; push ebp
    // ; mov ebp, esp
    offset = push(offset, .{ .r32 = .ebp });
    offset = mov_rm32_r32(offset, 0xE5);
    return offset;
}

pub fn restore_esp(memory_offset: usize) usize {
    var offset: usize = memory_offset;
    // ; mov esp, ebp
    // ; pop ebp
    offset = mov_rm32_r32(offset, 0xEC);
    offset = pop(offset, .{ .r32 = .ebp });
    return offset;
}

pub fn save_eax(memory_offset: usize) usize {
    var offset: usize = memory_offset;
    // ; push ebp
    // ; mov ebp, eax
    offset = push(offset, .{ .r32 = .ebp });
    offset = mov_rm32_r32(offset, 0xC5);
    return offset;
}

pub fn restore_eax(memory_offset: usize) usize {
    var offset: usize = memory_offset;
    // ; mov eax, ebp
    // ; pop ebp
    offset = mov_rm32_r32(offset, 0xE8);
    offset = pop(offset, .{ .r32 = .ebp });
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// call_rel32
pub fn call(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xE8);
    offset = mem.write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}
pub fn call_rm32(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xFF);
    offset = mem.write(offset, u32, address);
    return offset;
}

pub fn call_one_u32_param(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = save_esp(offset);
    offset = mov_eax_esp_add(offset, 0x08);
    offset = push(offset, .{ .r32 = .eax });
    offset = call(offset, address);
    offset = restore_esp(offset);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jmp_rel32
pub fn jmp(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0xE9);
    offset = mem.write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jnz_rel32
pub fn jnz(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x0F);
    offset = mem.write(offset, u8, 0x85);
    offset = mem.write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

pub fn jz_rel8(memory: usize, value: i8) usize {
    var offset = memory;
    offset = mem.write(offset, u8, 0x74);
    offset = mem.write(offset, i8, value);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jz_rel32
pub fn jz(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x0F);
    offset = mem.write(offset, u8, 0x84);
    offset = mem.write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

pub fn retn(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0xC3);
}

pub fn nop(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x90);
}

pub fn nop_align(memory_offset: usize, increment: usize) usize {
    var offset: usize = memory_offset;
    while (offset % increment > 0) {
        offset = nop(offset);
    }
    return offset;
}

pub fn nop_until(memory_offset: usize, end: usize) usize {
    var offset: usize = memory_offset;
    while (offset < end) {
        offset = nop(offset);
    }
    return offset;
}
