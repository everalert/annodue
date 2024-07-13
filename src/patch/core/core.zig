// this stuff was outside core and hooked in this order before making this file
pub const Hook = @import("Hook.zig");
pub const Input = @import("Input.zig");
pub const Settings = @import("Settings.zig");
pub const Global = @import("Global.zig");
pub const Practice = @import("Practice.zig");

// this stuff was inside core and hooked in this order before making this file
pub const Toast = @import("Toast.zig");
pub const Update = @import("Update.zig");
pub const Testing = @import("Testing.zig");

// this stuff was inside core before making this file, but didn't have any hook stuff
pub const Allocator = @import("Allocator.zig");
pub const Debug = @import("Debug.zig");
pub const Freeze = @import("Freeze.zig");
pub const HideRaceUI = @import("HideRaceUI.zig");
