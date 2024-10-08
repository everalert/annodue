pub const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;
const st = @import("util/active_state.zig");
const scroll = @import("util/scroll_control.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const TemporalCompressor = @import("util/temporal_compression.zig").TemporalCompressor;
const TDataPoint = @import("util/temporal_compression.zig").DataPoint;

const rg = @import("racer").Global;
const rin = @import("racer").Input;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rr = @import("racer").Random;
const rti = @import("racer").Time;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;
const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;

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
//   enable                 bool
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

const RewindDataType = TemporalCompressor(4, 4, 4);

const state = struct {
    var initialized: bool = false;

    // settings
    var s_h_section: ?SettingHandle = null;
    var s_h_enable: ?SettingHandle = null;
    var s_h_load_delay: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_load_delay: usize = 500; // ms

    var rec_state: LoadState = .Recording;
    var rec_data: RewindDataType = .{};
    var rec_sources = [_]TDataPoint{
        .{}, // RaceData
        .{}, // Test
        .{}, // Hang
        .{}, // cMan
        .{}, // Smok
        .{}, // Toss
        .{ .data = @as([*]u8, @ptrFromInt(rin.RACE_COMBINED_ADDR))[0..rin.RACE_COMBINED_SIZE] }, // Input
        .{ .data = @as([*]u8, @ptrFromInt(rin.GLOBAL_ADDR))[0..rin.GLOBAL_SIZE] }, // Input
        .{ .data = @as([*]u8, @ptrCast(rti.TIMING))[0..rti.TIMING_SIZE] }, // Timing
        .{ .data = @as([*]u8, @ptrCast(rr.NUMBER))[0..4] }, // RNG
    };

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

    fn reset() void {
        rec_data.reset();
        rec_sources[0].data = rrd.PLAYER_SLICE.*;
        rec_sources[1].data = re.Test.PLAYER_SLICE.*;
        rec_sources[2].data = re.Manager.entitySlice(.Hang, 0);
        rec_sources[3].data = re.Manager.entitySlice(.cMan, 0);
        rec_sources[4].data = re.Manager.entitySliceAll(.Smok);
        rec_sources[5].data = re.Manager.entitySliceAll(.Toss);
        // don't need to update any other sources
        load_frame = 0;
        load_count = 0;
        scrub_frame = 0;
        rec_state = .Recording;
    }

    // FIXME: better new-frame checking that doesn't only account for tabbing out
    // i.e. also when pausing, physics frozen with ingame feature, etc.
    fn saveable(gs: *GlobalSt) bool {
        return gs.in_race.on() and rec_data.canSave();
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

    fn settingsInit(gf: *GlobalFn) void {
        s_h_section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "savestate", null);

        s_h_enable = gf.ASettingOccupy(s_h_section.?, "enable", .B, .{ .b = false }, &s_enable, null);
        s_h_load_delay = gf.ASettingOccupy(s_h_section.?, "load_delay", .U, .{ .u = 500 }, &s_load_delay, null);
    }
};

// LOADER LOGIC

fn DoStateRecording(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.saveable(gs))
        state.rec_data.save(gs.framecount);

    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.rec_data.frame - 1;
    }
    if (state.save_input_ld.gets() == .JustOn and state.rec_data.frames > 0) {
        state.load_time = state.s_load_delay + gs.timestamp;
        return .Loading;
    }

    return .Recording;
}

fn DoStateLoading(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.saveable(gs))
        state.rec_data.save(gs.framecount);

    if (state.save_input_ld.gets() == .JustOn) {
        state.scrub_frame = std.math.cast(i32, state.rec_data.frame).? - 1;
        state.rec_data.frame_total = state.rec_data.frame;
        return .Scrubbing;
    }

    if (gs.timestamp >= state.load_time) {
        if (!state.loadable(gs)) return .Recording;
        state.rec_data.restore(state.load_frame);
        state.load_count += 1;
        return .Recording;
    }

    return .Loading;
}

fn DoStateScrubbing(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.rec_data.frame - 1;
    }
    if (state.save_input_ld.gets() == .JustOn) {
        state.load_frame = @min(state.load_frame, std.math.cast(u32, state.scrub_frame).?);
        state.load_time = state.s_load_delay + gs.timestamp;
        state.rec_data.restore(std.math.cast(u32, state.scrub_frame).?);
        return .ScrubExiting;
    }

    state.scrub_frame = state.scrub.UpdateEx(
        state.scrub_frame,
        std.math.cast(i32, state.rec_data.frame_total).?,
        false,
    );

    if (!state.loadable(gs)) return .Scrubbing;
    state.rec_data.restore(std.math.cast(u32, state.scrub_frame).?);
    return .Scrubbing;
}

fn DoStateScrubExiting(gs: *GlobalSt, _: *GlobalFn) LoadState {
    if (state.loadable(gs))
        state.rec_data.restore(std.math.cast(u32, state.scrub_frame).?);

    if (state.save_input_st.gets() == .JustOn) {
        state.load_frame = state.rec_data.frame - 1;
    }

    if (gs.timestamp < state.load_time) return .ScrubExiting;

    state.load_count += 1;
    return .Recording;
}

fn UpdateState(gs: *GlobalSt, gv: *GlobalFn) void {
    if (!state.updateable(gs)) return;

    if (!state.initialized) {
        defer state.initialized = true;
        state.reset();
        state.rec_data.sources = state.rec_sources[0..];
        state.rec_data.init();
    }

    if (gs.race_state_new and gs.race_state == .PreRace)
        state.reset();

    if (gs.race_state != .Racing) return;

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
    state.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    state.rec_data.deinit();
}

// HOOKS

//export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
//    state.handle_settings(gf);
//}

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    state.scrub_input_dec.update(gf);
    state.scrub_input_inc.update(gf);
    state.save_input_st.update(gf);
    state.save_input_ld.update(gf);
}

export fn EngineEntityUpdateB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (!state.s_enable) return;

    UpdateState(gs, gf);
}

export fn Draw2DB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (!state.s_enable) return;

    // TODO: build checks for GHideRaceUIIsHidden into drawtext api when that's done
    // TODO: show during whole race scene? esp. if recording from count
    // TODO: experiment with positioning
    // TODO: experiment with conditionally showing each string; only show fr
    // if playing back, only show st if a frame is actually saved?
    if (gs.race_state == .Racing and !gf.GHideRaceUIIsOn()) {
        _ = gf.GDrawText(
            .OverlayP,
            rt.MakeText(16, 480 - 16, "Fr {d}", .{state.rec_data.frame}, null, null) catch null,
        );
        _ = gf.GDrawText(
            .OverlayP,
            rt.MakeText(92, 480 - 16, "St {d}", .{state.load_frame}, null, null) catch null,
        );
        if (state.load_count > 0)
            _ = gf.GDrawText(
                .OverlayP,
                rt.MakeText(168, 480 - 16, "Ld {d}", .{state.load_count}, null, null) catch null,
            );
    }
}
