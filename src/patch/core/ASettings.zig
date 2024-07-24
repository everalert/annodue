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

// FIXME: remove, for testing
const dbg = @import("../util/debug.zig");

const Handle = HandleSOA(u16);
const NullHandle = Handle.getNull();

const SentSetting = extern struct {
    name: [*:0]u8,
    value: Value,

    const Value = extern union {
        str: [*:0]u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        pub inline fn fromSetting(setting: *Setting.Value, t: Setting.Type) Value {
            return switch (t) {
                .Str => .{ .str = &setting.str },
                .F => .{ .f = setting.f },
                .U => .{ .u = setting.u },
                .I => .{ .i = setting.i },
                .B => .{ .b = setting.b },
                else => @panic("setting value type must not be None"),
            };
        }
    };
};

const Setting = struct {
    section: ?struct { generation: u16, index: u16 } = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    value: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_default: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_saved: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_type: Type = .None,
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (value: SentSetting.Value) callconv(.C) void = null,

    const Type = enum(u8) { None, Str, F, U, I, B };

    const Value = extern union {
        str: [63:0]u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        pub inline fn set(self: *Value, v: SentSetting.Value, t: Type) !void {
            switch (t) {
                .Str => _ = try bufPrintZ(&self.str, "{s}", .{v.str}),
                .F => self.f = v.f,
                .U => self.u = v.u,
                .I => self.i = v.i,
                .B => self.b = v.b,
                else => @panic("setting value type must not be None"),
            }
        }

        pub inline fn get(self: *Value, t: Type) Value {
            return switch (t) {
                .Str => self.str,
                .F => self.f,
                .U => self.u,
                .I => self.i,
                .B => self.b,
                else => @panic("setting value type must not be None"),
            };
        }

        // raw (string) to value
        pub inline fn raw2type(self: *Value, t: Type) !void {
            const len = std.mem.len(@as([*:0]u8, @ptrCast(&self.str)));
            switch (t) {
                .B => self.b = std.mem.eql(u8, "on", self.str[0..2]) or
                    std.mem.eql(u8, "true", self.str[0..4]) or
                    self.str[0] == '1',
                .I => self.i = try std.fmt.parseInt(i32, self.str[0..len], 10),
                .U => self.u = try std.fmt.parseInt(u32, self.str[0..len], 10),
                .F => self.f = try std.fmt.parseFloat(f32, self.str[0..len]),
                .Str => {},
                else => @panic("setting output value type must not be None"),
            }
        }

        // FIXME: could overflow buffer
        // value to raw (string)
        pub inline fn type2raw(self: *Value, t: Type) !void {
            switch (t) {
                .B => _ = try bufPrintZ(&self.str, "{s}", .{if (self.b) "on" else "off"}),
                .I => _ = try bufPrintZ(&self.str, "{d}", .{self.i}),
                .U => _ = try bufPrintZ(&self.str, "{d}", .{self.u}),
                .F => _ = try bufPrintZ(&self.str, "{d:4.2}", .{self.f}),
                .Str => {},
                else => @panic("setting input value type must not be None"),
            }
        }

        pub inline fn type2type(self: *Value, t1: Type, t2: type) !void {
            try self.type2raw(t1);
            try self.raw2type(t2);
        }
    };

    const Flags = enum(u32) {
        FileUpdated,
        ChangedSinceLastRead,
        ProcessedSinceLastRead, // marker to let you know, e.g. don't unset ChangedSinceLastRead
        HasOwner,
        ValueIsSet,
        ValueNotConverted,
        SavedValueIsSet,
        SavedValueNotConverted,
        DefaultValueIsSet,
        DefaultValueNotConverted,
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

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub inline fn nodeFind(
        map: anytype, // handle_map_*
        parent: ?Handle,
        name: [*:0]const u8,
    ) ?u16 {
        if (parent != null and !data_sections.hasHandle(parent.?)) return null;

        const name_len = std.mem.len(name) + 1; // include sentinel
        const slices = map.values.slice();
        const slices_names = slices.items(.name);
        const slices_sections = slices.items(.section);
        for (slices_names, slices_sections, 0..) |s_name, *s_section, i| {
            if ((parent == null) != (s_section.* == null))
                continue;
            if (parent != null and
                (parent.?.generation != s_section.*.?.generation or
                parent.?.index != s_section.*.?.index))
                //if (parent != null and !std.mem.eql(u8, std.mem.asBytes(s_section), std.mem.asBytes(&parent)))
                continue;
            if (!std.mem.eql(u8, s_name[0..name_len], name[0..name_len]))
                continue;
            return @intCast(i);
        }

        return null;
    }

    pub fn sectionNew(
        section: ?Handle,
        name: [*:0]const u8,
    ) !Handle {
        if (section != null and !data_sections.hasHandle(section.?)) return error.SectionDoesNotExist;
        const owner: u16 = if (section) |s| s.owner else 0xFFFF; // TODO: change default to ASettings' id?

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeFind(data_sections, section, name) != null) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&section_new.name, "{s}", .{name});

        return try data_sections.insert(owner, section_new);
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub fn settingNew(
        section: ?Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> value_saved
        from_file: bool,
    ) !Handle {
        if (section != null and !data_sections.hasHandle(section.?)) return error.SectionDoesNotExist;
        const owner: u16 = if (section) |s| s.owner else 0xFFFF; // TODO: change default to ASettings' id?

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeFind(data_settings, section, name) != null) return error.NameTaken;

        const value_len = std.mem.len(value);
        if (value_len == 0 or value_len > 63) return error.ValueLengthInvalid;

        var setting = Setting{};
        if (section) |s| setting.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&setting.name, "{s}", .{name});
        _ = try bufPrintZ(&setting.value.str, "{s}", .{value});
        setting.flags.insert(.ValueIsSet);
        if (from_file) {
            _ = try bufPrintZ(&setting.value_saved.str, "{s}", .{value});
            setting.flags.insert(.SavedValueIsSet);
        }

        return try data_settings.insert(owner, setting);
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub fn settingOccupy(
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        value_type: Setting.Type,
        value_default: Setting.Value,
        fnOnChange: ?*const fn (SentSetting.Value) callconv(.C) void,
    ) !Handle {
        std.debug.assert(value_type != .None);

        const existing_i = nodeFind(data_settings, section, name);

        var data: Setting = Setting{};
        if (existing_i) |i| {
            if (data_settings.handles.items[i].owner != 0xFFFF) return error.SettingAlreadyOwned;
            data = data_settings.values.get(i);
        } else {
            data.section = if (section) |s| .{ .generation = s.generation, .index = s.index } else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        // NOTE: existing data assumed to be raw (new, unprocessed or released)
        if (data.flags.contains(.ValueIsSet)) {
            data.value.raw2type(value_type) catch {
                data.value = value_default; // invalid data = use default, will be cleaned next file write
            };
            if (data.flags.contains(.SavedValueIsSet))
                data.value_saved.raw2type(value_type) catch {
                    data.flags.insert(.SavedValueNotConverted);
                };
        } else {
            data.value = value_default;
            data.flags.insert(.ValueIsSet);
        }
        data.value_type = value_type;
        data.value_default = value_default;
        data.flags.insert(.DefaultValueIsSet);
        data.fnOnChange = fnOnChange;
        if (fnOnChange) |f|
            f(SentSetting.Value.fromSetting(&data.value, data.value_type));

        if (existing_i) |i| {
            data_settings.values.set(i, data);
            data_settings.handles.items[i].owner = owner;
            data_settings.sparse_indices.items[i].owner = owner;
            return data_settings.handles.items[i];
        } else {
            return data_settings.insert(owner, data);
        }
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub fn settingRelease(
        handle: Handle,
    ) void {
        var data: Setting = data_settings.get(handle) orelse return;
        std.debug.assert(data.flags.contains(.ValueIsSet));

        data.fnOnChange = null;

        data.value_default = .{ .str = std.mem.zeroes([63:0]u8) };
        data.flags.remove(.DefaultValueIsSet);

        data.value.type2raw(data.value_type) catch @panic("settingRelease: 'value' invalid");
        if (!data.flags.contains(.SavedValueNotConverted))
            data.value_saved.type2raw(data.value_type) catch @panic("settingRelease: 'value_saved' invalid");
        data.flags.remove(.SavedValueNotConverted);

        data.value_type = .None;

        data_settings.handles.items[handle.index].owner = 0xFFFF;
        data_settings.sparse_indices.items[handle.index].owner = 0xFFFF;
        data_settings.values.set(handle.index, data);
    }

    // TODO: ValueUpdated flag?
    pub fn settingUpdate(
        handle: Handle,
        value: SentSetting.Value,
    ) void {
        var data: Setting = data_settings.get(handle) orelse return;
        data.value.set(value, data.value_type) catch return;
        data_settings.values.set(handle.index, data);
        if (data.fnOnChange) |f|
            f(value);
    }

    // TODO: dumping stuff i might need here
    pub fn iniParse() void {}
    pub fn iniWrite() void {}
    pub fn jsonParse() void {}
    pub fn jsonWrite() void {}
    pub fn cleanupSave() void {} // remove settings from file not defined by a plugin etc.
    pub fn cleanupSaveOccupiedSectionsOnly() void {} // leave 'junk' data on file for unloaded sections
    pub fn saveAuto(_: ?Handle) void {}
    pub fn save(_: ?Handle) void {}
    pub fn sort() void {}
};

// GLOBAL EXPORTS

// ...

// HOOKS

// TODO: add global st/fn ptrs to fnOnChange def?
fn updateSet1(value: SentSetting.Value) callconv(.C) void {
    dbg.ConsoleOut("set1 changed to {d:4.2}\n", .{value.f}) catch {};
}

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    ASettings.init(coreAllocator());

    // TODO: move below to testing

    const sec1 = ASettings.sectionNew(null, "Sec1") catch Handle.getNull();
    const sec2 = ASettings.sectionNew(null, "Sec2") catch Handle.getNull();
    _ = ASettings.sectionNew(null, "Sec2") catch {}; // expect: NameTaken error -> skipped

    _ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    _ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    _ = ASettings.settingNew(null, "Set2", "Val2", false) catch {};
    _ = ASettings.settingNew(sec2, "Set3", "Val3", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val4", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    _ = ASettings.settingNew(null, "Set5", "Val5", false) catch {};

    const occ1 = ASettings.settingOccupy(0x0000, sec1, "Set1", .F, .{ .f = 987.654 }, updateSet1) catch NullHandle;
    _ = ASettings.settingOccupy(0x0000, sec1, "Set1", .F, .{ .f = 987.654 }, null) catch {}; // expect: ignored
    const occ2 = ASettings.settingOccupy(0x0000, null, "Set6", .F, .{ .f = 987.654 }, null) catch NullHandle;
    _ = ASettings.settingOccupy(0x0000, null, "Set6", .F, .{ .f = 876.543 }, null) catch {}; // export: ignored

    ASettings.settingUpdate(occ1, .{ .f = 678.543 }); // expect: changed value
    ASettings.settingRelease(occ2); // expect: undefined default, etc.
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    ASettings.deinit();
}

//pub fn OnPluginDeinit(_: u16) callconv(.C) void {}

// FIXME: remove, for testing
// TODO: maybe adapt for debug/testing
pub fn Draw2DB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf.GDrawRect(.Debug, 0, 0, 400, 480, 0x000000A0);
    var y: i16 = 0;

    for (0..ASettings.data_settings.values.len) |i| {
        const value: Setting = ASettings.data_settings.values.get(i);
        if (value.section != null) continue;
        _ = gf.GDrawText(.Debug, rt.MakeText(0, y, "{s}", .{value.name}, null, null) catch null);
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.MakeText(100, y, "{any}", .{value.value.b}, null, null) catch null,
            .F => rt.MakeText(100, y, "{d:4.2}", .{value.value.f}, null, null) catch null,
            .U => rt.MakeText(100, y, "{d}", .{value.value.u}, null, null) catch null,
            .I => rt.MakeText(100, y, "{d}", .{value.value.i}, null, null) catch null,
            else => rt.MakeText(100, y, "{s}", .{value.value.str}, null, null) catch null,
        });
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.MakeText(200, y, "{any}", .{value.value_default.b}, null, null) catch null,
            .F => rt.MakeText(200, y, "{d:4.2}", .{value.value_default.f}, null, null) catch null,
            .U => rt.MakeText(200, y, "{d}", .{value.value_default.u}, null, null) catch null,
            .I => rt.MakeText(200, y, "{d}", .{value.value_default.i}, null, null) catch null,
            .Str => rt.MakeText(200, y, "{s}", .{value.value_default.str}, null, null) catch null,
            .None => rt.MakeText(200, y, "{s}", .{"undefined"}, null, null) catch null,
        });
        _ = gf.GDrawText(.Debug, rt.MakeText(300, y, "{s}", .{@tagName(value.value_type)}, null, null) catch null);
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
            _ = gf.GDrawText(.Debug, switch (s_value.value_type) {
                .B => rt.MakeText(100, y, "{any}", .{s_value.value.b}, null, null) catch null,
                .F => rt.MakeText(100, y, "{d:4.2}", .{s_value.value.f}, null, null) catch null,
                .U => rt.MakeText(100, y, "{d}", .{s_value.value.u}, null, null) catch null,
                .I => rt.MakeText(100, y, "{d}", .{s_value.value.i}, null, null) catch null,
                else => rt.MakeText(100, y, "{s}", .{s_value.value.str}, null, null) catch null,
            });
            _ = gf.GDrawText(.Debug, switch (s_value.value_type) {
                .B => rt.MakeText(200, y, "{any}", .{s_value.value_default.b}, null, null) catch null,
                .F => rt.MakeText(200, y, "{d:4.2}", .{s_value.value_default.f}, null, null) catch null,
                .U => rt.MakeText(200, y, "{d}", .{s_value.value_default.u}, null, null) catch null,
                .I => rt.MakeText(200, y, "{d}", .{s_value.value_default.i}, null, null) catch null,
                .Str => rt.MakeText(200, y, "{s}", .{s_value.value_default.str}, null, null) catch null,
                .None => rt.MakeText(200, y, "{s}", .{"undefined"}, null, null) catch null,
            });
            _ = gf.GDrawText(.Debug, rt.MakeText(300, y, "{s}", .{@tagName(s_value.value_type)}, null, null) catch null);
            y += 8;
        }
    }
}

// TODO: impl testing in build script; cannot test statically because imports out of scope
// TODO: move testing stuff to here but commented in meantime
test {
    // ...
}
