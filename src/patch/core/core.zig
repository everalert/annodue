// TODO: revisit organisation, ordering
//  order must respect internal dependencies/assumptions about things already
//  being initialized
// NOTE: ASettings is sort of "cheating" by being initialized by main.zig before
//  Hook ever runs this stuff; need to straighten that out in the process of
//  making the core hot-reloadable. also, don't really like how the core alloc
//  is just thrown around, so that would be a good time to formalize that too

// this stuff needs to be first (ring 0)
pub const AMemory = @import("AMemory.zig");

// this stuff was outside core and hooked in this order before making this file
pub const AHook = @import("AHook.zig");
pub const Input = @import("Input.zig");
pub const ASettings = @import("ASettings.zig");
pub const Global = @import("Global.zig");
pub const Practice = @import("Practice.zig");

// this stuff was inside core and hooked in this order before making this file
pub const Toast = @import("Toast.zig");
pub const Update = @import("Update.zig");
pub const Testing = @import("Testing.zig");

// this stuff was inside core before making this file, but didn't have any hook stuff
//pub const Debug = @import("Debug.zig");

// FIXME: GAssetBuffer disabled because it was crashing due to unchecked undefined
//  behaviour related to something to do with the hot_reload implementation used
//  in ASettings; keeps breaking for seemingly no reason so must come back to this
//  and figure it out
// plugin-facing 'game' functions
//pub const GAssetBuffer = @import("GAssetBuffer.zig");
pub const Draw = @import("GDraw.zig");
pub const Freeze = @import("GFreeze.zig");
pub const HideRaceUI = @import("GHideRaceUI.zig");

// plugin-facing resources
pub const RTerrain = @import("RTerrain.zig");
pub const RTrigger = @import("RTrigger.zig");
