const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const rs = @import("racer").Sound;

// FEATURES
// - visualize collision faces
// - visualize collision mesh
// - visualize spline
// - CONTROLS:              keyboard        xinput
//   Open menu              9               ..
//   Toggle visualization   8               ..
// - SETTINGS:              type            note
//   depth_bias             i32             for aligining collision models with ingame models correctly

const PLUGIN_NAME: [*:0]const u8 = "PluginCollisionViewer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const win = std.os.windows;
const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;

const debug = @import("core/Debug.zig");

const timing = @import("util/timing.zig");
const Menu = @import("util/menu.zig").Menu;
const InputGetFnType = @import("util/menu.zig").InputGetFnType;
const mi = @import("util/menu_item.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");
const st = @import("util/active_state.zig");

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;

var input_enable_data = ButtonInputMap{ .kb = .@"8", .xi = null };
var input_enable = input_enable_data.inputMap();

var input_pause_data = ButtonInputMap{ .kb = .@"9", .xi = null };
var input_pause = input_pause_data.inputMap();

const c = @cImport({
    @cInclude("collision_viewer.h");
});
const CollisionViewerSettings = c.CollisionViewerSettings;
const CollisionViewerState = c.CollisionViewerState;

var presets: [5]CollisionViewerSettings = .{
    .{
        .show_visual_mesh = true,
        .collision_mesh_opacity = 0.3,
        .collision_mesh_brightness = 1.0,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = true,
        .cull_backfaces = true,
    },
    .{
        .show_visual_mesh = true,
        .collision_mesh_opacity = 0.0,
        .collision_mesh_brightness = 1.0,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = true,
        .cull_backfaces = true,
    },
    .{
        .show_visual_mesh = false,
        .collision_mesh_opacity = 1.0,
        .collision_mesh_brightness = 0.5,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = true,
        .cull_backfaces = true,
    },
    .{
        .show_visual_mesh = false,
        .collision_mesh_opacity = 0.2,
        .collision_mesh_brightness = 1.0,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = false,
        .cull_backfaces = false,
    },
    .{
        .show_visual_mesh = false,
        .collision_mesh_opacity = 0.2,
        .collision_mesh_brightness = 1.0,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = false,
        .cull_backfaces = false,
    },
};
const preset_names = [_][*:0]const u8{
    "transparent overlay",
    "wireframe overlay",
    "collision mesh only",
    "transparent collision mesh only",
    "[custom]",
};

var state: CollisionViewerState = .{
    .enabled = false,
    .show_collision_mesh = true,
    .settings = .{
        .show_visual_mesh = true,
        .collision_mesh_opacity = 0.3,
        .collision_mesh_brightness = 1.0,
        .collision_line_opacity = 1.0,
        .collision_line_brightness = 1.0,
        .depth_test = true,
        .cull_backfaces = true,
    },
    .depth_bias = 0.1,
    .show_spline = false,
};
var preset_index: i32 = 0;

// QUICK RACE MENU

const QuickRaceMenuInput = extern struct {
    kb: VIRTUAL_KEY,
    xi: XINPUT_GAMEPAD_BUTTON_INDEX,
    state: st.ActiveState = undefined,
};

const ConvertedMenuItem = struct {
    input_bool: ?*bool = null,
    input_float: ?*f32 = null,
    input_converted: i32 = 0,

    fn before_update(self: *ConvertedMenuItem) void {
        if (self.input_bool != null) self.input_converted = if (self.input_bool.?.*) 1 else 0;
        if (self.input_float != null) self.input_converted = @intFromFloat(std.math.round(self.input_float.?.* * 100));
    }

    fn after_update(self: *ConvertedMenuItem) void {
        if (self.input_bool != null) self.input_bool.?.* = self.input_converted != 0;
        if (self.input_float != null) {
            self.input_float.?.* = @floatFromInt(self.input_converted);
            self.input_float.?.* /= 100.0;
        }
    }
};

const QuickRaceMenu = extern struct {
    const menu_key: [*:0]const u8 = "CollisionViewerMenu";
    var menu_active: bool = false;
    var initialized: bool = false;
    // TODO: figure out if these can be removed, currently blocked by quick race menu callbacks
    var gs: *GlobalSt = undefined;
    var gf: *GlobalFn = undefined;

    var inputs = [_]QuickRaceMenuInput{
        .{ .kb = .UP, .xi = .DPAD_UP },
        .{ .kb = .DOWN, .xi = .DPAD_DOWN },
        .{ .kb = .LEFT, .xi = .DPAD_LEFT },
        .{ .kb = .RIGHT, .xi = .DPAD_RIGHT },
        .{ .kb = .SPACE, .xi = .A }, // confirm
        .{ .kb = .RETURN, .xi = .B }, // quick confirm
        .{ .kb = .HOME, .xi = .LEFT_SHOULDER }, // NU
        .{ .kb = .END, .xi = .RIGHT_SHOULDER }, // MU
    };

    fn get_input(comptime input: *QuickRaceMenuInput) InputGetFnType {
        const s = struct {
            fn gi(i: st.ActiveState) callconv(.C) bool {
                return input.state == i;
            }
        };
        return &s.gi;
    }

    inline fn update_input() void {
        for (&inputs) |*i|
            i.state.update(gf.InputGetKbRaw(i.kb).on() or gf.InputGetXInputButton(i.xi).on());
    }

    var data: Menu = .{
        .title = "Collision Viewer",
        .items = .{ .it = @ptrCast(&QuickRaceMenuItems), .len = QuickRaceMenuItems.len },
        .inputs = .{
            .cb = &[_]InputGetFnType{
                get_input(&inputs[4]), get_input(&inputs[5]),
                get_input(&inputs[6]), get_input(&inputs[7]),
            },
            .len = 3,
        },
        .callback = CollisionViewerCallback,
        .y_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input(&inputs[0]),
            .input_inc = get_input(&inputs[1]),
        },
        .x_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input(&inputs[2]),
            .input_inc = get_input(&inputs[3]),
        },
        .col_w = 200,
    };

    var QuickRaceMenuItems = [_]mi.MenuItem{
        mi.MenuItemToggle(&QuickRaceMenu.item_enabled.input_converted, "Enable viewer"),
        mi.MenuItemToggle(&QuickRaceMenu.item_show_collision_mesh.input_converted, "Show collision mesh"),
        mi.MenuItemToggle(&QuickRaceMenu.item_show_visual_mesh.input_converted, "Show visual mesh"),
        mi.MenuItemToggle(&QuickRaceMenu.item_show_spline.input_converted, "Show spline"),
        mi.MenuItemList(&preset_index, "Preset", &preset_names, false, null),
        mi.MenuItemSpacer(),
        mi.MenuItemRange(&QuickRaceMenu.item_mesh_opacity.input_converted, "Collision mesh opacity", 0, 100, false, null),
        mi.MenuItemRange(&QuickRaceMenu.item_mesh_brightness.input_converted, "Collision mesh brightness", 0, 100, false, null),
        mi.MenuItemRange(&QuickRaceMenu.item_line_opacity.input_converted, "Collision line opacity", 0, 100, false, null),
        mi.MenuItemRange(&QuickRaceMenu.item_line_brightness.input_converted, "Collision line brightness", 0, 100, false, null),
        mi.MenuItemSpacer(),
        mi.MenuItemToggle(&QuickRaceMenu.item_depth_test.input_converted, "Depth test"),
        mi.MenuItemToggle(&QuickRaceMenu.item_cull_backfaces.input_converted, "Cull backfaces"),
        mi.MenuItemRange(&QuickRaceMenu.item_depth_bias.input_converted, "Depth bias", -100, 100, false, null),
    };

    var item_enabled = ConvertedMenuItem{ .input_bool = &state.enabled };
    var item_show_collision_mesh = ConvertedMenuItem{ .input_bool = &state.show_collision_mesh };
    var item_show_visual_mesh = ConvertedMenuItem{ .input_bool = &state.settings.show_visual_mesh };
    var item_mesh_opacity = ConvertedMenuItem{ .input_float = &state.settings.collision_mesh_opacity };
    var item_mesh_brightness = ConvertedMenuItem{ .input_float = &state.settings.collision_mesh_brightness };
    var item_line_opacity = ConvertedMenuItem{ .input_float = &state.settings.collision_line_opacity };
    var item_line_brightness = ConvertedMenuItem{ .input_float = &state.settings.collision_line_brightness };
    var item_depth_test = ConvertedMenuItem{ .input_bool = &state.settings.depth_test };
    var item_cull_backfaces = ConvertedMenuItem{ .input_bool = &state.settings.cull_backfaces };
    var item_depth_bias = ConvertedMenuItem{ .input_float = &state.depth_bias };
    var item_show_spline = ConvertedMenuItem{ .input_bool = &state.show_spline };

    var all_items = [_]*ConvertedMenuItem{
        &item_enabled,
        &item_show_collision_mesh,
        &item_show_visual_mesh,
        &item_mesh_opacity,
        &item_mesh_brightness,
        &item_line_opacity,
        &item_line_brightness,
        &item_depth_test,
        &item_cull_backfaces,
        &item_depth_bias,
        &item_show_spline,
    };

    fn init() void {
        initialized = true;
    }

    fn open() void {
        if (!gf.GameFreezeEnable(menu_key)) return;
        rs.swrSound_PlaySound(78, 6, 0.25, 1.0, 0);
        data.idx = 0;
        menu_active = true;
    }

    fn close() void {
        if (!gf.GameFreezeDisable(menu_key)) return;
        rs.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        menu_active = false;
    }

    fn update() void {
        if (gs.in_race == .JustOn)
            init();

        if (!initialized or !gs.practice_mode or !gs.in_race.on()) {
            state.enabled = false;
            return;
        }

        if (input_enable.gets() == .JustOn)
            state.enabled = !state.enabled;

        if (input_pause.gets() == .JustOn) {
            if (menu_active) close() else open();
        }

        if (menu_active) {
            var current_preset: i32 = -1;

            for (presets[0 .. presets.len - 1], 0..) |preset, index| {
                if (std.meta.eql(preset, state.settings))
                    current_preset = @intCast(index);
            }
            if (current_preset == -1) {
                presets[presets.len - 1] = state.settings;
                current_preset = @intCast(presets.len - 1);
            }

            preset_index = current_preset;

            for (all_items) |item|
                item.before_update();

            data.UpdateAndDraw();

            for (all_items) |item|
                item.after_update();

            if (preset_index != current_preset)
                state.settings = presets[@intCast(preset_index)];
        }
    }
};

fn CollisionViewerCallback(m: *Menu) callconv(.C) bool {
    var result = false;
    _ = m;
    return result;
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

extern fn init_collision_viewer(gs: *CollisionViewerState) callconv(.C) void;
extern fn deinit_collision_viewer() callconv(.C) void;

fn handle_settings(gf: *GlobalFn) callconv(.C) void {
    var biasInt: i32 = gf.SettingGetI("collisionviewer", "depth_bias") orelse 10;
    var biasFloat: f32 = @floatFromInt(biasInt);
    state.depth_bias = biasFloat / 100.0;
}

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    handle_settings(gf);

    init_collision_viewer(&state);

    QuickRaceMenu.gs = gs;
    QuickRaceMenu.gf = gf;
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    QuickRaceMenu.close();
    deinit_collision_viewer();
    _ = gf;
    _ = gs;
}

// HOOKS

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    input_enable.update(gf);
    input_pause.update(gf);
    QuickRaceMenu.update_input();
}

export fn EarlyEngineUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    _ = gs;
    QuickRaceMenu.update();
}
