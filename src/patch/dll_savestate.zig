pub const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;

const GlobalSt = @import("core/Global.zig").GlobalState;
const GlobalFn = @import("core/Global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("core/Global.zig").PLUGIN_VERSION;

const debug = @import("core/Debug.zig");

const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;
const st = @import("util/active_state.zig");
const scroll = @import("util/scroll_control.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");

const rf = @import("racer").functions;
const rc = @import("racer").constants;
const rg = @import("racer").Global;
const ri = @import("racer").Input;
const rt = @import("racer").Text;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rto = rt.TextStyleOpts;

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// Usable in Practice Mode only

// FEATURES
// - feat: set and restore a save point to quickly retry parts of a track
// - feat: delay for restoring a state, to help with getting your hand back in position in time
// - feat: freeze, rewind and scrub to any moment in the run
// - planned: scrub forward at the end of recorded history to record TAS input
// - planned: save replays/ghosts to file
// - CONTROLS:              keyboard    xinput
//   Save State             1           D-Down
//   Reload State           2           D-Up        Will load beginning of race if no state saved
//   Scrub Mode On/Off      2           D-Up        Press during reload delay when toggling on (i.e. double-tap)
//   Scrub Back             3           D-Left      Hold to rewind
//   Scrub Forward          4           D-Right     Hold to fast-forward
// - SETTINGS:
//   savestate_enable       bool
//   load_delay             u32         amount of time to delay restoring a savestate, in ms
//                                      * setting to a low value can interfere with ability to enter scrub mode

// NOTE: some of these might be outdated, review at next refactor
// FIXME: change disabling during pause to use Freeze api, so that you can still save/load
// during a real pause
// FIXME: stop assuming entities will be in index 0, particularly Test entity
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
// TODO: convert all allocations to global allocator once part of GlobalFn
// FIXME: stop recording when quitting, pausing, etc.
// TODO: recording during the opening cutscene, to account for world animations (SMR, etc.)
// TODO: dinput controls

const PLUGIN_NAME: [*:0]const u8 = "Savestate";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const LoadState = enum(u32) {
    Recording,
    Loading,
    Scrubbing,
    ScrubExiting,
};

const state = struct {
    var savestate_enable: bool = false;

    var rec_state: LoadState = .Recording;
    var initialized: bool = false;
    var frame: usize = 0;
    var frame_total: usize = 0;
    var last_framecount: u32 = 0;

    const off_input: usize = 0;
    const off_race: usize = ri.COMBINED_SIZE;
    const off_test: usize = off_race + rrd.SIZE;
    const off_hang: usize = off_test + re.Test.SIZE;
    const off_cman: usize = off_hang + re.Hang.SIZE;
    const off_END: usize = off_cman + re.cMan.SIZE;

    const frames: usize = 60 * 60 * 8; // 8min @ 60fps
    //const frame_size: usize = off_cman + rc.cMan.SIZE;
    const header_size: usize = std.math.divCeil(usize, off_END, 4 * 8) catch unreachable; // comptime
    const header_type: type = std.packed_int_array.PackedIntArray(u1, header_bits);
    const header_bits: usize = off_END / 4;
    const offsets_off: usize = 0;
    const offsets_size: usize = frames * 4;
    const headers_off: usize = offsets_off + offsets_size;
    const headers_size: usize = header_size * frames;
    const stage_off: usize = headers_off + headers_size;
    const data_off: usize = stage_off + off_END * 2;

    // FIXME: remove gpa/alloc, do some kind of core integration instead
    var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;
    var alloc: ?std.mem.Allocator = null;
    const memory_size: usize = 1024 * 1024 * 64; // 64MB
    var memory: []u8 = undefined;
    var memory_addr: usize = undefined;
    var memory_end_addr: usize = undefined;
    var raw_offsets: [*]u8 = undefined;
    var raw_headers: [*]u8 = undefined;
    var raw_stage: [*]u8 = undefined;
    var offsets: *[frames]usize = undefined;
    var headers: *[frames]header_type = undefined;
    var stage: *[2][off_END / 4]u32 = undefined;
    var data: [*]u8 = undefined;

    var load_delay: usize = 500; // ms
    var load_time: usize = 0;
    var load_frame: usize = 0;
    var load_count: usize = 0;

    // TODO: some kind of unified mapping thing, once dinput is implemented
    var save_input_st_data = ButtonInputMap{ .kb = .@"1", .xi = .DPAD_DOWN };
    var save_input_ld_data = ButtonInputMap{ .kb = .@"2", .xi = .DPAD_UP };
    var save_input_st = save_input_st_data.inputMap();
    var save_input_ld = save_input_ld_data.inputMap();

    var scrub: scroll.ScrollControl = .{
        .scroll_time = 3,
        .scroll_units = 24 * 8, // FIXME: doesn't scale with fps
        .input_dec = scrub_dec,
        .input_inc = scrub_inc,
    };
    var scrub_frame: i32 = 0;
    var scrub_input_dec_data = ButtonInputMap{ .kb = .@"3", .xi = .DPAD_LEFT };
    var scrub_input_inc_data = ButtonInputMap{ .kb = .@"4", .xi = .DPAD_RIGHT };
    var scrub_input_dec = scrub_input_dec_data.inputMap();
    var scrub_input_inc = scrub_input_inc_data.inputMap();

    fn scrub_dec(s: st.ActiveState) callconv(.C) bool {
        return scrub_input_dec.gets() == s;
    }

    fn scrub_inc(s: st.ActiveState) callconv(.C) bool {
        return scrub_input_inc.gets() == s;
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

    fn init(_: *GlobalFn) void {
        if (initialized) return;
        defer initialized = true;

        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        alloc = gpa.?.allocator();
        memory = alloc.?.alloc(u8, memory_size) catch @panic("failed to allocate memory for savestate/rewind");
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
    }

    fn deinit(_: *GlobalFn) void {
        if (!initialized) return;
        defer initialized = false;

        if (alloc) |a| a.free(memory);
        if (gpa) |_| switch (gpa.?.deinit()) {
            .leak => @panic("leak detected when deinitializing savestate/rewind"),
            else => {},
        };

        reset();
    }

    fn reset() void {
        if (frame == 0) return;
        frame = 0;
        frame_total = 0;
        load_frame = 0;
        load_count = 0;
        scrub_frame = 0;
        rec_state = .Recording;
    }

    // FIXME: better new-frame checking that doesn't only account for tabbing out
    // i.e. also when pausing, physics frozen with ingame feature, etc.
    fn saveable(gs: *GlobalSt) bool {
        const space_ok: bool = memory_end_addr - @intFromPtr(data) - offsets[frame] >= off_END;
        const frames_ok: bool = frame < frames - 1;
        return gs.in_race.on() and space_ok and frames_ok;
    }

    // FIXME: check if you're actually in the racing part, also integrate with global
    // apis like Freeze (same for saveable())
    fn loadable(gs: *GlobalSt) bool {
        const race_ok = gs.in_race.on();
        // TODO: migrate to racerlib, see also fn_45D0B0; also maybe add to gs.race_state as .Loading
        const loading_ok = mem.read(0x50CA34, u32) == 0;
        return race_ok and loading_ok;
    }

    // FIXME: check if you're actually in the racing part, also integrate with global
    // apis like Freeze (same for saveable())
    fn updateable(gs: *GlobalSt) bool {
        if (!gs.practice_mode) return false;

        const tabbed_out = rg.GUI_STOPPED.* > 0;
        const paused = rg.PAUSE_STATE.* > 0;
        const race_ok = gs.in_race.on();
        // TODO: migrate to racerlib, see also fn_45D0B0; also maybe add to gs.race_state as .Loading
        const loading_ok = mem.read(0x50CA34, u32) == 0;

        return race_ok and !tabbed_out and !paused and loading_ok;
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
        @memcpy(raw_stage[0..off_END], data[0..off_END]);

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
    fn save_compressed(gs: *GlobalSt, gv: *GlobalFn) void {
        // FIXME: why the fk does this crash if it comes after the guard
        if (!initialized) init(gv);
        if (!saveable(gs)) return;
        last_framecount = gs.framecount;

        var data_size: usize = 0;
        if (frame > 0) {
            uncompress_frame(frame, true);

            const s1_base = raw_stage + off_END;
            mem.read_bytes(ri.COMBINED_ADDR, s1_base + off_input, ri.COMBINED_SIZE);
            @memcpy(s1_base + off_race, rrd.PLAYER_SLICE.*);
            @memcpy(s1_base + off_test, re.Test.PLAYER_SLICE.*);
            @memcpy(s1_base + off_hang, re.Manager.entitySlice(.Hang, 0));
            @memcpy(s1_base + off_cman, re.Manager.entitySlice(.cMan, 0));

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
            data_size = off_END;
            mem.read_bytes(ri.COMBINED_ADDR, data + off_input, ri.COMBINED_SIZE);
            @memcpy(data + off_race, rrd.PLAYER_SLICE.*);
            @memcpy(data + off_test, re.Test.PLAYER_SLICE.*);
            @memcpy(data + off_hang, re.Manager.entitySlice(.Hang, 0));
            @memcpy(data + off_cman, re.Manager.entitySlice(.cMan, 0));
        }
        frame += 1;
        offsets[frame] = offsets[frame - 1] + data_size;
    }

    fn load_compressed(index: usize, gs: *GlobalSt) void {
        if (!loadable(gs)) return;

        uncompress_frame(index, false);
        _ = mem.write_bytes(ri.COMBINED_ADDR, &raw_stage[off_input], ri.COMBINED_SIZE);
        @memcpy(rrd.PLAYER_SLICE.*, raw_stage[off_race..off_test]); // WARN: maybe perm issues
        @memcpy(re.Test.PLAYER_SLICE.*, raw_stage[off_test..off_hang]); // WARN: maybe perm issues
        @memcpy(re.Manager.entitySlice(.Hang, 0).ptr, raw_stage[off_hang..off_cman]);
        @memcpy(re.Manager.entitySlice(.cMan, 0).ptr, raw_stage[off_cman..off_END]);
        frame = index + 1;
    }

    fn handle_settings(gf: *GlobalFn) callconv(.C) void {
        savestate_enable = gf.SettingGetB("savestate", "enable") orelse false;
        load_delay = gf.SettingGetU("savestate", "load_delay") orelse 500;
    }
};

// LOADER LOGIC

fn DoStateRecording(gs: *GlobalSt, gf: *GlobalFn) LoadState {
    state.save_compressed(gs, gf);

    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.frame - 1;
    }
    if (state.save_input_ld.gets() == .JustOn and state.frames > 0) {
        state.load_time = state.load_delay + gs.timestamp;
        return .Loading;
    }

    return .Recording;
}

fn DoStateLoading(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.save_input_ld.gets() == .JustOn) {
        state.scrub_frame = std.math.cast(i32, state.frame).? - 1;
        state.frame_total = state.frame;
        return .Scrubbing;
    }
    if (gs.timestamp >= state.load_time) {
        state.load_compressed(state.load_frame, gs);
        state.load_count += 1;
        return .Recording;
    }
    return .Loading;
}

fn DoStateScrubbing(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.frame - 1;
    }
    if (state.save_input_ld.gets() == .JustOn) {
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

fn DoStateScrubExiting(gs: *GlobalSt, _: *GlobalFn) LoadState {
    state.load_compressed(std.math.cast(u32, state.scrub_frame).?, gs);

    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.frame - 1;
    }

    if (gs.timestamp < state.load_time) return .ScrubExiting;

    state.load_count += 1;
    return .Recording;
}

fn UpdateState(gs: *GlobalSt, gv: *GlobalFn) void {
    if (!state.updateable(gs)) return;

    if (gs.race_state != .Racing)
        return state.reset();

    state.rec_state = switch (state.rec_state) {
        .Recording => DoStateRecording(gs, gv),
        .Loading => DoStateLoading(gs, gv),
        .Scrubbing => DoStateScrubbing(gs, gv),
        .ScrubExiting => DoStateScrubExiting(gs, gv),
    };
}

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    state.handle_settings(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    state.deinit(gf);
}

// HOOKS

//pub fn MenuStartRaceB(gs: *GlobalState,gv:*GlobalFn, initialized: bool) callconv(.C) void {
//    state.reset();
//}

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    state.handle_settings(gf);
}

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    state.scrub_input_dec.update(gf);
    state.scrub_input_inc.update(gf);
    state.save_input_st.update(gf);
    state.save_input_ld.update(gf);
}

// TODO: maybe reset state/recording if savestates or practice mode disabled?
export fn EngineUpdateStage20A(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (!state.savestate_enable) return;
    UpdateState(gs, gf);
}

// TODO: merge with EngineUpdateStage20A?
export fn EarlyEngineUpdateA(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (!state.savestate_enable) return;

    // TODO: show during whole race scene? esp. if recording from count
    // TODO: experiment with positioning
    // TODO: experiment with conditionally showing each string; only show fr
    // if playing back, only show st if a frame is actually saved?
    if (gs.practice_mode and gs.race_state == .Racing) {
        rt.DrawText(16, 480 - 16, "Fr {d}", .{state.frame}, null, null) catch {};
        rt.DrawText(92, 480 - 16, "St {d}", .{state.load_frame}, null, null) catch {};
        if (state.load_count > 0)
            rt.DrawText(168, 480 - 16, "Ld {d}", .{state.load_count}, null, null) catch {};
    }
}

// COMPRESSION-RELATED FUNCTIONS
// not really in use/needs work, basically just stuff for testing

// TODO: move to compression lib whenever that happens

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
// TODO: cleanup unreachable after migrating to lib
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
