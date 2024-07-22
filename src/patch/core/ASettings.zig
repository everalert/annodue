const std = @import("std");

const EnumSet = std.EnumSet;
const Allocator = std.mem.Allocator;
const bufPrintZ = std.fmt.bufPrintZ;

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;
const coreAllocator = @import("Allocator.zig").allocator;

const HandleMapSOA = @import("../util/handle_map_soa.zig").HandleMapSOA;
const HandleSOA = @import("../util/handle_map_soa.zig").Handle;

const r = @import("racer");
const rt = r.Text;

const SentSetting = extern struct {
    name: [*:0]u8,
    value: Value,

    const Value = extern union { str: [*:0]u8, f: f32, u: u32, i: i32, b: bool };
};

const Setting = struct {
    section: ?struct { generation: u16, index: u16 } = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    value: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_default: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_saved: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_type: Type = .NotSet,
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (value: SentSetting.Value) callconv(.C) void = null,

    const Handle = HandleSOA(u16);
    const Type = enum(u8) { NotSet, Str, F, U, I, B };
    const Value = extern union { str: [63:0]u8, f: f32, u: u32, i: i32, b: bool };
    const Flags = enum(u32) {
        InFile,
        FileUpdated,
        ChangedSinceLastRead,
        ProcessedSinceLastRead, // marker to let you know, e.g. don't unset ChangedSinceLastRead
        HasOwner,
    };

    inline fn sent2setting(setting: SentSetting.Value) Value {
        _ = setting;
    }
};

// reserved settings: AutoSave, UseGlobalAutoSave
const Section = struct {
    section: ?struct { generation: u16, index: u16 } = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (changed: [*]SentSetting) callconv(.C) void = null,

    const Handle = HandleSOA(u16);
    const Flags = enum(u32) {
        AutoSave,
        HasOwner,
    };
};

// reserved global settings: AutoSave
const ASettings = struct {
    var data_sections: HandleMapSOA(Section, u16) = undefined;
    var data_settings: HandleMapSOA(Setting, u16) = undefined;
    flags: EnumSet(Flags),

    const Flags = enum(u32) {
        AutoSave,
    };

    pub fn init(alloc: Allocator) void {
        data_sections = HandleMapSOA(Section, u16).init(alloc);
        data_settings = HandleMapSOA(Setting, u16).init(alloc);
        // TODO: load from file
    }

    pub fn deinit() void {
        // TODO: save to file if needed
        data_sections.deinit();
        data_settings.deinit();
    }

    pub inline fn nodeExists(
        map: anytype, // handle_map_*
        parent: ?Section.Handle,
        name: [*:0]const u8,
    ) bool {
        if (parent != null and !data_sections.hasHandle(parent.?)) return false;

        const name_len = std.mem.len(name) + 1; // include sentinel
        const slices = map.values.slice();
        const slices_names = slices.items(.name);
        const slices_sections = slices.items(.section);
        for (slices_names, slices_sections) |s_name, *s_section| {
            if (parent == null and s_section.* != null)
                continue;
            if (parent != null and !std.mem.eql(u8, std.mem.asBytes(s_section), std.mem.asBytes(&parent)))
                continue;
            if (!std.mem.eql(u8, s_name[0..name_len], name[0..name_len]))
                continue;
            return true;
        }

        return false;
    }

    pub fn sectionNew(
        section: ?Section.Handle,
        name: [*:0]const u8,
    ) !Section.Handle {
        if (section != null and !data_sections.hasHandle(section.?)) return error.SectionDoesNotExist;
        const owner: u16 = if (section) |s| s.owner else 0xFFFF; // TODO: change default to ASettings' id?

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeExists(data_sections, section, name)) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&section_new.name, "{s}", .{name});

        return try data_sections.insert(owner, section_new);
    }

    pub fn settingNew(
        section: ?Section.Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> value_saved
        from_file: bool,
    ) !Setting.Handle {
        if (section != null and !data_sections.hasHandle(section.?)) return error.SectionDoesNotExist;
        const owner: u16 = if (section) |s| s.owner else 0xFFFF; // TODO: change default to ASettings' id?

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeExists(data_settings, section, name)) return error.NameTaken;

        const value_len = std.mem.len(value);
        if (value_len == 0 or value_len > 63) return error.ValueLengthInvalid;

        var setting = Setting{};
        if (section) |s| setting.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&setting.name, "{s}", .{name});
        _ = try bufPrintZ(&setting.value.str, "{s}", .{value});
        if (from_file) {
            _ = try bufPrintZ(&setting.value_saved.str, "{s}", .{value});
            setting.flags.insert(.InFile);
        }

        return try data_settings.insert(owner, setting);
    }

    //pub fn settingRegister(
    //    owner: u16,
    //    section: ?Section.Handle,
    //    name: [*:0]const u8,
    //    value_type: Setting.Type,
    //    value_default: SentSetting.Value,
    //    callback: ?*const fn (SentSetting) callconv(.C) void,
    //) Setting.Handle {}

    pub fn iniParse() void {}
    pub fn iniWrite() void {}
    //pub fn jsonParse() void {}
    //pub fn jsonWrite() void {}
    pub fn cleanupSave() void {} // remove settings from file not defined by a plugin etc.
    pub fn saveAuto(_: ?Section.Handle) void {}
    pub fn save(_: ?Section.Handle) void {}
    pub fn sort() void {}
};

// GLOBAL EXPORTS

// ...

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    ASettings.init(coreAllocator());

    // TODO: move below to testing

    const sec1 = ASettings.sectionNew(null, "Sec1") catch Setting.Handle.getNull();
    const sec2 = ASettings.sectionNew(null, "Sec2") catch Setting.Handle.getNull();
    _ = ASettings.sectionNew(null, "Sec2") catch {}; // expect: NameTaken error -> skipped

    _ = ASettings.settingNew(sec1, "Set1", "Val1", false) catch {};
    _ = ASettings.settingNew(null, "Set2", "Val2", false) catch {};
    _ = ASettings.settingNew(sec2, "Set3", "Val3", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val4", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    _ = ASettings.settingNew(null, "Set5", "Val5", false) catch {};
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    ASettings.deinit();
}

//pub fn OnPluginDeinit(_: u16) callconv(.C) void {}

// FIXME: remove, for testing
// TODO: maybe adapt for debug/testing
pub fn Draw2DB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf.GDrawRect(.Debug, 0, 0, 320, 480, 0x000000A0);
    var y: i16 = 0;

    for (0..ASettings.data_settings.values.len) |i| {
        const value = ASettings.data_settings.values.get(i);
        if (value.section != null) continue;
        _ = gf.GDrawText(.Debug, rt.MakeText(0, y, "{s}", .{value.name}, null, null) catch null);
        _ = gf.GDrawText(.Debug, rt.MakeText(128, y, "{s}", .{value.value.str}, null, null) catch null);
        y += 8;
    }

    for (0..ASettings.data_sections.values.len) |i| {
        const value = ASettings.data_sections.values.get(i);
        const handle = ASettings.data_sections.handles.items[i];
        _ = gf.GDrawText(.Debug, rt.MakeText(0, y, "{s}", .{value.name}, null, null) catch null);
        y += 8;

        for (0..ASettings.data_settings.values.len) |j| {
            const s_value = ASettings.data_settings.values.get(j);
            const section = s_value.section;
            if (section == null or handle.generation != section.?.generation or handle.index != section.?.index)
                continue;
            _ = gf.GDrawText(.Debug, rt.MakeText(12, y, "{s}", .{s_value.name}, null, null) catch null);
            _ = gf.GDrawText(.Debug, rt.MakeText(128, y, "{s}", .{s_value.value.str}, null, null) catch null);
            y += 8;
        }
    }
}

// TODO: impl testing in build script; cannot test statically because imports out of scope
// TODO: move testing stuff to here but commented in meantime
test {
    // ...
}
