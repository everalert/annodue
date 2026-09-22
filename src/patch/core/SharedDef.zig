const std = @import("std");

const ToggleState = @import("../util/toggle_state.zig").ToggleState;

const plugapi = @import("../util/plugin/plugin_api.zig");
const RaceState = plugapi.RaceState;
const HangState = plugapi.HangState;

pub const GLOBAL_STATE_VERSION = 10;

// TODO: move all the common game check stuff from plugins/modules to here; cleanup
// TODO: add index of currently consumed loaded tga IDs, since they are arbitrarily assigned
//   also, some kind of interface plugins can use to avoid clashes
//   list of stuff to update when it's made:
//     inputdisplay, practice mode vis, spare camstates used
pub const GlobalState = extern struct {
    init_late_passed: bool = false,
    practice_mode: bool = false,

    window_in_foreground: bool = true,

    //dt_f: f32 = 0,
    //fps: f32 = 0,
    fps_avg: f32 = 0,

    in_race: ToggleState = .Off,
    race_state: RaceState = .None,
    race_state_prev: RaceState = .None,
    race_state_new: bool = false,
    hang_state: HangState = .None,
    hang_state_prev: HangState = .None,
    hang_state_new: bool = false,
    player: extern struct {
        boosting: ToggleState = .Off,
        boost_charging: ToggleState = .Off,
        boost_ready: ToggleState = .Off,
        underheating: ToggleState = .On,
        overheating: ToggleState = .Off,
        dead: ToggleState = .Off,
        deaths: u32 = 0,
    } = .{},
};
