pub const Self = @This();

const std = @import("std");
const mem = @import("memory.zig");

pub fn add_rm32_imm8(memory_offset: usize, rm32: u8, imm8: u8) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x83);
    offset = mem.write(offset, u8, rm32);
    offset = mem.write(offset, u8, imm8);
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

pub fn push_eax(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x50);
}

pub fn push_edx(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x52);
}

pub fn push_ebp(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x55);
}

pub fn push_esi(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x56);
}

pub fn push_edi(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x57);
}

pub fn pop_eax(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x58);
}

pub fn pop_edx(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x5A);
}

pub fn pop_edi(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x5F);
}

pub fn pop_esi(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x5E);
}

pub fn pop_ebp(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x5D);
}

pub fn pop_ebx(memory_offset: usize) usize {
    return mem.write(memory_offset, u8, 0x5B);
}

pub fn push_u32(memory_offset: usize, value: usize) usize {
    var offset = memory_offset;
    offset = mem.write(offset, u8, 0x68);
    offset = mem.write(offset, u32, value);
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
