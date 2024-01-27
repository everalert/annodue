const std = @import("std");
const user32 = std.os.windows.user32;

const testing = std.testing;
const print = std.debug.print;

const LoadLibraryW = std.os.windows.LoadLibraryW;
const VirtualProtect = std.os.windows.VirtualProtect;
const VirtualAlloc = std.os.windows.VirtualAlloc;
const GetProcAddress = std.os.windows.kernel32.GetProcAddress;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;
const WINAPI = std.os.windows.WINAPI;
const DWORD = std.os.windows.DWORD;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

fn write(offset: usize, comptime T: type, value: T) usize {
    const addr: [*]align(1) T = @ptrFromInt(offset);
    const data: [1]T = [1]T{value};
    var protect: DWORD = undefined;
    _ = VirtualProtect(addr, @sizeOf(T), PAGE_EXECUTE_READWRITE, &protect) catch unreachable;
    @memcpy(addr, &data);
    _ = VirtualProtect(addr, @sizeOf(T), protect, &protect) catch unreachable;
    return offset + @sizeOf(T);
}

fn read(offset: usize, comptime T: type) T {
    const addr: [*]align(1) T = @ptrFromInt(offset);
    var data: [1]T = undefined;
    @memcpy(&data, addr);
    return data[0];
}

fn patchAdd(offset: usize, comptime T: type, delta: T) usize {
    const value: T = read(offset, T);
    return write(offset, T, value + delta);
}

fn add_esp(memory_offset: usize, n: i32) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x81);
    offset = write(offset, u8, 0xC4);
    offset = write(offset, i32, n);
    //offset = write(offset, u32, @as(u32, @bitCast(n)));
    return offset;
}

fn test_eax_eax(memory_offset: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x85);
    offset = write(offset, u8, 0xC0);
    return offset;
}

fn test_edx_edx(memory_offset: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x85);
    offset = write(offset, u8, 0xD2);
    return offset;
}

fn nop(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x90);
}

fn push_eax(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x50);
}

fn push_edx(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x52);
}

fn pop_edx(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5A);
}

fn push_u32(memory_offset: usize, value: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x68);
    offset = write(offset, u32, value);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
fn call(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0xE8);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
fn jmp(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0xE9);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
fn jnz(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x0F);
    offset = write(offset, u8, 0x85);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

fn retn(memory_offset: usize) usize {
    return write(memory_offset, u8, 0xC3);
}

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

const patch_size: u32 = 4 * 1024 * 1024;

export fn PatchDeathSpeed(min: f32, drop: f32) void {
    //0x4C7BB8	4	DeathSpeedMin	float	325.0		SWEP1RCR.EXE+0x0C7BB8
    _ = write(0x4C7BB8, f32, min);
    //0x4C7BBC	4	DeathSpeedDrop	float	140.0		SWEP1RCR.EXE+0x0C7BBC
    _ = write(0x4C7BBC, f32, drop);
}

export fn PatchTriggerDisplay(memory_offset: usize) usize {
    var offset = memory_offset;

    // Display triggers
    const trigger_string = "Trigger %d activated";
    const trigger_string_display_duration: f32 = 3.0;

    var offset_trigger_string = offset;
    offset = write(offset, @TypeOf(trigger_string.*), trigger_string.*);

    var offset_trigger_code: u32 = offset;

    // Read the trigger from stack
    offset = write(offset, u8, 0x8B); // mov    eax, [esp+4]
    offset = write(offset, u8, 0x44);
    offset = write(offset, u8, 0x24);
    offset = write(offset, u8, 0x04);

    // Get pointer to section 8
    offset = write(offset, u8, 0x8B); // 8b 40 4c  ->  mov    eax,DWORD PTR [eax+0x4c]
    offset = write(offset, u8, 0x40);
    offset = write(offset, u8, 0x4C);

    // Read the section8.trigger_action field
    offset = write(offset, u8, 0x0F); // 0f b7 40 24  ->  movzx    eax, WORD PTR [eax+0x24]
    offset = write(offset, u8, 0xB7);
    offset = write(offset, u8, 0x40);
    offset = write(offset, u8, 0x24);

    // Make room for sprintf buffer and keep the pointer in edx
    offset = add_esp(offset, -0x400); // add    esp, -400h
    offset = write(offset, u8, 0x89); // mov    edx, esp
    offset = write(offset, u8, 0xE2);

    // Generate the string we'll display
    offset = push_eax(offset); // (trigger index)
    offset = push_u32(offset, offset_trigger_string); // (fmt)
    offset = push_edx(offset); // (buffer)
    offset = call(offset, 0x49EB80); // sprintf
    offset = pop_edx(offset); // (buffer)
    offset = add_esp(offset, 0x8);

    // Display a message
    offset = push_u32(offset, @bitCast(trigger_string_display_duration));
    offset = push_edx(offset); // (buffer)
    offset = call(offset, 0x44FCE0);
    offset = add_esp(offset, 0x8);

    // Pop the string buffer off of the stack
    offset = add_esp(offset, 0x400);

    // Jump to the real function to run the trigger
    offset = jmp(offset, 0x47CE60);

    // Install it by replacing the call destination (we'll jump to the real one)
    _ = call(0x476E80, offset_trigger_code);

    return offset;
}

export fn Patch() void {
    var offset: usize = @intFromPtr(VirtualAlloc(null, patch_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    PatchDeathSpeed(640, 25);

    offset = PatchTriggerDisplay(offset);

    if (false) {
        var mb_title = std.fmt.allocPrintZ(alloc, "Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }) catch unreachable;
        var mb_launch = "Patching SWE1R...";
        _ = MessageBoxA(null, mb_launch, mb_title, MB_OK);
    }
}
