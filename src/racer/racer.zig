// TODO: codebase - go through codebase and migrate any direct racer address usage into here
// TODO: codebase - cleanup usage of this module; remove dead imports, etc.
// TODO: this module - adding typedefs, then migrating usage in codebase where appropriate
// TODO: this module - naming pattern for helper stuff to help intellisense, e.g. HSomeHelperFn()

pub const Global = @import("Global.zig");

pub const RaceData = @import("RaceData.zig");
pub const Entity = @import("Entity/entity.zig");

pub const Time = @import("Time.zig");
pub const File = @import("File.zig");
pub const Save = @import("Save.zig");
pub const Debug = @import("Debug.zig");

pub const Random = @import("Random.zig");
pub const Vector = @import("Vector.zig");
pub const Matrix = @import("Matrix.zig");

pub const Input = @import("Input.zig");
pub const Sound = @import("Sound.zig");
pub const Video = @import("Video.zig");
pub const Quad = @import("Quad.zig");
pub const Text = @import("Text.zig");
pub const Font = @import("Font.zig");
pub const Model = @import("Model.zig");
pub const Asset = @import("Asset.zig");
pub const @"3D" = @import("3D.zig");

pub const Camera = @import("Camera.zig");
pub const Vehicle = @import("Vehicle.zig");
pub const Track = @import("Track.zig");
