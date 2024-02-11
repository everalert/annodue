pub const Self = @This();
const std = @import("std");

const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;

// TODO: array of static frames of "pure" savestates
const savestate = struct {
    const off_race: usize = 0;
    const off_test: usize = rc.RACE_DATA_SIZE;
    const off_hang: usize = off_test + rc.EntitySize(.Test);
    const off_cman: usize = off_hang + rc.EntitySize(.Hang);

    const frames: usize = 60 * 60 * 8; // 8min @ 60fps
    const frame_size: usize = off_cman + rc.EntitySize(.cMan);
    const header_size: usize = std.math.divCeil(usize, frame_size, 4 * 8) catch unreachable;
    const header_type: type = std.packed_int_array.PackedIntArray(u1, header_bits);
    const header_bits: usize = frame_size / 4;
    const offsets_off: usize = 0;
    const offsets_size: usize = frames * 4;
    const headers_off: usize = offsets_off + offsets_size;
    const headers_size: usize = header_size * frames;
    const stage_off: usize = headers_off + headers_size;
    const data_off: usize = stage_off + frame_size * 2;

    const memory_size: usize = 1024 * 1024 * 64; // 64MB
    var memory: ?std.os.windows.LPVOID = null;
    var memory_addr: usize = undefined;
    var raw_offsets: [*]u8 = undefined;
    var raw_headers: [*]u8 = undefined;
    var raw_stage: [*]u8 = undefined;
    var offsets: *[frames]usize = undefined;
    var headers: *[frames]header_type = undefined;
    var stage: *[2][frame_size / 4]u32 = undefined;
    var data: [*]u8 = undefined;

    const load_delay: usize = 750; // ms
    var load_queued: bool = false;
    var load_time: usize = 0;
    var load_frame: usize = 0;

    const layer_size: isize = 4;
    const layer_depth: isize = 4;
    var layer_widths: [layer_depth]usize = widths: {
        var widths: [layer_depth]usize = undefined;
        for (1..layer_depth + 1) |f| {
            widths[layer_depth - f] = std.math.pow(usize, layer_size, f);
        }
        break :widths widths;
    };
    var layer_indexes: [layer_depth + 1]usize = undefined;
    var layer_index_count: usize = undefined;
    var frame: usize = 0;
    var frame_total: usize = 0;
    var initialized: bool = false;

    var debug_loading: bool = false;

    fn init() void {
        const mem_alloc = MEM_COMMIT | MEM_RESERVE;
        const mem_protect = PAGE_EXECUTE_READWRITE;
        memory = VirtualAlloc(null, memory_size, mem_alloc, mem_protect) catch unreachable;
        memory_addr = @intFromPtr(memory);
        raw_offsets = @as([*]u8, @ptrCast(memory)) + offsets_off;
        raw_headers = @as([*]u8, @ptrCast(memory)) + headers_off;
        raw_stage = @as([*]u8, @ptrCast(memory)) + stage_off;
        data = @as([*]u8, @ptrCast(memory)) + data_off;
        offsets = @as(@TypeOf(offsets), @ptrFromInt(memory_addr + offsets_off));
        headers = @as(@TypeOf(headers), @ptrFromInt(memory_addr + headers_off));
        stage = @as(@TypeOf(stage), @ptrFromInt(memory_addr + stage_off));
        initialized = true;
    }

    // FIXME: figure out a way to persist states through a reset without messing
    // up the frame history
    fn reset() void {
        if (frame == 0) return;
        frame = 0;
        frame_total = 0;
        load_frame = 0;
        load_queued = false;
    }

    // FIXME: assumes array of raw data; rework to adapt it to new compressed data
    fn save_file() void {
        const file = std.fs.cwd().createFile("annodue/testdata.bin", .{}) catch |err| return msg.ErrMessage("create file", @errorName(err));
        defer file.close();

        _ = file.write(data[frame * frame_size .. frames * frame_size]) catch return;
        _ = file.write(data[0 .. frame * frame_size]) catch return;
    }

    fn saveable() bool {
        const in_race: bool = mem.read(rc.ADDR_IN_RACE, u8) > 0;
        const space_available: bool = memory_size - offsets[frame] >= frame_size;
        const frames_available: bool = frame < frames;
        return in_race and space_available and frames_available;
    }

    fn loadable() bool {
        const in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;
        return in_race;
    }

    fn get_depth(index: usize) usize {
        var depth: usize = layer_depth;
        var depth_test: usize = index;
        while (depth_test % layer_size == 0 and depth > 0) : (depth -= 1) {
            depth_test /= layer_size;
        }
        return depth;
    }

    fn set_layer_indexes(index: usize) void {
        layer_index_count = 0;
        var last_base: usize = 0;
        for (layer_widths) |w| {
            const remainder = index % w;
            const base = index - remainder;
            if (base > 0 and base != last_base) {
                last_base = base;
                layer_indexes[layer_index_count] = base;
                layer_index_count += 1;
            }
            if (remainder < layer_size) {
                if (remainder == 0) break;
                layer_indexes[layer_index_count] = index;
                layer_index_count += 1;
                break;
            }
        }
    }

    fn uncompress_frame(index: usize, skip_last: bool) void {
        @memcpy(raw_stage[0..frame_size], data[0..frame_size]);

        set_layer_indexes(index);
        var indexes: usize = layer_index_count - @intFromBool(skip_last);
        if (indexes == 0) return;

        for (layer_indexes[0..indexes]) |l| {
            const header = &headers[l];
            const frame_data = @as([*]usize, @ptrFromInt(@intFromPtr(data) + offsets[l]));
            var j: usize = 0;
            for (0..header_bits) |h| {
                if (header.get(h) == 1) {
                    stage[0][h] = frame_data[j];
                    j += 1;
                }
            }
        }
    }

    // FIXME: in future, probably can skip the first step each new frame, because
    // the most recent frame would already be in stage1 from last time
    // FIXME: some kind of checking so that a new frame isn't added unless it is
    // actually new, e.g. when tabbed out, pausing, physics frozen in some way..
    fn save_compressed() void {
        // FIXME: why the fk does this crash if it comes after the guard
        if (!initialized) init();
        if (!saveable()) return;

        var data_size: usize = 0;
        if (frame > 0) {
            // setup stage0 with comparison frame
            uncompress_frame(frame, true);

            // setup stage1 with new frame
            const s1_base = raw_stage + frame_size;
            r.ReadRaceDataValueBytes(0, s1_base + off_race, rc.RACE_DATA_SIZE);
            r.ReadEntityValueBytes(.Test, 0, 0, s1_base + off_test, rc.EntitySize(.Test));
            r.ReadEntityValueBytes(.Hang, 0, 0, s1_base + off_hang, rc.EntitySize(.Hang));
            r.ReadEntityValueBytes(.cMan, 0, 0, s1_base + off_cman, rc.EntitySize(.cMan));

            // dif frames, while counting compressed size and constructing header
            var header = &headers[frame];
            header.setAll(0);
            var new_frame = @as([*]u32, @ptrFromInt(@intFromPtr(data) + offsets[frame]));
            var j: usize = 0;
            for (0..header_bits) |h| {
                if (stage[0][h] != stage[1][h]) {
                    header.set(h, 1);
                    new_frame[j] = stage[1][h];
                    data_size += 4;
                    j += 1;
                }
            }
        } else {
            data_size = frame_size;
            r.ReadRaceDataValueBytes(0, data + off_race, rc.RACE_DATA_SIZE);
            r.ReadEntityValueBytes(.Test, 0, 0, data + off_test, rc.EntitySize(.Test));
            r.ReadEntityValueBytes(.Hang, 0, 0, data + off_hang, rc.EntitySize(.Hang));
            r.ReadEntityValueBytes(.cMan, 0, 0, data + off_cman, rc.EntitySize(.cMan));
        }
        frame += 1;
        offsets[frame] = offsets[frame - 1] + data_size;
    }

    // FIXME: sometimes crashes when rendering race stats, not sure why but seems
    // correlated to dying during the run. doesn't seem to be an issue if you don't
    // load any states during the run.
    fn load_compressed(index: usize) void {
        if (!loadable()) return;

        uncompress_frame(index, false);
        r.WriteRaceDataValueBytes(0, &raw_stage[off_race], rc.RACE_DATA_SIZE);
        r.WriteEntityValueBytes(.Test, 0, 0, &raw_stage[off_test], rc.EntitySize(.Test));
        r.WriteEntityValueBytes(.Hang, 0, 0, &raw_stage[off_hang], rc.EntitySize(.Hang));
        r.WriteEntityValueBytes(.cMan, 0, 0, &raw_stage[off_cman], rc.EntitySize(.cMan));
        frame = index + 1;
    }

    fn queue_load(timestamp: usize) void {
        load_time = load_delay + timestamp;
        load_queued = true;
    }

    // FIXME: tries to load after a reset if you queue before the reset
    fn queue_check(timestamp: usize) void {
        if (load_queued and timestamp >= load_time) {
            load_compressed(load_frame);
            load_queued = false;
        }
    }
};

pub fn MenuStartRace_Before() void {
    savestate.reset();
}

// FIXME: more appropriate hook point to run this
// after Test functions run but before rendering, so that nothing changes the loaded data
pub fn GameLoop_After(practice_mode: bool) void {
    if (practice_mode) {
        const in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;
        if (in_race) {
            const pause: u8 = mem.read(rc.ADDR_PAUSE_STATE, u8);
            if (input.get_kb_pressed(.I))
                _ = mem.write(rc.ADDR_PAUSE_STATE, u8, (pause + 1) % 2);

            const timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
            const flags1: u32 = r.ReadEntityValue(.Test, 0, 0x60, u32);
            const cannot_use: bool = (flags1 & (1 << 0)) > 0 or (flags1 & (1 << 5)) == 0;

            if (cannot_use) {
                savestate.reset();
            } else {
                // FIXME: game crashes after a bit when tabbing out; probably
                // the allocated memory filling up quickly because there is no
                // frame pacing while tabbed out? not sure why it's able to
                // overflow though, saveable() is supposed to prevent this
                savestate.save_compressed();
                savestate.queue_check(timestamp);

                if (input.get_kb_pressed(.@"2") and savestate.frames > 0)
                    savestate.queue_load(timestamp);

                if (input.get_kb_pressed(.@"1"))
                    savestate.load_frame = savestate.frame;

                var buff: [1023:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buff, "~F0~sFr {d}", .{savestate.frame}) catch unreachable;
                rf.swrText_CreateEntry1(16, 480 - 16, 255, 255, 255, 190, &buff);

                var bufs: [1023:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&bufs, "~F0~sSt {d}", .{savestate.load_frame}) catch unreachable;
                rf.swrText_CreateEntry1(92, 480 - 16, 255, 255, 255, 190, &bufs);
            }
        }
    }
}

// FIXME: dumped from patch.zig; need to rework into a generalized function
pub fn check_compression_potential() void {
    const savestate_size: usize = 0x2428 / 4;
    const savestate_count: usize = 128;
    const savestate_head: usize = savestate_size / 8;
    const layer_size: usize = 4;
    const layer_depth: usize = 4;

    const testfile = std.fs.cwd().openFile("annodue/testdata.bin", .{}) catch unreachable;
    defer testfile.close();
    const reportfile = std.fs.cwd().createFile("annodue/testreport.txt", .{}) catch unreachable;
    defer reportfile.close();

    var data = std.mem.zeroes([layer_depth + 1][savestate_size]u32);
    var total_bytes: usize = 0;

    for (0..savestate_count - 1) |i| {
        var depth: usize = layer_depth;
        var depth_test: usize = i;
        while (depth_test % layer_size == 0 and depth > 0) {
            depth_test /= layer_size;
            depth -= 1;
        }

        _ = testfile.read(@as(*[savestate_size * 4]u8, @ptrCast(&data[depth]))) catch unreachable;
        if (depth < layer_depth) {
            for (depth + 1..layer_depth) |d| {
                data[d] = data[depth];
            }
        }

        const frame_bytes: usize = if (depth > 0) bytes: {
            var dif_count: usize = 0;
            for (data[depth], data[depth - 1]) |new, src| {
                if (new != src) dif_count += 1;
            }
            break :bytes dif_count * 4;
        } else savestate_size * 4;

        var buf: [17]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "Frame {d: >3}:\t{d: >4}\r\n", .{ i + 1, frame_bytes + savestate_head }) catch unreachable;
        _ = reportfile.write(&buf) catch unreachable;
        total_bytes += frame_bytes + savestate_head;
    }

    var buf: [26]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "Total: {d: >8}/{d: >8}\r\n", .{ total_bytes, savestate_size * savestate_count * 4 }) catch unreachable;
    _ = reportfile.write(&buf) catch unreachable;
}
