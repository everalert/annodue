pub const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const st = @import("util/active_state.zig");
const scroll = @import("util/scroll_control.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

// NOTE: some of these might be outdated, review at next refactor
// FIXME: change disabling during pause to use Freeze api, so that you can still save/load
// during a real pause
// FIXME: stop assuming entities will be in index 0, particularly Test entity
// FIXME: game crashes after a bit when tabbing out; probably the allocated memory
// filling up quickly because there is no frame pacing while tabbed out? not sure
// why it's able to overflow though, saveable() is supposed to prevent this.
// update - prevented saving while tabbed out, core issue still remains tho
// update - prevented running updates while paused, core issue still not fixed
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
        .input_dec = scrub_dec,
        .input_inc = scrub_inc,
    };
    var scrub_frame: i32 = 0;
    var scrub_input_dec: w32kb.VIRTUAL_KEY = .@"3";
    var scrub_input_inc: w32kb.VIRTUAL_KEY = .@"4";
    var scrub_input_dec_state: st.ActiveState = undefined;
    var scrub_input_inc_state: st.ActiveState = undefined;

    fn scrub_dec(s: st.ActiveState) callconv(.C) bool {
        return scrub_input_dec_state == s;
    }

    fn scrub_inc(s: st.ActiveState) callconv(.C) bool {
        return scrub_input_inc_state == s;
    }

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

    fn init(gv: *GlobalFn) void {
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

        load_delay = gv.SettingGetU("savestate", "load_delay") orelse 500;

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
    fn saveable(gs: *GlobalState) bool {
        const space_ok: bool = memory_end_addr - @intFromPtr(data) - offsets[frame] >= frame_size;
        const frames_ok: bool = frame < frames;
        return gs.in_race.on() and space_ok and frames_ok;
    }

    // FIXME: check if you're actually in the racing part, also integrate with global
    // apis like Freeze (same for saveable())
    fn loadable(gs: *GlobalState) bool {
        return gs.in_race.on();
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
    fn save_compressed(gs: *GlobalState, gv: *GlobalFn) void {
        // FIXME: why the fk does this crash if it comes after the guard
        if (!initialized) init(gv);
        if (!saveable(gs)) return;
        last_framecount = gs.framecount;

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

    fn load_compressed(index: usize, gs: *GlobalState) void {
        if (!loadable(gs)) return;

        uncompress_frame(index, false);
        r.WriteRaceDataValueBytes(0, &raw_stage[off_race], rc.RACE_DATA_SIZE);
        r.WritePlayerValueBytes(0, &raw_stage[off_test], rc.EntitySize(.Test));
        r.WriteEntityValueBytes(.Hang, 0, 0, &raw_stage[off_hang], rc.EntitySize(.Hang));
        r.WriteEntityValueBytes(.cMan, 0, 0, &raw_stage[off_cman], rc.EntitySize(.cMan));
        frame = index + 1;
    }
};

// LOADER LOGIC

fn DoStateRecording(gs: *GlobalState, gv: *GlobalFn) LoadState {
    state.save_compressed(gs, gv);

    if (gv.InputGetKbPressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }
    if (gv.InputGetKbPressed(.@"2") and state.frames > 0) {
        state.load_time = state.load_delay + gs.timestamp;
        return .Loading;
    }

    return .Recording;
}

fn DoStateLoading(gs: *GlobalState, gv: *GlobalFn) LoadState {
    if (gv.InputGetKbPressed(.@"2")) {
        state.scrub_frame = std.math.cast(i32, state.frame).? - 1;
        state.frame_total = state.frame;
        return .Scrubbing;
    }
    if (gs.timestamp >= state.load_time) {
        state.load_compressed(state.load_frame, gs);
        return .Recording;
    }
    return .Loading;
}

fn DoStateScrubbing(gs: *GlobalState, gv: *GlobalFn) LoadState {
    if (gv.InputGetKbPressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }
    if (gv.InputGetKbPressed(.@"2")) {
        state.load_frame = @min(state.load_frame, std.math.cast(u32, state.scrub_frame).?);
        state.load_time = state.load_delay + gs.timestamp;
        return .ScrubExiting;
    }

    state.scrub_frame = state.scrub.UpdateEx(
        state.scrub_frame,
        std.math.cast(i32, state.frame_total).?,
        false,
    );

    state.load_compressed(std.math.cast(u32, state.scrub_frame).?, gs);
    return .Scrubbing;
}

fn DoStateScrubExiting(gs: *GlobalState, gv: *GlobalFn) LoadState {
    state.load_compressed(std.math.cast(u32, state.scrub_frame).?, gs);

    if (gv.InputGetKbPressed(.@"1")) {
        state.load_frame = state.frame - 1;
    }

    if (gs.timestamp < state.load_time) return .ScrubExiting;
    return .Recording;
}

fn UpdateState(gs: *GlobalState, gv: *GlobalFn) void {
    state.rec_state = switch (state.rec_state) {
        .Recording => DoStateRecording(gs, gv),
        .Loading => DoStateLoading(gs, gv),
        .Scrubbing => DoStateScrubbing(gs, gv),
        .ScrubExiting => DoStateScrubExiting(gs, gv),
    };
}

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "Savestate";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.0";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

//pub fn MenuStartRaceB(gs: *GlobalState,gv:*GlobalFn, initialized: bool) callconv(.C) void {
//    state.reset();
//}

export fn InputUpdateB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    state.scrub_input_dec_state = gv.InputGetKbRaw(state.scrub_input_dec);
    state.scrub_input_inc_state = gv.InputGetKbRaw(state.scrub_input_inc);
}

export fn EarlyEngineUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("savestate", "savestate_enable").?) return;

    const tabbed_out = mem.read(rc.ADDR_GUI_STOPPED, u32) > 0;
    const paused: bool = mem.read(rc.ADDR_PAUSE_STATE, u8) > 0;
    if (!paused and !tabbed_out and gs.practice_mode and gs.in_race.on()) {
        if (gs.player.in_race_racing.on()) UpdateState(gs, gv) else state.reset();
    }
}

export fn TextRenderB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("savestate", "savestate_enable").?) return;

    //const tabbed_out = mem.read(rc.ADDR_GUI_STOPPED, u32) > 0;
    //const paused: bool = mem.read(rc.ADDR_PAUSE_STATE, u8) > 0;
    if (gs.practice_mode and gs.in_race.on()) {
        if (gs.player.in_race_racing.on()) {
            rt.DrawText(16, 480 - 16, "Fr {d}", .{state.frame}, null, null) catch {};
            rt.DrawText(92, 480 - 16, "St {d}", .{state.load_frame}, null, null) catch {};
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
