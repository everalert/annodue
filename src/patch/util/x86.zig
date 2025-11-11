pub const Self = @This();

const std = @import("std");
const mem = @import("memory.zig");
const assert = std.debug.assert;
const bytesToHex = std.fmt.bytesToHex;
const fmtSliceHexUpper = std.fmt.fmtSliceHexUpper;

// NOTE: supporting x86 only, not x86_64
// TODO: change all usize to u32; ensures correct size of address-related params
// when not compiling for x86 target
// FIXME: cut down on comptime requirements as much as possible (to reduce
// function coloring)
// FIXME: values are "type-less" because two's complement makes signed/unsigned
// the same at bit-level; what convention should be used to allow user to use
// both iN/uN types? or is it ok to just let them spam `@bitCast`?
// - for now, defaulting to signed types because pointer offsets are signed

// references
// https://wiki.osdev.org/X86-64_Instruction_Encoding
// https://sandpile.org/x86/opc_rm.htm
// https://sandpile.org/x86/opc_enc.htm
// https://www.c-jump.com/CIS77/CPU/x86/lecture.html
// http://ref.x86asm.net/coder32.html
// https://pnx.tf/files/x86_opcode_structure_and_instruction_overview.pdf
// https://shell-storm.org/online/Online-Assembler-and-Disassembler/
// https://disasm.pro/
// https://godbolt.org/

const SegReg = enum { cs, ss, ds, es, fs, gs }; // segment register
const OpEn = enum { mem, reg, imm, zo }; // operator encoding
const EffAdd = enum(u2) { mem, mem8, mem32, reg }; // effective address

// general registers
// TODO: separate index/pointer registers from 16/32-bit register enum
const GenReg8 = enum(u3) { al, cl, dl, bl, ah, ch, dh, bh };
const GenReg16 = enum(u3) { ax, cx, dx, bx, sp, bp, si, di };
const GenReg32 = enum(u3) { eax, ecx, edx, ebx, esp, ebp, esi, edi };

const GenReg = enum(u5) {
    const Type = enum(u2) { r8, r16, r32, imm };

    // zig fmt: off
     al = 0o00,  cl = 0o01,  dl = 0o02,  bl = 0o03,  ah = 0o04,  ch = 0o05,  dh = 0o06,  bh = 0o07,
     ax = 0o10,  cx = 0o11,  dx = 0o12,  bx = 0o13,  sp = 0o14,  bp = 0o15,  si = 0o16,  di = 0o17,
    eax = 0o20, ecx = 0o21, edx = 0o22, ebx = 0o23, esp = 0o24, ebp = 0o25, esi = 0o26, edi = 0o27,
    imm = 0o30,
    // zig fmt: on

    pub fn RegType(r: GenReg) Type {
        return @enumFromInt(r.RegTypeIndex());
    }

    pub fn RegTypeIndex(r: GenReg) u2 {
        return @truncate(@as(u5, @intFromEnum(r)) >> 3);
    }

    pub fn RegIndex(r: GenReg) u3 {
        return @truncate(@as(u5, @intFromEnum(r)));
    }
};

// FIXME: merge with EffAdd; this is the same thing, but with better tag names
const Addressing = enum(u2) {
    disp0 = 0,
    disp8 = 1,
    disp32 = 2,
    reg = 3,

    pub fn FromLength(length: ?u8) Addressing {
        return if (length) |l| switch (l) {
            0 => .disp0,
            1 => .disp8,
            2, 4 => .disp32,
            else => @panic("invalid value"),
        } else .reg;
    }
};

pub const ModRM = packed struct(u8) {
    rm: u3,
    reg: u3,
    mod: u2,

    pub fn Make(mod: Addressing, reg: GenReg, rm: GenReg) ModRM {
        return ModRM{ .mod = @intFromEnum(mod), .reg = reg.RegIndex(), .rm = rm.RegIndex() };
    }
};

const SIB = packed struct(u8) {
    s: u2, // scale (1<<s)
    i: u3, // index register
    b: u3, // base register
};

// helpers

// FIXME: .mem could have a displacement value, if SIB base == 0b101
inline fn parseEffAddFromDispType(comptime T: type) EffAdd {
    return switch (T) {
        i0 => .mem, // not null (still need SIB), but no displacement value
        i8 => .mem8,
        i32 => .mem32,
        @TypeOf(null) => .reg,
        else => @panic("invalid type"),
    };
}

// FIXME: .mem could have a displacement value, if SIB base == 0b101
inline fn parseEffAddFromDispSize(size: ?u3) EffAdd {
    return if (size) |s| switch (s) {
        0 => .mem, // not null (still need SIB), but no displacement value
        1 => .mem8,
        2, 3, 4 => .mem32,
        else => @panic("invalid byte length"),
    } else .reg;
}

inline fn parseDispTypeFromEffAdd(comptime ea: EffAdd) type {
    return switch (ea) {
        .mem => i0,
        .mem8 => i8,
        .mem32 => i32,
        .reg => null,
    };
}

fn parseOperandSize(n: i32, use_16bit: bool) u8 {
    if (n >= std.math.minInt(i8) and n <= std.math.maxInt(i8)) return 1;
    if (n >= std.math.minInt(i16) and n <= std.math.maxInt(i16) and use_16bit) return 2;
    return 4;
}

inline fn parseRM(comptime reg: GenReg32) u8 {
    return @as(u8, @intCast(@intFromEnum(reg))) * 0x08;
}

inline fn parseMod(comptime mod: EffAdd) u8 {
    return @as(u8, @intCast(@intFromEnum(mod))) * 0x40;
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
    return mem.write_bytes(write_at, &[2]u8{ 0x66, base + @intFromEnum(reg) });
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
    return mem.write_bytes(write_at, &[2]u8{ op, value });
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

fn parseAddSubOperandSize(n: i32, base: u8, dst: GenReg, b_ptr: bool, b_use_16bit: bool) u8 {
    const op_size = parseOperandSize(n, b_use_16bit);
    if (b_ptr or (base == 0x83 and op_size == 1)) return op_size;
    return @as(u8, 1) << dst.RegTypeIndex();
}

// ----------
// arithmetic
// ----------

// FIXME: add tests: OR, ADC, SBB, AND, XOR, CMP
// FIXME: impl SIB byte output, needed for non-low BYTE PTR output; see [ah] case
// in add tests (commented), likely also need tests for [sp], [esp]
// TODO: look into accepting register width mismatch; doesn't always result in
// different output, need to decide if i want registers promoted implicitly
//   see disasm.pro:   add [ebx+5], cl   VS   add [bx+5], cl   VS   add [bl+5], cl
/// generic instruction logic shared between most arithmetic instructions. use
/// the dedicated helper functions for specific instructions.
/// - register widths must match (e.g. @dst==.ah, @src==.bx)
/// - immediate value will be truncated to @dst register width
/// @dst    op1 reg
/// @v1     op1 offset when dereferencing op1 as r/m, else null
/// @src    op2 reg
/// @v2     op2 offset when dereferencing op2 as r/m, or immediate value when op2 is imm, else null
/// examples:
/// ADD EAX, EBX                    ADD(<addr>, .eax, null, .ebx, null) // (r, r/m)
/// ADD EAX, [EBX]                  ADD(<addr>, .eax, null, .ebx, 0)    // (r, r/m) with deref
/// ADD [EAX], EBX                  ADD(<addr>, .eax,    0, .ebx, null) // (r/m, r)
/// ADD EAX, [EBX+4]                ADD(<addr>, .eax, null, .ebx, 4)    // (r, r/m) with deref and offset
/// ADD EAX, 4                      ADD(<addr>, .eax, null, .imm, 4)    // (r/m, imm)
/// ADD [EAX+4], 4                  ADD(<addr>, .eax,    4, .imm, 4)    // (r/m, imm) with offset
/// ADD AL, BYTE PTR [EBX+4]        ADD(<addr>,  .al, null,  .bl, 4)    // byte derefs must be low byte
/// ADD WORD PTR [EBX+0xF0], 0xFF   ADD(<addr>, .bx, 0xF0, .imm, 0xFF)
pub fn GenericArithmeticInstruction(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32, comptime V_BASE: u8, comptime V_EXT: u3) usize {
    const dst_t = dst.RegType();
    const src_t = src.RegType();
    const dst_ri = dst.RegIndex();
    const src_ri = src.RegIndex();
    assert(dst_t != .imm);
    assert(src_t == .imm or !(v1 != null and v2 != null)); // only one reg can deref
    assert(src_t == .imm or dst_t == src_t); // register widths must match
    assert(v1 == null or dst_t != .r8 or dst_ri < 4); // BYTE derefs must be low byte
    assert(v2 == null or src_t != .r8 or src_ri < 4);

    const b_8bit = (dst_t == .r8 or src_t == .r8);
    const b_16bit = (dst_t == .r16 or src_t == .r16);
    const b_r_rm = (src_t != .imm and v2 != null);
    const b_a_reg = (dst_ri == 0 and v1 == null);
    const b_mod_ext = (src_t == .imm and !b_a_reg);
    const b_ptr = (v1 != null or (src_t != .imm and v2 != null));

    var base: u8 = if (src_t == .imm) base: {
        if (b_a_reg) break :base V_BASE | 0b00000100;
        break :base 0b10000000;
    } else V_BASE;
    if (!b_8bit)
        base |= 0b00000001;
    if (b_r_rm or (base == 0x81 and v2.? >= -127 and v2.? <= 128))
        base |= 0b00000010;

    const v1_s: u8 = if (v1) |v| parseAddSubOperandSize(v, base, dst, b_ptr, b_16bit and src_t != .imm) else 0;
    const v1_b: ?[]const u8 = if (v1) |*v| @as([*]const u8, @ptrCast(v))[0..4] else null;
    const v2_s: u8 = if (v2) |v| parseAddSubOperandSize(v, base, dst, b_ptr, b_16bit) else 0;
    const v2_b: ?[]const u8 = if (v2) |*v| @as([*]const u8, @ptrCast(v))[0..4] else null;

    const mod_rm: ?ModRM = if (base & 0b100 == 0) mod_rm: {
        var mod: ModRM = undefined;
        if (b_r_rm) mod = ModRM.Make(Addressing.FromLength(if (v2) |_| v2_s else null), dst, src);
        if (!b_r_rm) mod = ModRM.Make(Addressing.FromLength(if (v1) |_| v1_s else null), src, dst);
        if (b_mod_ext) mod.reg = V_EXT;
        break :mod_rm mod;
    } else null;

    var addr = write_at;
    addr = if (b_16bit) mem.write(addr, u8, 0x66) else addr;
    addr = mem.write(addr, u8, base);
    addr = if (mod_rm) |m| mem.write(addr, u8, @as(u8, @bitCast(m))) else addr;
    addr = if (v1_b) |b| mem.write_bytes(addr, b[0..v1_s]) else addr;
    addr = if (v2_b) |b| mem.write_bytes(addr, b[0..v2_s]) else addr;
    return addr;
}

const GenericArithmeticInstructionTestCase = struct { GenReg, ?i32, GenReg, ?i32, []const u8 };

fn GenericArithmeticInstructionTest(
    comptime label: []const u8,
    comptime test_fn: *const fn (usize, GenReg, ?i32, GenReg, ?i32) callconv(.Inline) usize,
    comptime test_cases: []const GenericArithmeticInstructionTestCase,
) !void {
    var output: [12]u8 = undefined;
    const output_a = @intFromPtr(&output);
    inline for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2} :: {s}(<addr>, .{s}, {?d}, .{s}, {?d})\n\n", .{
            i, label, @tagName(t[0]), t[1], @tagName(t[2]), t[3],
        });
        const expected = t[4];
        const output_len = test_fn(@intFromPtr(&output), t[0], t[1], t[2], t[3]) - output_a;
        const output_s = output[0..output_len];
        try std.testing.expectEqualSlices(u8, expected, output_s);
        try std.testing.expectEqual(expected.len, output_len);
    }
}

/// ADD - Add
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn ADD(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x00, 0);
}

// FIXME: something about this test makes zls stop autoformatting the remainder
// of the file, even though "zig fmt: on" is there
// - autoformatting works on the file up until this point
// - commenting between the zig fmt directives (exclusive) makes it work after fmt:on
// - removing the normal comments between the directives does not make it work
test "ADD" {
    try GenericArithmeticInstructionTest("ADD", &ADD, &[_]GenericArithmeticInstructionTestCase{
        // zig fmt: off
        // standard tests
        .{  .al, null, .imm, 0xF0, &[_]u8{       0x04,       0xF0,                                          } },
        .{  .ah, null, .imm, 0xF0, &[_]u8{       0x80, 0xC4, 0xF0,                                          } },
        .{  .al, null,  .ah, null, &[_]u8{       0x00, 0xE0,                                                } },
        .{  .al, 0x0F,  .cl, null, &[_]u8{       0x00, 0x48, 0x0F                                           } },
        .{  .al, 0xFF,  .cl, null, &[_]u8{       0x00, 0x88, 0xFF, 0x00, 0x00, 0x00                         } },
      //.{  .ah, 0x0F,  .cl, null, &[_]u8{       0x00, 0x4C, 0x24, 0x0F                                     } },
      //.{  .bh, 0x0F,  .cl, null, &[_]u8{       0x00, 0x4F, 0x0F                                           } },
        .{  .bl, null,  .ch, null, &[_]u8{       0x00, 0xEB,                                                } },
        .{  .bl, 0xF0, .imm, 0x0F, &[_]u8{       0x80, 0x83, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{  .ax, null, .imm, 0xF0, &[_]u8{ 0x66, 0x05,       0xF0, 0x00,                                    } },
        .{  .bx, null, .imm, 0xF0, &[_]u8{ 0x66, 0x81, 0xC3, 0xF0, 0x00,                                    } },
        .{  .ax, null,  .bx, null, &[_]u8{ 0x66, 0x01, 0xD8                                                 } },
        .{  .bx, 0xF0, .imm, 0x0F, &[_]u8{ 0x66, 0x83, 0x83, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{  .bx, 0xF0, .imm, 0xFF, &[_]u8{ 0x66, 0x81, 0x83, 0xF0, 0x00, 0x00, 0x00, 0xFF, 0x00             } },
        .{ .eax, null, .imm, 0xF0, &[_]u8{       0x05,       0xF0, 0x00, 0x00, 0x00                         } },
        .{ .ebx, null, .imm, 0xF0, &[_]u8{       0x81, 0xC3, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .ebp, null, .ebp, 0xF0, &[_]u8{       0x03, 0xAD, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, null, .ebp, 0xF0, &[_]u8{       0x03, 0x85, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, 0xF0, .ebp, null, &[_]u8{       0x01, 0xA8, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, 0xF0, .imm, 0xFF, &[_]u8{       0x81, 0x80, 0xF0, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00 } },
        .{ .eax, 0xF0, .imm, 0x0F, &[_]u8{       0x83, 0x80, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{ .ebx, null, .eax, null, &[_]u8{       0x01, 0xC3                                                 } },
        .{ .ebx, null, .imm, 0x7F, &[_]u8{       0x83, 0xC3, 0x7F                                           } },
        .{ .ebx, 0xF0, .ebx, null, &[_]u8{       0x01, 0x9B, 0xF0, 0x00, 0x00, 0x00                         } },
        // migration cases
        .{ .esp, null, .imm, 0x10,   &[_]u8{ 0x83, 0xC4, 0x10                   } },
        .{ .esp, null, .imm, 0x20,   &[_]u8{ 0x83, 0xC4, 0x20                   } },
        .{ .esp, null, .imm, 0x404,  &[_]u8{ 0x81, 0xC4, 0x04, 0x04, 0x00, 0x00 } },
        .{ .esp, null, .imm, -0x400, &[_]u8{ 0x81, 0xC4, 0x00, 0xFC, 0xFF, 0xFF } },
        .{ .esp, null, .imm, 0x4,    &[_]u8{ 0x83, 0xC4, 0x04                   } },
        // zig fmt: on
    });
}


/// OR - Logical Inclusive OR
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn OR(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x08, 1);
}

/// ADC - Add With Carry
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn ADC(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x10, 2);
}

/// SBB - Integer Subtraction With Borrow
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn SBB(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x18, 3);
}

/// AND - Logical AND
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn AND(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x20, 4);
}

/// SUB - Subtract
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn SUB(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x28, 5);
}

test "SUB" {
    try GenericArithmeticInstructionTest("SUB", &SUB, &[_]GenericArithmeticInstructionTestCase{
        // zig fmt: off
        .{  .al, null, .imm, 0xF0, &[_]u8{       0x2C,       0xF0,                                          } },
        .{  .ah, null, .imm, 0xF0, &[_]u8{       0x80, 0xEC, 0xF0,                                          } },
        .{  .al, null,  .ah, null, &[_]u8{       0x28, 0xE0,                                                } },
        .{  .al, 0x0F,  .cl, null, &[_]u8{       0x28, 0x48, 0x0F                                           } },
        .{  .al, 0xFF,  .cl, null, &[_]u8{       0x28, 0x88, 0xFF, 0x00, 0x00, 0x00                         } },
        .{  .bl, null,  .ch, null, &[_]u8{       0x28, 0xEB,                                                } },
        .{  .bl, 0xF0, .imm, 0x0F, &[_]u8{       0x80, 0xAB, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{  .ax, null, .imm, 0xF0, &[_]u8{ 0x66, 0x2D,       0xF0, 0x00,                                    } },
        .{  .bx, null, .imm, 0xF0, &[_]u8{ 0x66, 0x81, 0xEB, 0xF0, 0x00,                                    } },
        .{  .ax, null,  .bx, null, &[_]u8{ 0x66, 0x29, 0xD8                                                 } },
        .{  .bx, 0xF0, .imm, 0x0F, &[_]u8{ 0x66, 0x83, 0xAB, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{  .bx, 0xF0, .imm, 0xFF, &[_]u8{ 0x66, 0x81, 0xAB, 0xF0, 0x00, 0x00, 0x00, 0xFF, 0x00             } },
        .{ .eax, null, .imm, 0xF0, &[_]u8{       0x2D,       0xF0, 0x00, 0x00, 0x00                         } },
        .{ .ebx, null, .imm, 0xF0, &[_]u8{       0x81, 0xEB, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .ebp, null, .ebp, 0xF0, &[_]u8{       0x2B, 0xAD, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, null, .ebp, 0xF0, &[_]u8{       0x2B, 0x85, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, 0xF0, .ebp, null, &[_]u8{       0x29, 0xA8, 0xF0, 0x00, 0x00, 0x00                         } },
        .{ .eax, 0xF0, .imm, 0xFF, &[_]u8{       0x81, 0xA8, 0xF0, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00 } },
        .{ .eax, 0xF0, .imm, 0x0F, &[_]u8{       0x83, 0xA8, 0xF0, 0x00, 0x00, 0x00, 0x0F                   } },
        .{ .ebx, null, .eax, null, &[_]u8{       0x29, 0xC3                                                 } },
        .{ .ebx, null, .imm, 0x7F, &[_]u8{       0x83, 0xEB, 0x7F                                           } },
        .{ .ebx, 0xF0, .ebx, null, &[_]u8{       0x29, 0x9B, 0xF0, 0x00, 0x00, 0x00                         } },
        // zig fmt: on
    });
}

/// XOR - Logical Exclusive OR
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn XOR(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x30, 6);
}

// NOTE: technically not in the "arithmetic" category, but shares same logic
/// CMP - Compare Two Operands
/// Refer to `GenericArithmeticInstruction` for usage
pub inline fn CMP(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32) usize {
    return GenericArithmeticInstruction(write_at, dst, v1, src, v2, 0x38, 7);
}

test "CMP" {
    try GenericArithmeticInstructionTest("CMP", &CMP, &[_]GenericArithmeticInstructionTestCase{
        // zig fmt: off
        // migration
        .{ .esi, 0x08, .imm, 0x1F5, &[7]u8{ 0x81, 0x7E, 0x08, 0xF5, 0x01, 0x00, 0x00 } },
        .{ .eax, null, .imm, 0x134, &[5]u8{ 0x3D, 0x34, 0x01, 0x00, 0x00 } },
        .{  .cx, null, .imm,  0x01, &[4]u8{ 0x66, 0x83, 0xF9, 0x01 } },
        .{  .cx, null, .imm,  0x05, &[4]u8{ 0x66, 0x83, 0xF9, 0x05 } },
        .{  .cx, null,  .di,  null, &[3]u8{ 0x66, 0x39, 0xF9 } }, 
        // FIXME: this is also valid, however the generator can't tell that you
        // intend for an RM output instead of an MR output, because the shape
        // of the parameters is the same between RM/MR when no deref; expected
        // output here is RM, codegen gives us MR (as above)
        //.{  .cx, null,  .di,  null, &[3]u8{ 0x66, 0x3B, 0xCF } }, 
        // zig fmt: on
    });
}

// -----------
// conditional
// -----------

// WARN: could underflow, but not likely for our use case i guess
inline fn calcRelativeOffset(write_at: usize, target: usize) i32 {
    return @as(i32, @bitCast(target -% write_at));
}

const Condition = enum(u4) { o, no, b, nb, e, ne, be, a, s, ns, pe, po, l, ge, le, g };

// NOTE: cc instructions: CMOVcc, FCMOVcc, Jcc, LOOPcc, SETcc
inline fn ConditionalInstructionBase(write_at: usize, cond:Condition, B_TWOBYTE: bool, I_BASE: u8) usize {
    var addr = write_at;
    addr = if (B_TWOBYTE) mem.write(addr, u8, 0x0F) else addr;
    addr = mem.write(addr, u8, I_BASE + @intFromEnum(cond));
    return addr;
}

// NOTE: alt. mnemonic template
// pub const xC = xB;
// pub const xNAE = xB;
// pub const xAE = xNB;
// pub const xNC = xNB;
// pub const xZ = xE;
// pub const xNZ = xNE;
// pub const xNA = xBE;
// pub const xNBE = xA;
// pub const xP = xPE;
// pub const xNP = xPO;
// pub const xNGE = xL;
// pub const xNL = xGE;
// pub const xNG = xLE;
// pub const xNLE = xG;

inline fn Jcc(write_at: usize, jump_to: u32, cond: Condition) usize {
    var offset: i32 = calcRelativeOffset(write_at, jump_to);
    // -2 forces size 4 if offset==-127 (adjustment is 2 bytes if short jump); forces size 1 if +129
    const offset_w: u8 = parseOperandSize(offset - 2, false);
    const b_twobyte = offset_w > 1;
    const base: u8 = if (b_twobyte) 0x80 else 0x70;

    var addr = write_at;
    addr = ConditionalInstructionBase(addr, cond, b_twobyte, base);
    offset -= if (b_twobyte) 6 else 2; // offset is from EIP, so we adjust it
    addr = mem.write_bytes(addr, @as([*]const u8, @ptrCast(&offset))[0..offset_w]);
    return addr;
}

// TODO: test calcRelativeOffset and ConditionalInstructionBase separately instead 
// of indirectly here
test "Jcc" {
    var buf_o: [6]u8 = undefined;
    const addr_o: usize = @intFromPtr(&buf_o[0]);
    const addr_min_o: usize = addr_o - 126;
    const addr_max_o: usize = addr_o + 129;
    const sl_2_o = buf_o[0..2];
    const sl_6_o = buf_o[0..6];

    // behaviour (offsets)
    _ = Jcc(addr_o, addr_max_o, .e); // jcc short positive
    try std.testing.expectEqualSlices(u8, &[2]u8{0x74, 0x7F}, sl_2_o);
    _ = Jcc(addr_o, addr_min_o, .e); // jcc short negative
    try std.testing.expectEqualSlices(u8, &[2]u8{0x74, 0x80}, sl_2_o);
    _ = Jcc(addr_o, addr_max_o + 1, .e); // jcc positive
    try std.testing.expectEqualSlices(u8, &[6]u8{0x0F, 0x84, 0x7C, 0x00, 0x00, 0x00}, sl_6_o);
    _ = Jcc(addr_o, addr_min_o - 1, .e); // jcc negative
    try std.testing.expectEqualSlices(u8, &[6]u8{0x0F, 0x84, 0x7B, 0xFF, 0xFF, 0xFF}, sl_6_o);
    // behaviour (bases)
    _ = JO(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x70, 0x7F}, sl_2_o);
    _ = JNO(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x71, 0x7F}, sl_2_o);
    _ = JB(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x72, 0x7F}, sl_2_o);
    _ = JNB(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x73, 0x7F}, sl_2_o);
    _ = JE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x74, 0x7F}, sl_2_o);
    _ = JNE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x75, 0x7F}, sl_2_o);
    _ = JBE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x76, 0x7F}, sl_2_o);
    _ = JA(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x77, 0x7F}, sl_2_o);
    _ = JS(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x78, 0x7F}, sl_2_o);
    _ = JNS(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x79, 0x7F}, sl_2_o);
    _ = JPE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7A, 0x7F}, sl_2_o);
    _ = JPO(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7B, 0x7F}, sl_2_o);
    _ = JL(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7C, 0x7F}, sl_2_o);
    _ = JGE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7D, 0x7F}, sl_2_o);
    _ = JLE(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7E, 0x7F}, sl_2_o);
    _ = JG(addr_o, addr_max_o);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x7F, 0x7F}, sl_2_o);
}

pub const JC = JB;
pub const JNAE = JB;
pub const JAE = JNB;
pub const JNC = JNB;
pub const JZ = JE;
pub const JNZ = JNE;
pub const JNA = JBE;
pub const JNBE = JA;
pub const JP = JPE;
pub const JNP = JPO;
pub const JNGE = JL;
pub const JNL = JGE;
pub const JNG = JLE;
pub const JNLE = JG;

pub fn JO(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .o);
}

pub fn JNO(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .no);
}

pub fn JB(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .b);
}

pub fn JNB(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .nb);
}

pub fn JE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .e);
}

pub fn JNE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .ne);
}

pub fn JBE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .be);
}

pub fn JA(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .a);
}

pub fn JS(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .s);
}

pub fn JNS(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .ns);
}

pub fn JPE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .pe);
}

pub fn JPO(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .po);
}

pub fn JL(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .l);
}

pub fn JGE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .ge);
}

pub fn JLE(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .le);
}

pub fn JG(write_at: usize, jump_to: usize) usize {
    return Jcc(write_at, jump_to, .g);
}

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

// stuff

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

/// mov r32(@dst), r/m32(@src)
/// mov reg, reg
pub fn mov_r32_rm32(write_at: usize, comptime dst: GenReg32, comptime src: GenReg32) usize {
    return op_modRM(write_at, 0x8B, .reg, dst, src);
}

// TODO: handle mod 00 + r/m ebp case, where addressing becomes eip-relative and
// a 4-byte displacement value is used (normally 0 bytes for mod 00)
/// mov r32, r/m32 (with offset)
/// mov reg, [reg + offset]
pub fn mov_r32_rm32o(
    write_at: usize,
    comptime dst: GenReg32,
    comptime src: GenReg32,
    comptime T: type,
    disp: T,
) usize {
    if (src == .esp) @compileError("use mov_r32_rm32so for esp src (uses SIB)");
    const ea = comptime parseEffAddFromDispType(T);
    var addr = write_at;
    addr = op_modRM(addr, 0x8B, ea, dst, src);
    addr = mem.write(addr, T, disp);
    return addr;
}

test "mov_r32_rm32o" {
    const test_cases = [_]struct { GenReg32, GenReg32, type, i32, []const u8 }{
        .{ .ebp, .ebp, i8, 4, &[_]u8{ 0x8B, 0x6D, 0x04 } },
        .{ .esp, .eax, i32, 400, &[_]u8{ 0x8B, 0xA0, 0x90, 0x01, 0x00, 0x00 } },
        .{ .ebx, .ecx, i32, 400000, &[_]u8{ 0x8B, 0x99, 0x80, 0x1A, 0x06, 0x00 } },
        .{ .ecx, .esi, i32, 0x2D8, &[_]u8{ 0x8B, 0x8E, 0xD8, 0x02, 0x00, 0x00 } },
        .{ .ecx, .esi, i8, 0x0F, &[_]u8{ 0x8B, 0x4E, 0x0F } },
    };

    var output: [8]u8 = undefined;
    errdefer std.debug.print("\n", .{});
    inline for (test_cases, 0..) |t, i| {
        const expected = t[4];
        const output_s = output[0..expected.len];
        errdefer std.debug.print("FAILED {d:0>2} :: i: mov {s}, [{s} + {d}]  o: {s}  e: {s}\n", .{
            i, @tagName(t[0]), @tagName(t[1]), t[3], fmtSliceHexUpper(output_s), fmtSliceHexUpper(expected),
        });
        _ = mov_r32_rm32o(@intFromPtr(&output), t[0], t[1], t[2], t[3]);
        try std.testing.expectEqualSlices(u8, expected, output_s);
    }
}

// FIXME: remove once `mov_r32_rm32o` fixed
// NOTE: normally, MOD 00 means the displacement is 0 bytes; when R/M part is
// ebp (101), addressing becomes EIP-relative with 4-byte displacement value
// WARN: depends on incomplete behaviour of `mov_r32_rm32o` (see test)
/// mov @dst, [disp]
pub fn mov_r32_disp(write_at: usize, comptime dst: GenReg32, disp: i32) usize {
    var addr = write_at;
    addr = mov_r32_rm32o(addr, dst, .ebp, i0, 0);
    addr = mem.write(addr, i32, disp);
    return addr;
}

// should fail once `mov_r32_rm32o` behaviour fixed
test "mov_r32_disp" {
    var output: [6]u8 = undefined;
    const expected: []const u8 = &[_]u8{ 0x8B, 0x15, 0xDD, 0xCC, 0xBB, 0xAA };
    _ = mov_r32_disp(@intFromPtr(&output), .edx, @bitCast(@as(u32, 0xAABBCCDD)));
    try std.testing.expectEqualSlices(u8, expected, &output);
}

// FIXME: match structure with non-so version, this one is lagging behind
// TODO: figure out how to represent SIB; so far, value seems to be determined
// by the CPU state, so it seems like you can't just generate it without the
// user basically specifying the whole thing manually?
// SIB
// - output = [[BASE] + [INDEX]*SCALAR + DISP]
// - if BASE==ebp and MOD==00, DISP byte size is 4, else MOD determines size
//      00->0,  01->1,  10->4
// - if BASE==ebp and MOD==00, BASE part is removed (becomes 0)
// - if INDEX==esp, SCALAR is 0 (index removed), else [INDEX]*scalar
/// mov r32, r/m32 (with offset)
/// mov reg, [esp + offset]
/// version for ESP with SIB-related options
pub fn mov_r32_rm32so(
    write_at: usize,
    comptime dst: GenReg32,
    comptime src: GenReg32,
    disp: i32,
) usize {
    assert(false); // implementation not complete
    if (src != .esp) @compileError("use mov_r32_rm32o for non-esp src");
    const disp_bytes: u3 = @intCast((32 - @clz(disp) + 7) % 8);
    const ea = parseEffAddFromDispSize(disp_bytes);
    var addr = write_at;
    addr = op_modRM(addr, 0x8B, ea, dst, src);
    addr = mem.write(addr, u8, 0x00); // TODO: SIB generation
    addr = switch (ea) {
        .mem8 => mem.write(addr, i8, @intCast(disp)),
        .mem32 => mem.write(addr, i32, @intCast(disp)),
        else => null,
    };
    return addr;
}

// FIXME: impl alongside function
//test "mov_r32_rm32so" {
//    const test_cases = [_]struct { GenReg32, GenReg32, type, i32, []const u8 }{
//        .{ .ebx, .esp, i32, 400000, &[_]u8{ 0x8B, 0x9C, 0x24, 0x80, 0x1A, 0x06, 0x00 } },
//        .{ .ebx, .ecx, i32, 0x400000, &[_]u8{ 0x8B, 0x99, 0x00, 0x00, 0x00, 0x40, 0x00 } },
//    };
//
//    var output: [8]u8 = undefined;
//    errdefer std.debug.print("\n", .{});
//    inline for (test_cases, 0..) |t, i| {
//        const expected = t[4];
//        const output_s = output[0..expected.len];
//        errdefer std.debug.print("FAILED {d:0>2} :: i: mov {s}, [{s} + {d}]  o: {s}  e: {s}\n", .{
//            i, @tagName(t[0]), @tagName(t[1]), t[3], fmtSliceHexUpper(output_s), fmtSliceHexUpper(expected),
//        });
//        _ = mov_r32_rm32so(@intFromPtr(&output), t[0], t[1], t[2], t[3]);
//        try std.testing.expectEqualSlices(u8, expected, output_s);
//    }
//}

// FIXME: this does part of the (planned) functionality of `mov_r32_rm32so`, should
// remove once that's sorted
/// mov r32, [esp+<delta>]
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
            .fs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA0 }),
            .gs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA8 }),
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
            .fs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA1 }),
            .gs => mem.write_bytes(write_at, &[2]u8{ 0x0F, 0xA9 }),
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
        addr = ADD(addr, .esp, null, .imm, @intCast(4 * args.len));
    
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
