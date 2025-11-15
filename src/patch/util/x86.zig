pub const Self = @This();

const std = @import("std");
const mem = @import("memory.zig");
const assert = std.debug.assert;
const bytesToHex = std.fmt.bytesToHex;
const fmtSliceHexUpper = std.fmt.fmtSliceHexUpper;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;

// NOTE: supporting x86 only, not x86_64
// NOTE: instructions roughly organized according to pnx.tf reference
// NOTE: run tests in x86-windows mode
//  `zig test src/patch/util/x86.zig -target x86-windows -freference-trace`

// TODO: some kind of documentation at the top summarizing the overall themes
//  with the api design
// TODO: change all usize to u32; ensures correct size of address-related params
//  when not compiling for x86 target
// TODO: remove windows requirement; not urgent, not using this outside of
//  windows for now anyway
// FIXME: cut down on comptime requirements as much as possible (to reduce
//  function coloring)
// FIXME: some of the tests are getting stupid/redundant af, maybe add some
//  integration/end-to-end style testing to cover it more concisely? or generally
//  rethink where test content goes so that there isn't so much implicit redundancy
// see: BSWAP, Jcc, etc.
// FIXME: values are "type-less" because two's complement makes signed/unsigned
//  the same at bit-level; what convention should be used to allow user to use
//  both iN/uN types? or is it ok to just let them spam `@bitCast`?
// for now, defaulting to signed types because pointer offsets are signed

// references
// https://wiki.osdev.org/X86-64_Instruction_Encoding
// https://sandpile.org/x86/opc_rm.htm
// https://sandpile.org/x86/opc_enc.htm
// https://www.c-jump.com/CIS77/CPU/x86/lecture.html
// https://www.c-jump.com/CIS77/reference/Instructions_by_Opcode.html
// http://ref.x86asm.net/coder32.html
// https://pnx.tf/files/x86_opcode_structure_and_instruction_overview.pdf
// https://shell-storm.org/online/Online-Assembler-and-Disassembler/
// https://disasm.pro/
// https://godbolt.org/

// --------------------------------------
// instruction encoding & metaprogramming
// --------------------------------------

// FIXME: move to top, just here for proximity during initial experimentation
// FIXME: impl 16bit addressing mapping for MODRM
// NOTE: 16bit addressing uses a different register mapping for MODRM.rm field
// see https://wiki.osdev.org/X86-64_Instruction_Encoding#16-bit_addressing
// also yes, this means GenericArithmeticInstruction produces incorrect output
//  currently for 16bit registers (sort of - currently it doesn't attempt to
//  enforce address size at all, and therefore never emits an instruction with
//  invalid 16bit addressing; if it emitted a 0x67 prefix when given a 16bit
//  register, like NASM, then they would be invalid)
// example correct output of 16bit dst == 16bit addressing:
//  ->  add dword ptr [bx+0x11], 0x22
//  ->  add(<addr>, .bx, 0x11, .imm, 0x22)
//  ->  67 83 47 11 22  // 47 in 16bit mode, 43 otherwise (e.g. for ebx)
// note that none of the migration cases are affected by this either way,
//  so it should be safe to change the output of the relevant cases
// NOTE: 16-bit addressing doesn't use the SIB byte. instead, SIB-like behaviour
//  is implicit based on MODRM.rm value in indirect modes. the main implications
//  of this are that not all registers can be displaced or indexed (the SIB-like
//  stuff replaces some of the slots, but not all), and that there is no way to
//  configure the SIB, meaning no scaling factor.
// TODO: look into implementing operator encodings (RM, MI, II, ZO, etc.) as a
// way to simplify the logic
/// helper struct for simplifying codegen in instruction mnemonic implementations
/// and reducing code bloat.
/// some notes/goals of the api:
/// - dst and src registers must be of equivalent width, if not using immediate value
/// - operand size inferred from displacement type, or dst type when displacement is null
///   -> equivalent to <SIZE> part of:  <INST> <SIZE> ptr [<REG>+N], M
///   -> equivalent to <REG> part of:   <INST> <REG>, N
///   -> operand size override depends on: disp_t==i16 OR disp_t==null and dst_t==r16
/// - address size inferred from displacement size, or 0 when displacement is null
///   -> equivalent to <REG> part of:  <INST> <SIZE> ptr [<REG>+N], M
///   -> address size override depends on: dst_t==r16 AND presence of displacement
/// - 16bit addressing mode (presence of address size override byte, according to
///   above conditions) changes MODRM mapping.
///   see: https://wiki.osdev.org/X86-64_Instruction_Encoding#16-bit_addressing
/// - truncation of displacement/immediate values according to width of target
///   register (inferred address size, as explained above)
pub fn Instruction(comptime TD: type) type {
    const DisplacementT = if (TD == @TypeOf(null)) i32 else TD; // FIXME: should we actually default to i32?
    assert(std.meta.trait.isSignedInt(DisplacementT));
    assert(std.math.isPowerOfTwo(@bitSizeOf(DisplacementT)));
    assert(@bitSizeOf(DisplacementT) >= 8);
    assert(@bitSizeOf(DisplacementT) <= 32);

    return struct {
        const Inst = @This();
        const BehaviorPrefix = enum(u8) { LOCK = 0xF0, REPN = 0xF2, REP = 0xF3, _ };
        const SegmentPrefix = enum(u8) { CS = 0x2E, SS = 0x36, DS = 0x3E, ES = 0x26, FS = 0x64, GS = 0x65, _ };
        const RegOperandMode = enum(u2) { none, op, mod };
        const b16BitDisp: bool = @bitSizeOf(DisplacementT) == 16;

        BehaviorPf: ?BehaviorPrefix = null,
        SegmentPf: ?SegmentPrefix = null,
        bForceAddressPf: bool = false,
        bForceOperandPf: bool = false,

        Opcode: u8,
        OpcodeExtension: ?u3 = null, // override for MODRM.Reg
        bTwoByteOpcode: bool = false,

        TargetReg: ?GenReg = null, // MODRM.RM if mode==.mod
        TargetMode: RegOperandMode = .none,

        SourceReg: ?GenReg = null, // MODRM.Reg

        ForceMod: ?Addressing = null, // override for MODRM.Mod
        //SIB: SIB,

        Displacement: ?i32 = null,
        DispScale: u8 = 1,
        DispIndex: ?GenReg = null,
        // DispBase = SourceReg when using SIB

        Immediate: ?i32 = null,

        fn OperandSize(n: i32, max: u4, use_16bit: bool) u8 {
            var s: u8 = s: {
                if (n >= minInt(i8) and n <= maxInt(i8)) break :s 1;
                if (n >= minInt(i16) and n <= maxInt(i16) and use_16bit) break :s 2;
                break :s 4;
            };
            return @min(max, s);
        }

        // TODO: more closely follow NASM size parsing
        // operand size: width implied by MODRM.reg (in register mode, not opcode
        //  ext) and MODRM.rm fields; use width if same, error if mismatch.
        // address size: selected by priority - MODRM.rm field (in memory mode)
        //  -> SIB.base -> SIB.index -> displacement size. if the displacement
        //  is larger than the selected address size, it gets truncated
        // currently things were not necessarily organized with this in mind, but
        //  should be in line with this with the caveat that SIB is generally not
        //  implemented yet and the logic will break once it is
        // key realization is that "operand size" refers to operands that are NOT
        //  "operator-encoded" but are values meant to be written into registers,
        //  i.e. immediate values; this is why there is no further logic for op
        //  size than making sure the registers are in agreement
        // also, i think "MODRM.rm in memory mode" basically refers to indirect
        //  addressing, i.e. the mod bits NOT being 0b11
        // note that for [base+index*scale+disp] syntax, NASM does not allow opsize
        //  override ("WORD" etc.); i.e. "SIB behaviour" should ignore displacement
        //  input type and only use sizes implied by field-defined registers
        // FIXME: add assertions that guarantee values won't be null in the wrong places
        pub fn Emit(self: *const Inst, write_at: usize) usize {
            var addr = write_at;
            assert(self.TargetReg == null or self.TargetReg.? != .imm);
            assert(self.TargetReg != null or self.SourceReg != null);
            assert(self.Displacement == null or self.TargetReg != null); // disp needs reg
            assert(std.math.isPowerOfTwo(self.DispScale)); // implicit disp scale > 0
            assert(self.DispScale <= 8);
            assert(self.DispIndex == null or self.Displacement != null); // dispindex needs disp
            assert(self.DispIndex == null or self.DispIndex.?.RegTypeIndex() & 1 == 0); // dispindex r8 or r32
            defer assert(addr - write_at <= 15); // max x86 instruction size

            // FIXME: assuming TargetMode == .mod for now; logic will be different for others
            const dst_t = self.TargetReg.?.RegType();
            const dst_ti = self.TargetReg.?.RegTypeIndex();

            const reg_sz: u4 = if (self.TargetReg) |_| @as(u4, 1) << dst_ti else 0;
            const b_16bit = (dst_t == .r16);

            const dsp_sz: ?u8 = if (self.Displacement) |d| OperandSize(d, reg_sz, b_16bit) else null;
            const imm_sz: ?u8 = if (self.Immediate) |i| OperandSize(i, reg_sz, b_16bit) else null;
            const dsp_sl = @as([*]const u8, @ptrCast(&self.Displacement))[0 .. dsp_sz orelse 0];
            const imm_sl = @as([*]const u8, @ptrCast(&self.Immediate))[0 .. imm_sz orelse 0];

            const b_mod = (self.Displacement != null or self.OpcodeExtension != null);
            const b_16bit_addr = (b_16bit and self.Displacement != null);
            const b_16bit_open = (b_16bit and self.Displacement == null) or b16BitDisp;

            // TODO: cleanup/actually implement something non-adhoc
            const mod_rm_byte: ?MODRM = if (b_mod) modrm: {
                const mod = self.ForceMod orelse Addressing.FromLength(dsp_sz);
                const reg: GenReg = if (self.OpcodeExtension) |ext| @enumFromInt(ext) else self.TargetReg.?;
                const rm: GenReg = if (self.OpcodeExtension) |_| self.TargetReg.? else self.SourceReg.?;
                break :modrm MODRM.Make(mod, reg, rm);
            } else null;

            // prefixes
            // WARN: apparently the prefix order doesn't matter, but if it crashes try swapping these
            addr = if (self.BehaviorPf) |b| mem.write(addr, u8, @intFromEnum(b)) else addr;
            addr = if (self.SegmentPf) |s| mem.write(addr, u8, @intFromEnum(s)) else addr;
            addr = if (self.bForceAddressPf or b_16bit_addr) OverrideAddressSizePf(addr) else addr;
            addr = if (self.bForceOperandPf or b_16bit_open) OverrideOperandSizePf(addr) else addr;

            addr = EmitOpcode(addr, self.Opcode, self.bTwoByteOpcode);

            addr = if (mod_rm_byte) |mod| mem.write(addr, u8, @as(u8, @bitCast(mod))) else addr;
            // TODO: sib

            addr = mem.write_bytes(addr, dsp_sl);
            addr = mem.write_bytes(addr, imm_sl);

            return addr;
        }
    };
}

/// helper to write simple opcode with optional two-byte prefix
pub inline fn EmitOpcode(write_at: usize, opcode: u8, b_two_byte: bool) usize {
    var addr = if (b_two_byte) mem.write(write_at, u8, 0x0F) else write_at;
    return mem.write(addr, u8, opcode);
}

pub inline fn EncodeRegisterOp(base: u8, reg: GenReg) u8 {
    assert(base & 0b111 == 0);
    return base | reg.RegIndex();
}

const SegReg = enum { cs, ss, ds, es, fs, gs }; // segment register
const OpEn = enum { mem, reg, imm, zo }; // operator encoding
const EffAdd = enum(u2) { mem, mem8, mem32, reg }; // effective address

// general registers
// FIXME: probably remove these 3
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

pub const MODRM = packed struct(u8) {
    rm: u3,
    reg: u3,
    mod: u2,

    pub fn Make(mod: Addressing, reg: GenReg, rm: GenReg) MODRM {
        return MODRM{ .mod = @intFromEnum(mod), .reg = reg.RegIndex(), .rm = rm.RegIndex() };
    }
};

const SIB = packed struct(u8) {
    s: u2, // scale (1<<s)
    i: u3, // index register
    b: u3, // base register
};

// instruction helpers
// FIXME: can probably remove a lot of this once Instruction gets more fleshed out

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

// FIXME: remove, replace usage with OverrideOperandSizePf + EncodeRegisterOp
pub inline fn op_r16(
    write_at: usize,
    comptime base: u8,
    reg: GenReg16,
) usize {
    return mem.write_bytes(write_at, &[2]u8{ 0x66, base + @intFromEnum(reg) });
}

// FIXME: remove, replace usage with EncodeRegisterOp
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

// ------------------
// arithmetic & logic
// ------------------

fn parseAddSubOperandSize(n: i32, base: u8, dst: GenReg, b_ptr: bool, b_use_16bit: bool) u8 {
    const op_size = parseOperandSize(n, b_use_16bit);
    if (b_ptr or (base == 0x83 and op_size == 1)) return op_size;
    return @as(u8, 1) << dst.RegTypeIndex();
}

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
fn GenericArithmeticInstruction(write_at: usize, dst: GenReg, v1: ?i32, src: GenReg, v2: ?i32, comptime V_BASE: u8, comptime V_EXT: u3) usize {
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

    const mod_rm: ?MODRM = if (base & 0b100 == 0) mod_rm: {
        var mod: MODRM = undefined;
        if (b_r_rm) mod = MODRM.Make(Addressing.FromLength(if (v2) |_| v2_s else null), dst, src);
        if (!b_r_rm) mod = MODRM.Make(Addressing.FromLength(if (v1) |_| v1_s else null), src, dst);
        if (b_mod_ext) mod.reg = V_EXT;
        break :mod_rm mod;
    } else null;

    var addr = write_at;
    addr = if (b_16bit) OverrideOperandSizePf(addr) else addr;
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

// FIXME: add more thorough tests
/// SAL/SAR/SHL/SHR — Shift
fn ShiftArithmeticInstruction(write_at: usize, dst: GenReg, v1: anytype, src: GenReg, v2: ?u8, comptime V_EXT: u3) usize {
    assert(dst != .imm);
    assert(src == .imm or src == .cl);
    assert((src == .imm) != (v2 == null));
    const dst_t = dst.RegType();
    const b_8bit = (dst_t == .r8);
    const b_1 = (src == .imm and v2.? == 1);

    var instruction = Instruction(@TypeOf(v1)){
        .Opcode = 0xC0,
        .OpcodeExtension = V_EXT,
        .TargetReg = dst,
        .SourceReg = src,
        .Displacement = v1,
        .Immediate = if (v2) |v| @intCast(v) else null,
    };

    if (b_1) {
        instruction.Opcode |= 0b00010000;
        instruction.Displacement = null;
        instruction.Immediate = null;
        instruction.ForceMod = .disp0;
    }
    if (!b_8bit)
        instruction.Opcode |= 0b00000001;
    if (src == .cl)
        instruction.Opcode |= 0b00010010;

    return instruction.Emit(write_at);
}

const ShiftArithmeticInstructionTestCase = struct { 
    GenReg, 
    union(enum) { b:i8, w:i16, d:i32, n:@TypeOf(null) }, 
    GenReg, 
    ?u8, 
    []const u8,
};

fn ShiftArithmeticInstructionTest(
    comptime label: []const u8,
    comptime test_fn: *const fn (usize, GenReg, anytype, GenReg, ?u8) callconv(.Inline) usize,
    comptime test_cases: []const ShiftArithmeticInstructionTestCase,
) !void {
    var output: [12]u8 = undefined;
    const output_a = @intFromPtr(&output);
    inline for (test_cases, 0..) |t, i| {
        const v1 = switch (t[1]) { .b => t[1].b, .w => t[1].w, .d => t[1].d, .n => t[1].n };
        errdefer std.debug.print("FAILED {d:0>2} :: {s}(<addr>, .{s}, {any}, .{s}, {?d})\n\n", .{
            i, label, @tagName(t[0]), v1, @tagName(t[2]), t[3],
        });
        const expected = t[4];
        const output_len = test_fn(@intFromPtr(&output), t[0], v1, t[2], t[3]) - output_a;
        const output_s = output[0..output_len];
        try std.testing.expectEqualSlices(u8, expected, output_s);
        try std.testing.expectEqual(expected.len, output_len);
    }
}

pub const SHL = SAL;
pub inline fn SAL(write_at: usize, dst: GenReg, v1: anytype, src: GenReg, v2: ?u8) usize {
    return ShiftArithmeticInstruction(write_at, dst, v1, src, v2, 4);
}

test "SHL/SAL" {
    try ShiftArithmeticInstructionTest("SHL", &SHL, &[_]ShiftArithmeticInstructionTestCase{
        // zig fmt: off
        // standard tests
        .{  .al, .{ .d=0x10 }, .imm, 10, &[4]u8{ 0xC0, 0x60, 0x10, 0x0A } },
        .{ .ebx, .{ .d=0x10 }, .imm,  2, &[4]u8{ 0xC1, 0x63, 0x10, 0x02 } },
      // FIXME: needs 16bit addressing mode for MODRM
      //.{  .bx, .{ .w=0x10 }, .imm,  2, &[6]u8{ 0x67, 0x66, 0xC1, 0x67, 0x10, 0x02 } },
        .{  .bl, .{ .d=0x10 }, .imm,  2, &[4]u8{ 0xC0, 0x63, 0x10, 0x02 } },
        .{  .bh, .{ .d=0x10 }, .imm,  2, &[4]u8{ 0xC0, 0x67, 0x10, 0x02 } },
        .{  .bx, .{ .n=null }, .imm,  2, &[4]u8{ 0x66, 0xC1, 0xE3, 0x02 } },
        .{  .bx, .{ .n=null }, .cl, null, &[3]u8{ 0x66, 0xD3, 0xE3 } },
        // zig fmt: on
    });
}

pub inline fn SAR(write_at: usize, dst: GenReg, v1: anytype, src: GenReg, v2: ?u8) usize {
    return ShiftArithmeticInstruction(write_at, dst, v1, src, v2, 7);
}

pub inline fn SHR(write_at: usize, dst: GenReg, v1: anytype, src: GenReg, v2: ?u8) usize {
    return ShiftArithmeticInstruction(write_at, dst, v1, src, v2, 5);
}

test "SHR" {
    try ShiftArithmeticInstructionTest("SHR", &SHR, &[_]ShiftArithmeticInstructionTestCase{
        // zig fmt: off
        // migration
        .{ .eax, .{ .w=0x00 }, .imm, 0x01, &[3]u8{ 0x66, 0xD1, 0x28 } },             // shr WORD [eax+0x0], 1
        .{ .eax, .{ .w=0x02 }, .imm, 0x02, &[5]u8{ 0x66, 0xC1, 0x68, 0x02, 0x02 } }, // shr WORD [eax+0x2], 2
        .{ .eax, .{ .w=0x0E }, .imm, 0x02, &[5]u8{ 0x66, 0xC1, 0x68, 0x0E, 0x02 } }, // shr WORD [eax+0xE], 2
        .{ .edx, .{ .w=0x00 }, .imm, 0x01, &[3]u8{ 0x66, 0xD1, 0x2A } },             // shr WORD [edx+0x0], 1
        .{ .edx, .{ .w=0x02 }, .imm, 0x02, &[5]u8{ 0x66, 0xC1, 0x6A, 0x02, 0x02 } }, // shr WORD [edx+0x2], 2
        // zig fmt: on
    });
}

/// AAA — ASCII Adjust After Addition
pub fn AAA(write_at: usize) usize {
    return mem.write(write_at, u8, 0x37);
}

/// AAS — ASCII Adjust AL After Subtraction
pub fn AAS(write_at: usize) usize {
    return mem.write(write_at, u8, 0x3F);
}

/// DAA — Decimal Adjust AL After Addition
pub fn DAA(write_at: usize) usize {
    return mem.write(write_at, u8, 0x27);
}

/// DAS — Decimal Adjust AL After Subtraction
pub fn DAS(write_at: usize) usize {
    return mem.write(write_at, u8, 0x2F);
}

// --------------------------
// control flow & conditional
// --------------------------

// WARN: could underflow, but not likely for our use case i guess
// NOTE: probably more useful on Instruction and paired with a "calcInstructionSize"
inline fn calcRelativeOffset(write_at: usize, target: usize) i32 {
    return @as(i32, @bitCast(target -% write_at));
}

const Condition = enum(u4) { o, no, b, nb, e, ne, be, a, s, ns, pe, po, l, ge, le, g };

// NOTE: cc instructions: CMOVcc, FCMOVcc, Jcc, LOOPcc, SETcc
inline fn ConditionalInstructionBase(write_at: usize, cond:Condition, B_TWOBYTE: bool, I_BASE: u8) usize {
    return EmitOpcode(write_at, I_BASE + @intFromEnum(cond), B_TWOBYTE);
}

// jumping

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

// FIXME: add support for 16bit operand size override; seems that operand is always 
//  32bit in bytes, but truncated by the cpu in presence of the override. actually 
//  not sure how useful this really is, but technically the impl is "wrong".
/// Jcc - Jump if Condition Is Met
/// Used via mnemonic-specific helpers JNZ, JE, etc.
fn JccInstruction(write_at: usize, jump_to: u32, cond: Condition) usize {
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
    _ = JccInstruction(addr_o, addr_max_o, .e); // jcc short positive
    try std.testing.expectEqualSlices(u8, &[2]u8{0x74, 0x7F}, sl_2_o);
    _ = JccInstruction(addr_o, addr_min_o, .e); // jcc short negative
    try std.testing.expectEqualSlices(u8, &[2]u8{0x74, 0x80}, sl_2_o);
    _ = JccInstruction(addr_o, addr_max_o + 1, .e); // jcc positive
    try std.testing.expectEqualSlices(u8, &[6]u8{0x0F, 0x84, 0x7C, 0x00, 0x00, 0x00}, sl_6_o);
    _ = JccInstruction(addr_o, addr_min_o - 1, .e); // jcc negative
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

pub inline fn JO(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .o);
}

pub inline fn JNO(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .no);
}

pub inline fn JB(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .b);
}

pub inline fn JNB(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .nb);
}

pub inline fn JE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .e);
}

pub inline fn JNE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .ne);
}

pub inline fn JBE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .be);
}

pub inline fn JA(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .a);
}

pub inline fn JS(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .s);
}

pub inline fn JNS(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .ns);
}

pub inline fn JPE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .pe);
}

pub inline fn JPO(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .po);
}

pub inline fn JL(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .l);
}

pub inline fn JGE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .ge);
}

pub inline fn JLE(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .le);
}

pub inline fn JG(write_at: usize, jump_to: usize) usize {
    return JccInstruction(write_at, jump_to, .g);
}

/// Jcc - Jump if Condition Is Met
/// Special case for JCXZ/JECXZ
fn JccCXInstruction(write_at: usize, jump_to: u32, reg: GenReg) usize {
    const b_16bit = reg == .cx;
    const inst_s: u8 = if (b_16bit) 3 else 2;
    var offset: i32 = calcRelativeOffset(write_at + inst_s, jump_to);
    const offset_w: u8 = parseOperandSize(offset, false);
    assert(reg == .cx or reg == .ecx);
    assert(offset_w == 1);

    var addr = write_at;
    addr = if (b_16bit) OverrideAddressSizePf(addr) else addr;
    addr = mem.write(addr, u8, 0xE3);
    addr = mem.write(addr, i8, @as(i8, @truncate(offset)));
    return addr;
}

test "Jcc CX" {
    var buf_o: [3]u8 = undefined;
    const addr_o: usize = @intFromPtr(&buf_o[0]);
    const addr_min_o: usize = addr_o - 126;
    const addr_max_o: usize = addr_o + 129;
    const sl_2_o = buf_o[0..2];
    const sl_3_o = buf_o[0..3];

    // behaviour (offsets)
    try std.testing.expectEqual(addr_o + 2, JccCXInstruction(addr_o, addr_max_o, .ecx));
    try std.testing.expectEqualSlices(u8, &[2]u8{0xE3, 0x7F}, sl_2_o);
    try std.testing.expectEqual(addr_o + 2, JccCXInstruction(addr_o, addr_min_o, .ecx));
    try std.testing.expectEqualSlices(u8, &[2]u8{0xE3, 0x80}, sl_2_o);
    // behaviour (bases)
    try std.testing.expectEqual(addr_o + 3, JCXZ(addr_o, addr_min_o + 1));
    try std.testing.expectEqualSlices(u8, &[3]u8{0x67, 0xE3, 0x80}, sl_3_o);
    try std.testing.expectEqual(addr_o + 2, JECXZ(addr_o, addr_min_o));
    try std.testing.expectEqualSlices(u8, &[2]u8{0xE3, 0x80}, sl_2_o);
}

pub inline fn JCXZ(write_at: usize, jump_to: usize) usize {
    return JccCXInstruction(write_at, jump_to, .cx);
}

pub inline fn JECXZ(write_at: usize, jump_to: usize) usize {
    return JccCXInstruction(write_at, jump_to, .ecx);
}

// FIXME: check if address size override prefix (0x67) required for 2-byte
// offset during r/m16
// TODO: generalized JMP; missing rm16/32 (FF /4), m16/32 (FF /5), ptr16/32
// TODO: rename to JMP when above done
/// JMP with D op/en only
pub fn jmp_rel(write_at: usize, jump_to: usize) usize {
    var offset: i32 = calcRelativeOffset(write_at, jump_to);
    const offset_w: u8 = o: {
        if (offset-2 >= minInt(i8) and offset-2 <= maxInt(i8)) break :o 1;
        if (offset-4 >= minInt(i16) and offset-4 <= maxInt(i16)) break :o 2;
        break :o 4;
    };
    const base: u8 = if (offset_w == 1) 0xEB else 0xE9;
    const b_16bit: bool = offset_w == 2;

    var addr = write_at;
    addr = if (b_16bit) OverrideOperandSizePf(addr) else addr;
    addr = mem.write(addr, u8, base);
    offset -= @bitCast(addr - write_at + offset_w); // offset is from EIP, so we adjust it
    addr = mem.write_bytes(addr, @as([*]const u8, @ptrCast(&offset))[0..offset_w]);
    return addr;
}

// TODO: more thorough testing
// TODO: impl generalized JMP tests once complete JMP implemented
test "JMP" {
    var buf_o: [6]u8 = undefined;
    const addr_o: usize = @intFromPtr(&buf_o[0]);
    const addr_min8_o: usize = addr_o - 128 + 2;
    const addr_max8_o: usize = addr_o + 127 + 2;
    const addr_min16_o: usize = addr_o - 32768 + 4;
    const addr_max16_o: usize = addr_o + 32767 + 4;
    const sl_2_o = buf_o[0..2];
    const sl_4_o = buf_o[0..4];
    const sl_5_o = buf_o[0..5];

    // behaviour (offsets)
    // jmp short pos
    try std.testing.expectEqual(addr_o+2, jmp_rel(addr_o, addr_max8_o));
    try std.testing.expectEqualSlices(u8, &[2]u8{0xEB, 0x7F}, sl_2_o);
    // jmp short neg
    try std.testing.expectEqual(addr_o+2, jmp_rel(addr_o, addr_min8_o));
    try std.testing.expectEqualSlices(u8, &[2]u8{0xEB, 0x80}, sl_2_o);
    // jmp near pos (16bit override)
    try std.testing.expectEqual(addr_o+4, jmp_rel(addr_o, addr_max8_o+1));
    try std.testing.expectEqualSlices(u8, &[4]u8{0x66, 0xE9, 0x7E, 0x00}, sl_4_o);
    // jmp near neg (16bit override)
    try std.testing.expectEqual(addr_o+4, jmp_rel(addr_o, addr_min8_o-1));
    try std.testing.expectEqualSlices(u8, &[4]u8{0x66, 0xE9, 0x7D, 0xFF}, sl_4_o);
    // jmp near pos (16bit override)
    try std.testing.expectEqual(addr_o+4, jmp_rel(addr_o, addr_max16_o));
    try std.testing.expectEqualSlices(u8, &[4]u8{0x66, 0xE9, 0xFF, 0x7F}, sl_4_o);
    // jmp near neg (16bit override)
    try std.testing.expectEqual(addr_o+4, jmp_rel(addr_o, addr_min16_o));
    try std.testing.expectEqualSlices(u8, &[4]u8{0x66, 0xE9, 0x00, 0x80}, sl_4_o);
    // jmp near pos
    try std.testing.expectEqual(addr_o+5, jmp_rel(addr_o, addr_max16_o+1));
    try std.testing.expectEqualSlices(u8, &[5]u8{0xE9, 0xFF, 0x7F, 0x00, 0x00}, sl_5_o);
    // jmp near neg
    try std.testing.expectEqual(addr_o+5, jmp_rel(addr_o, addr_min16_o-1));
    try std.testing.expectEqualSlices(u8, &[5]u8{0xE9, 0xFE, 0x7F, 0xFF, 0xFF}, sl_5_o);
}

// test

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

// call

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

// return

pub fn retn(write_at: usize) usize {
    return mem.write(write_at, u8, 0xC3);
}

pub fn retn_imm16(write_at: u32, bytes: u16) u32 {
    var addr = write_at;
    addr = mem.write(addr, u8, 0xC2);
    addr = mem.write(addr, u16, bytes);
    return addr;
}

/// IRET — Interrupt Return
pub inline fn IRET(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return IRETD(addr);
}

/// IRETD — Interrupt Return
pub inline fn IRETD(write_at: usize) usize {
    return mem.write(write_at, u8, 0xCF);
}

// clearing

/// CMC — Complement Carry Flag
pub fn CMC(write_at: usize) usize {
    return mem.write(write_at, u8, 0xF5);
}

/// CLC — Clear Carry Flag
pub fn CLC(write_at: usize) usize {
    return mem.write(write_at, u8, 0xF8);
}

/// STC — Set Carry Flag
pub fn STC(write_at: usize) usize {
    return mem.write(write_at, u8, 0xF9);
}

/// CLI — Clear Interrupt Flag
pub fn CLI(write_at: usize) usize {
    return mem.write(write_at, u8, 0xFA);
}

/// STI — Set Interrupt Flag
pub fn STI(write_at: usize) usize {
    return mem.write(write_at, u8, 0xFB);
}

/// CLD — Clear Direction Flag
pub fn CLD(write_at: usize) usize {
    return mem.write(write_at, u8, 0xFC);
}

/// STD — Set Direction Flag
pub fn STD(write_at: usize) usize {
    return mem.write(write_at, u8, 0xFD);
}

// -----
// stack
// -----

// TODO: ENTER — Make Stack Frame for Procedure Parameters
// TODO: LEAVE — High Level Procedure Exit
// TODO: rework push/pop for nicer api and adding missing options

pub const PushSrc = union(enum) { imm8: u8, imm16: u16, imm32: u32, seg: SegReg, r16: GenReg16, r32: GenReg32 };

// TODO: r/m16, r/m32 (FF /6)
/// PUSH — Push Word or Doubleword Onto the Stack
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
            .fs => EmitOpcode(write_at, 0xA0, true),
            .gs => EmitOpcode(write_at, 0xA8, true),
        },
    }
}

/// PUSHA/PUSHAD – Pop All General Registers
pub inline fn PUSHA(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return PUSHAD(addr);
}

/// PUSHA/PUSHAD – Pop All General Registers
pub inline fn PUSHAD(write_at: usize) usize {
    return mem.write(write_at, u8, 0x60);
}

/// PUSHF/PUSHFD – Pop Stack into FLAGS or EFLAGS Register
pub inline fn PUSHF(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return PUSHFD(addr);
}

/// PUSHF/PUSHFD – Pop Stack into FLAGS or EFLAGS Register
pub inline fn PUSHFD(write_at: usize) usize {
    return mem.write(write_at, u8, 0x9C);
}

pub const PopDest = union(enum) { seg: SegReg, r16: GenReg16, r32: GenReg32 };

// TODO: r/m16, r/m32 (8F /0)
/// POP — Pop a Value From the Stack
pub inline fn pop(write_at: usize, dest: PopDest) usize {
    switch (dest) {
        .r16 => |reg| return op_r16(write_at, 0x58, reg),
        .r32 => |reg| return op_r32(write_at, 0x58, reg),
        .seg => |seg| return switch (seg) {
            .ds => mem.write(write_at, u8, 0x1F),
            .es => mem.write(write_at, u8, 0x07),
            .ss => mem.write(write_at, u8, 0x17),
            .fs => EmitOpcode(write_at, 0xA1, true),
            .gs => EmitOpcode(write_at, 0xA9, true),
            else => @panic("pop(): invalid segment register"),
        },
    }
}

/// POPA/POPAD – Pop All General Registers
pub inline fn POPA(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return POPAD(addr);
}

/// POPA/POPAD – Pop All General Registers
pub inline fn POPAD(write_at: usize) usize {
    return mem.write(write_at, u8, 0x61);
}

/// POPF/POPFD – Pop Stack into FLAGS or EFLAGS Register
pub inline fn POPF(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return POPFD(addr);
}

/// POPF/POPFD – Pop Stack into FLAGS or EFLAGS Register
pub inline fn POPFD(write_at: usize) usize {
    return mem.write(write_at, u8, 0x9D);
}

// ------
// memory
// ------


/// SAHF — Store AH Into Flags
pub fn SAHF(write_at: usize) usize {
    return mem.write(write_at, u8, 0x9E);
}

/// LAHF — Load Status Flags Into AH Register
pub fn LAHF(write_at: usize) usize {
    return mem.write(write_at, u8, 0x9F);
}

/// CBW — Convert Byte to Word
pub inline fn CBW(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return CWDE(addr);
}

/// CWDE — Convert Word to Doubleword
pub inline fn CWDE(write_at: usize) usize {
    return mem.write(write_at, u8, 0x98);
}

/// CDQ — Convert Doubleword to Quadword
pub inline fn CDQ(write_at: usize) usize {
    var addr = OverrideOperandSizePf(write_at);
    return CWD(addr);
}

/// CWD — Convert Word to Doubleword
pub inline fn CWD(write_at: usize) usize {
    return mem.write(write_at, u8, 0x99);
}

// mov

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

/// BSWAP — Byte Swap
fn BSWAP(write_at: usize, reg: GenReg) usize {
    assert(reg.RegType() == .r32);
    const op = EncodeRegisterOp(0xC8, reg);
    return EmitOpcode(write_at, op, true);
}

test "BSWAP" {
    var buf_o: [2]u8 = undefined;
    const addr_o: usize = @intFromPtr(&buf_o);

    try std.testing.expectEqual(@intFromPtr(&buf_o) + 2, BSWAP(addr_o, .eax));
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xC8}, &buf_o);
    _ = BSWAP(addr_o, .ecx);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xC9}, &buf_o);
    _ = BSWAP(addr_o, .edx);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCA}, &buf_o);
    _ = BSWAP(addr_o, .ebx);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCB}, &buf_o);
    _ = BSWAP(addr_o, .esp);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCC}, &buf_o);
    _ = BSWAP(addr_o, .ebp);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCD}, &buf_o);
    _ = BSWAP(addr_o, .esi);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCE}, &buf_o);
    _ = BSWAP(addr_o, .edi);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x0F, 0xCF}, &buf_o);
}

// ------------
// system & i/o
// ------------

// TODO: INS/INSB/INSW/INSD — Input from Port to String
// TODO: OUTS/OUTSB/OUTSW/OUTSD — Output String to Port
// TODO: IN — Input From Port
// TODO: OUT — Output to Port
// TODO: ICEBP (undocumented)
// TODO: UD, UD2
// TODO: *FENCE
// TODO: {L,S}LDT etc., {L,S}GDT etc.

/// INT n/INTO/INT3/INT1 — Call to Interrupt Procedure
pub inline fn INT3(write_at: usize) usize {
    return mem.write(write_at, u8, 0xCC);
}

// TODO: INT n (CD ib)
/// INT n/INTO/INT3/INT1 — Call to Interrupt Procedure

/// INT n/INTO/INT3/INT1 — Call to Interrupt Procedure
pub inline fn INTO(write_at: usize) usize {
    return mem.write(write_at, u8, 0xCE);
}

/// INT n/INTO/INT3/INT1 — Call to Interrupt Procedure
pub inline fn INT1(write_at: usize) usize {
    return mem.write(write_at, u8, 0xF1);
}

/// HLT — Halt
pub inline fn HLT(write_at: usize) usize {
    return mem.write(write_at, u8, 0xF4);
}

pub const FWAIT = WAIT;
/// WAIT/FWAIT — Wait
pub inline fn WAIT(write_at: usize) usize {
    return mem.write(write_at, u8, 0x9B);
}

/// CLTS — Clear Task-Switched Flag in CR0
pub inline fn CLTS(write_at: usize) usize {
    return EmitOpcode(write_at, 0x06, true);
}

/// INVD — Invalidate Internal Caches
pub inline fn INVD(write_at: usize) usize {
    return EmitOpcode(write_at, 0x08, true);
}

/// WBINVD — Write Back and Invalidate Cache
pub inline fn WBINVD(write_at: usize) usize {
    return EmitOpcode(write_at, 0x09, true);
}

/// RDTSC – Read Time-Stamp Counter
pub inline fn RDTSC(write_at: usize) usize {
    return EmitOpcode(write_at, 0x31, true);
}

/// WRMSR — Write to Model Specific Register
pub inline fn WRMSR(write_at: usize) usize {
    return EmitOpcode(write_at, 0x30, true);
}

/// RDMSR — Read From Model Specific Register
pub inline fn RDMSR(write_at: usize) usize {
    return EmitOpcode(write_at, 0x32, true);
}

/// RDPMC – Read Performance Monitoring Counters
pub inline fn RDPMC(write_at: usize) usize {
    return EmitOpcode(write_at, 0x33, true);
}

/// SYSENTER — Fast System Call
pub inline fn SYSENTER(write_at: usize) usize {
    return EmitOpcode(write_at, 0x34, true);
}

/// SYSEXIT — Fast Return from Fast System Call
pub inline fn SYSEXIT(write_at: usize) usize {
    return EmitOpcode(write_at, 0x35, true);
}

/// CPUID — CPU Identification
pub inline fn CPUID(write_at: usize) usize {
    return EmitOpcode(write_at, 0xA2, true);
}

/// RSM — Resume From System Management Mode
pub inline fn RSM(write_at: usize) usize {
    return EmitOpcode(write_at, 0xAA, true);
}

// ------
// prefix
// ------

//pub inline fn LockPf(write_at: usize) usize {
//    return mem.write(write_at, u8, 0xF0);
//}

//pub inline fn RepnPf(write_at: usize) usize {
//    return mem.write(write_at, u8, 0xF2);
//}

//pub inline fn RepPf(write_at: usize) usize {
//    return mem.write(write_at, u8, 0xF3);
//}

//pub inline fn SegmentOverridePf(write_at: usize, comptime s: SegReg) usize {
//    return switch (s) {
//        .cs => mem.write(write_at, u8, 0x2E),
//        .ds => mem.write(write_at, u8, 0x3E),
//        .es => mem.write(write_at, u8, 0x26),
//        .fs => mem.write(write_at, u8, 0x64),
//        .gs => mem.write(write_at, u8, 0x65),
//        .ss => mem.write(write_at, u8, 0x36),
//    };
//}

pub inline fn OverrideOperandSizePf(write_at: usize) usize {
    return mem.write(write_at, u8, 0x66);
}

pub inline fn OverrideAddressSizePf(write_at: usize) usize {
    return mem.write(write_at, u8, 0x67);
}

// ----------------
// other/extensions
// ----------------

// no-op
// TODO: multi-byte nop flavors (e.g. 0xOF 0x1F)

pub fn nop(write_at: usize) usize {
    return mem.write(write_at, u8, 0x90);
}

pub fn nop_align(write_at: usize, alignment: usize) usize {
    assert(std.math.isPowerOfTwo(alignment));
    var addr: usize = write_at;
    while (addr % alignment > 0) {
        addr = nop(addr);
    }
    return addr;
}

pub fn nop_until(write_at: usize, end: usize) usize {
    assert(end >= write_at);
    var addr: usize = write_at;
    while (addr < end) {
        addr = nop(addr);
    }
    return addr;
}

test "NOP" {
    var buf_o: [4]u8 = undefined; // should be 4-byte aligned (stack-allocated)
    const addr_o: usize = @intFromPtr(&buf_o);

    try std.testing.expectEqual(addr_o + 1, nop(addr_o));
    try std.testing.expectEqual(@as(u8, 0x90), buf_o[0]);
    
    const sl_until = buf_o[0..3];
    try std.testing.expectEqual(addr_o + sl_until.len, nop_until(addr_o, addr_o + sl_until.len));
    try std.testing.expectEqualSlices(u8, &[_]u8{0x90,0x90,0x90}, sl_until);

    const alignment: usize = 4;
    const sl_align0 = buf_o[0..0]; 
    const sl_align1 = buf_o[1..alignment];
    try std.testing.expectEqual(addr_o + 0, nop_align(addr_o + 0, alignment));
    try std.testing.expectEqualSlices(u8, &[_]u8{}, sl_align0);
    try std.testing.expectEqual(addr_o + alignment, nop_align(addr_o + 1, alignment));
    try std.testing.expectEqualSlices(u8, &[_]u8{0x90,0x90,0x90}, sl_align1);
}

// --------------------
// non-specific helpers
// --------------------

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

// function calls
// https://en.wikibooks.org/wiki/X86_Disassembly/Calling_Conventions
// https://blog.aaronballman.com/2012/02/describing-the-msvc-abi-for-structure-return-types/

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

// detour

/// helper for managing a "jump-and-replace"-style detour
pub const Detour = struct {
    const AlignSize: u32 = 16;

    entry_addr: u32,
    return_addr: u32,
    buf: []u8,
    addr: u32,

    // TODO: optional nop_until
    // TODO: option to auto copy overwritten bytes to detour buffer
    pub fn Start(data: *Detour, write_at: u32, return_to: u32, buf: []u8) void {
        assert(buf.len % Detour.AlignSize == 0);
        assert(return_to > write_at);
        assert(return_to - write_at >= 5); // jmp long instruction size
        data.entry_addr = write_at;
        data.return_addr = return_to;
        data.buf = buf;
        data.addr = @intFromPtr(buf.ptr);
        var addr = write_at;
        addr = jmp_rel(write_at, data.addr);
        addr = nop_until(addr, return_to);
    }

    // between these two functions, write to buf the usual way using Detour.addr
    // example: my_detour.addr = jmp_rel(my_detour.addr, 0xDEADBEEF);

    // TODO: optional nop_align
    pub fn End(data: *Detour) void {
        data.addr = jmp_rel(data.addr, data.return_addr);
        data.addr = nop_align(data.addr, Detour.AlignSize);
        assert(data.addr - @intFromPtr(data.buf.ptr) <= data.buf.len);
    }

    pub fn UnusedSpace(data: *const Detour) u32 {
        return data.buf.len - (data.addr - @intFromPtr(data.buf.ptr));
    }
};

