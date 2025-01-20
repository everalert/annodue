const std = @import("std");

// GAME TYPEDEFS

pub const BlockFileType = enum(u32) { Model, Sprite, Spline, Texture };

// GAME CONSTANTS

// *anyopaque here refers to c std FILE*
pub const pOpenSpriteBlockFile: **anyopaque = @ptrFromInt(0x4B958C);
pub const pOpenSplineBlockFile: **anyopaque = @ptrFromInt(0x4B9590);
pub const pOpenTextureBlockFile: **anyopaque = @ptrFromInt(0x4B9594);
pub const pOpenModelBlockFile: **anyopaque = @ptrFromInt(0x4B9598);

pub const TextureBuffer: *[1700]u32 = @ptrFromInt(0xE93860); // TODO: texture typedef
pub const TextureBlockCount: *u32 = @ptrFromInt(0xE9823C); // updated in TextureBuffer_Init

// GAME FUNCTIONS

pub const Block_UncompressData: *const fn ([*]u8, [*]u8) callconv(.C) void = @ptrFromInt(0x42D520);
pub const Block_GetLoadedFile: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D600);
pub const Block_Read: *const fn (BlockFileType, u32, [*]u8, u32) callconv(.C) void = @ptrFromInt(0x42D640);
pub const Block_Open: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D680);
pub const Block_Close: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D6F0);
pub const TextureBuffer_Init: *const fn () callconv(.C) void = @ptrFromInt(0x447420);
pub const TextureBuffer_LoadModelTexture: *const fn () callconv(.C) void = @ptrFromInt(0x447490);
pub const TextureBuffer_ClearBufferAfterPtr: *const fn () callconv(.C) void = @ptrFromInt(0x4475D0);

// HELPERS

// ...
