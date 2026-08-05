const TGA = @This();

const std = @import("std");
const assert = std.debug.assert;
const Writer = std.io.Writer;
const Reader = std.io.Reader;

// TGA 2.2
// NOTE: just implementing enough to write basic uncompressed images for now

// https://en.wikipedia.org/wiki/Truevision_TGA
// http://www.paulbourke.net/dataformats/tga/
// https://www.loc.gov/preservation/digital/formats/fdd/fdd000180.shtml

// HEADER

//ID: ?[]const u8 = null,

// color map spec
//ColorMapType: u8 = 0,
//ColorMapOrigin: u16 = 0,
//ColorMapLength: u16 = 0,
//ColorMapDepth: u8 = 0,

// image spec
ImageType: packed struct(u8) {
    DataType: enum(u3) { None, ColorMapped, TrueColor, Grayscale } = .TrueColor,
    RLE: bool = false,
    _4: u4 = 0,
} = .{},
//ImageXOrigin: u16 = 0,
//ImageYOrigin: u16 = 0,
ImageWidth: u16 = 0,
ImageHeight: u16 = 0,
ImageBPP: u8 = 24,
ImageDescriptor: packed struct(u8) {
    BPPAlpha: u4 = 0,
    BeginRight: bool = false, // right-to-left
    BeginTop: bool = true, // top-to-bottom
    _6_unused: u2 = 0,
} = .{},

// footer
//ExtensionAreaOffset: u32 = 0,
//DeveloperDirectoryOffset: u32 = 0,

// ...

pub fn WriteHeader(self: *TGA, writer: anytype) !void {
    // assert(!self.StWrittenHeader);
    // self.StWrittenHeader = true;

    try writer.writeIntLittle(u8, 0); // IDLength
    try writer.writeIntLittle(u8, 0); // ColorMapType
    try writer.writeStruct(self.ImageType);
    try writer.writeIntLittle(u16, 0); // ColorMapOrigin
    try writer.writeIntLittle(u16, 0); // ColorMapLength
    try writer.writeIntLittle(u8, 0); // ColorMapDepth
    try writer.writeIntLittle(u16, 0); // ImageXOrigin
    try writer.writeIntLittle(u16, 0); // ImageYOrigin
    try writer.writeIntLittle(u16, self.ImageWidth);
    try writer.writeIntLittle(u16, self.ImageHeight);
    try writer.writeIntLittle(u8, self.ImageBPP);
    try writer.writeStruct(self.ImageDescriptor);
}

pub fn WriteID(self: *TGA, writer: anytype) !void {
    _ = self;
    _ = writer;
    assert(false); // not supported
}

pub fn WriteColorMap(self: *TGA, writer: anytype) !void {
    _ = self;
    _ = writer;
    assert(false); // not supported
}

pub fn WriteFooter(self: *TGA, writer: anytype) !void {
    _ = self;
    try writer.writeIntLittle(u32, 0); // ExtensionAreaOffset
    try writer.writeIntLittle(u32, 0); // DeveloperDirectoryOffset
    _ = try writer.write("TRUEVISION-XFILE");
    try writer.writeByte('.');
    try writer.writeByte(0);
}

// helpers

pub fn WriteGrey8(writer: anytype, pixels: []const u8, width: u16, height: u16) !void {
    assert(pixels.len == width * height);
    var tga = TGA{
        .ImageType = .{ .DataType = .Grayscale },
        .ImageWidth = width,
        .ImageHeight = height,
        .ImageBPP = 8,
    };
    try tga.WriteHeader(writer);
    // try tga.WriteID(writer);
    // try tga.WriteColorMap(writer);
    _ = try writer.write(pixels);
    try tga.WriteFooter(writer);
}
