// TODO: revisit organisation, ordering

// this stuff was outside core and hooked in this order before making this file
pub const Hook = @import("Hook.zig");
pub const Input = @import("Input.zig");
pub const ASettings = @import("ASettings.zig");
pub const Global = @import("Global.zig");
pub const Practice = @import("Practice.zig");

// this stuff was inside core and hooked in this order before making this file
pub const Toast = @import("Toast.zig");
pub const Update = @import("Update.zig");
pub const Testing = @import("Testing.zig");

// this stuff was inside core before making this file, but didn't have any hook stuff
pub const Allocator = @import("Allocator.zig");
pub const Debug = @import("Debug.zig");

// plugin-facing 'game' functions
pub const Draw = @import("GDraw.zig");
pub const Freeze = @import("GFreeze.zig");
pub const HideRaceUI = @import("GHideRaceUI.zig");

// plugin-facing resources
pub const RTerrain = @import("RTerrain.zig");
pub const RTrigger = @import("RTrigger.zig");
