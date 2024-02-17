pub const Self = @This();

const std = @import("std");

const settings = @import("settings.zig");
const s = settings.state;
const g = @import("global.zig").state;

const scroll = @import("util/scroll_control.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

// FIXME: stop assuming entities will be in index 0, particularly Test entity
// FIXME: game crashes after a bit when tabbing out; probably the allocated memory
// filling up quickly because there is no frame pacing while tabbed out? not sure
// why it's able to overflow though, saveable() is supposed to prevent this.
// update - prevented saving while tabbed out, core issue still remains tho
// FIXME: sometimes crashes when rendering race stats, not sure why but seems
// correlated to dying. doesn't seem to be an issue if you don't load any states
// during the run.
// FIXME: more appropriate hook point to run main logic than GameLoop_After;
// after Test functions run but before rendering, so that nothing changes the loaded data
// TODO: array of static frames of "pure" savestates
// TODO: frame advance when scrubbing forward at the final recorded frame
// TODO: figure out a way to persist states through a reset without messing
// up the frame history
// TODO: self-expanding frame memory for infinite recording time; likely need to split
// the memory allocation for this

const LoadState = enum(u32) {
    Recording,
    Loading,
    Scrubbing,
    ScrubExiting,
};

const state = struct {
    var rec_state: LoadState = .Recording;
    var initialized: bool = false;
    var frame: usize = 0;
    var frame_total: usize = 0;
    var last_framecount: u32 = 0;

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
    var memory: []u8 = undefined;
    var memory_addr: usize = undefined;
    var memory_end_addr: usize = undefined;
    var raw_offsets: [*]u8 = undefined;
    var raw_headers: [*]u8 = undefined;
    var raw_stage: [*]u8 = undefined;
    var offsets: *[frames]usize = undefined;
    var headers: *[frames]header_type = undefined;
    var stage: *[2][frame_size / 4]u32 = undefined;
    var data: [*]u8 = undefined;

    var load_delay: usize = 500; // ms
    var load_time: usize = 0;
    var load_frame: usize = 0;

    var scrub: scroll.ScrollControl = .{
        .scroll_time = 3,
        .scroll_units = 24 * 8, // FIXME: doesn't scale with fps
        .input_dec = .@"3",
        .input_inc = .@"4",
    };
    var scrub_frame: i32 = 0;

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

    fn init() void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const alloc = gpa.allocator();
        memory = alloc.alloc(u8, memory_size) catch unreachable;
        @memset(memory[0..memory_size], 0x00);

        memory_addr = @intFromPtr(memory.ptr);
        memory_end_addr = @intFromPtr(memory.ptr) + memory_size;
        raw_offsets = memory.ptr + offsets_off;
        raw_headers = memory.ptr + headers_off;
        raw_stage = memory.ptr + stage_off;
        data = memory.ptr + data_off;
        offsets = @as(@TypeOf(offsets), @ptrFromInt(memory_addr + offsets_off));
        headers = @as(@TypeOf(headers), @ptrFromInt(memory_addr + headers_off));
        stage = @as(@TypeOf(stage), @ptrFromInt(memory_addr + stage_off));

        load_delay = s.sav.get("load_delay", u32);

        initialized = true;
    }

    fn reset() void {
        if (frame == 0) return;
        frame = 0;
        frame_total = 0;
        load_frame = 0;
        scrub_frame = 0;
        rec_state = .Recording;
    }

    // FIXME: better new-frame checking that doesn't only account for tabbing out
    // i.e. also when pausing, physics frozen with ingame feature, etc.
    fn saveable() bool {
        const frame_new: bool = mem.read(rc.ADDR_TIME_FRAMECOUNT, u32) != last_framecount;
        const in_race: bool = mem.read(rc.ADDR_IN_RACE, u8) > 0;
        const space_ok: bool = memory_end_addr - @intFromPtr(data) - offsets[frame] >= frame_size;
        const frames_ok: bool = frame < frames;
        return frame_new and in_race and space_ok and frames_ok;
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
    fn save_compressed() void {
        // FIXME: why the fk does this crash if it comes after the guard
        if (!initialized) init();
        if (!saveable()) return;
        last_framecount = mem.read(rc.ADDR_TIME_FRAMECOUNT, u32);

        var data_size: usize = 0;
        if (frame > 0) {
            uncompress_frame(frame, true);

            const s1_base = raw_stage + frame_size;
            r.ReadRaceDataValueBytes(0, s1_base + off_race, rc.RACE_DATA_SIZE);
            r.ReadPlayerValueBytes(0, s1_base + off_test, rc.EntitySize(.Test));
            r.ReadEntityValueBytes(.Hang, 0, 0, s1_base + off_hang, rc.EntitySize(.Hang));
            r.ReadEntityValueBytes(.cMan, 0, 0, s1_base + off_cman, rc.EntitySize(.cMan));

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
            r.ReadPlayerValueBytes(0, data + off_test, rc.EntitySize(.Test));
            r.ReadEntityValueBytes(.Hang, 0, 0, data + off_hang, rc.EntitySize(.Hang));
            r.ReadEntityValueBytes(.cMan, 0, 0, data + off_cman, rc.EntitySize(.cMan));
        }
        frame += 1;
        offsets[frame] = offsets[frame - 1] + data_size;
    }

    fn load_compressed(index: usize) void {
        if (!loadable()) return;

        uncompress_frame(index, false);
        r.WriteRaceDataValueBytes(0, &raw_stage[off_race], rc.RACE_DATA_SIZE);
        r.WritePlayerValueBytes(0, &raw_stage[off_test], rc.EntitySize(.Test));
        r.WriteEntityValueBytes(.Hang, 0, 0, &raw_stage[off_hang], rc.EntitySize(.Hang));
        r.WriteEntityValueBytes(.cMan, 0, 0, &raw_stage[off_cman], rc.EntitySize(.cMan));
        frame = index + 1;
    }
};

// LOADER LOGIC

fn DoStateRecording() LoadState {
    const timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    state.save_compressed();

    if (input.get_kb_pressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }
    if (input.get_kb_pressed(.@"2") and state.frames > 0) {
        state.load_time = state.load_delay + timestamp;
        return .Loading;
    }

    return .Recording;
}

fn DoStateLoading() LoadState {
    const timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    if (input.get_kb_pressed(.@"2")) {
        state.scrub_frame = std.math.cast(i32, state.frame).? - 1;
        state.frame_total = state.frame;
        return .Scrubbing;
    }
    if (timestamp >= state.load_time) {
        state.load_compressed(state.load_frame);
        return .Recording;
    }
    return .Loading;
}

fn DoStateScrubbing() LoadState {
    const timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    if (input.get_kb_pressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }
    if (input.get_kb_pressed(.@"2")) {
        state.load_frame = @min(state.load_frame, std.math.cast(u32, state.scrub_frame).?);
        state.load_time = state.load_delay + timestamp;
        return .ScrubExiting;
    }

    state.scrub.update(&state.scrub_frame, std.math.cast(i32, state.frame_total).?, false);

    state.load_compressed(std.math.cast(u32, state.scrub_frame).?);
    return .Scrubbing;
}

fn DoStateScrubExiting() LoadState {
    const timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    state.load_compressed(std.math.cast(u32, state.scrub_frame).?);

    if (input.get_kb_pressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }

    if (timestamp < state.load_time) return .ScrubExiting;
    return .Recording;
}

fn UpdateState() void {
    state.rec_state = switch (state.rec_state) {
        .Recording => DoStateRecording(),
        .Loading => DoStateLoading(),
        .Scrubbing => DoStateScrubbing(),
        .ScrubExiting => DoStateScrubExiting(),
    };
}

// HOOKS

//pub fn MenuStartRace_Before() void {
//    state.reset();
//}

pub fn EarlyEngineUpdate_After() void {
    if (!s.sav.get("savestate_enable", bool)) return;

    const in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;
    if (g.practice_mode and in_race) {
        const flags1: u32 = r.ReadPlayerValue(0x60, u32);
        const is_racing: bool = !((flags1 & (1 << 0)) > 0 or (flags1 & (1 << 5)) == 0);

        if (is_racing) UpdateState() else state.reset();
    }
}

pub fn TextRender_Before() void {
    if (!s.sav.get("savestate_enable", bool)) return;

    const in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;
    if (g.practice_mode and in_race) {
        const flags1: u32 = r.ReadPlayerValue(0x60, u32);
        const is_racing: bool = !((flags1 & (1 << 0)) > 0 or (flags1 & (1 << 5)) == 0);

        if (is_racing) {
            var buff: [1023:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buff, "~F0~sFr {d}", .{state.frame}) catch unreachable;
            rf.swrText_CreateEntry1(16, 480 - 16, 255, 255, 255, 190, &buff);

            var bufs: [1023:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&bufs, "~F0~sSt {d}", .{state.load_frame}) catch unreachable;
            rf.swrText_CreateEntry1(92, 480 - 16, 255, 255, 255, 190, &bufs);
        }
    }
}

// COMPRESSION-RELATED FUNCTIONS
// not really in use/needs work

// FIXME: assumes array of raw data; rework to adapt it to new compressed data
fn save_file() void {
    const file = std.fs.cwd().createFile("annodue/testdata.bin", .{}) catch |err| return msg.ErrMessage("create file", @errorName(err));
    defer file.close();

    const middle = state.frame * state.frame_size;
    const end = state.frames * state.frame_size;
    _ = file.write(state.data[middle..end]) catch return;
    _ = file.write(state.data[0..middle]) catch return;
}

// FIXME: dumped from patch.zig; need to rework into a generalized function
fn check_compression_potential() void {
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
