const std = @import("std");
const user32 = std.os.windows.user32;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const mem = @import("util/memory.zig");

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

const patch_size: u32 = 4 * 1024 * 1024;

export fn PatchDeathSpeed(min: f32, drop: f32) void {
    //0x4C7BB8	4	DeathSpeedMin	float	325.0		SWEP1RCR.EXE+0x0C7BB8
    _ = mem.write(0x4C7BB8, f32, min);
    //0x4C7BBC	4	DeathSpeedDrop	float	140.0		SWEP1RCR.EXE+0x0C7BBC
    _ = mem.write(0x4C7BBC, f32, drop);
}

export fn PatchTriggerDisplay(memory_offset: usize) usize {
    var offset = memory_offset;

    // Display triggers
    const trigger_string = "Trigger %d activated";
    const trigger_string_display_duration: f32 = 3.0;

    var offset_trigger_string = offset;
    offset = mem.write(offset, @TypeOf(trigger_string.*), trigger_string.*);

    var offset_trigger_code: u32 = offset;

    // Read the trigger from stack
    offset = mem.write(offset, u8, 0x8B); // mov    eax, [esp+4]
    offset = mem.write(offset, u8, 0x44);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, 0x04);

    // Get pointer to section 8
    offset = mem.write(offset, u8, 0x8B); // 8b 40 4c  ->  mov    eax,DWORD PTR [eax+0x4c]
    offset = mem.write(offset, u8, 0x40);
    offset = mem.write(offset, u8, 0x4C);

    // Read the section8.trigger_action field
    offset = mem.write(offset, u8, 0x0F); // 0f b7 40 24  ->  movzx    eax, WORD PTR [eax+0x24]
    offset = mem.write(offset, u8, 0xB7);
    offset = mem.write(offset, u8, 0x40);
    offset = mem.write(offset, u8, 0x24);

    // Make room for sprintf buffer and keep the pointer in edx
    offset = mem.add_esp(offset, -0x400); // add    esp, -400h
    offset = mem.write(offset, u8, 0x89); // mov    edx, esp
    offset = mem.write(offset, u8, 0xE2);

    // Generate the string we'll display
    offset = mem.push_eax(offset); // (trigger index)
    offset = mem.push_u32(offset, offset_trigger_string); // (fmt)
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x49EB80); // sprintf
    offset = mem.pop_edx(offset); // (buffer)
    offset = mem.add_esp(offset, 0x8);

    // Display a message
    offset = mem.push_u32(offset, @bitCast(trigger_string_display_duration));
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x44FCE0);
    offset = mem.add_esp(offset, 0x8);

    // Pop the string buffer off of the stack
    offset = mem.add_esp(offset, 0x400);

    // Jump to the real function to run the trigger
    offset = mem.jmp(offset, 0x47CE60);

    // Install it by replacing the call destination (we'll jump to the real one)
    _ = mem.call(0x476E80, offset_trigger_code);

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
