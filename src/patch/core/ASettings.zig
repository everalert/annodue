const std = @import("std");

const ArrayList = std.ArrayList;

const ini = @import("zigini");
const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

const EnumSet = std.EnumSet;
const Allocator = std.mem.Allocator;
const bufPrintZ = std.fmt.bufPrintZ;

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const workingOwner = @import("Hook.zig").PluginState.workingOwner;
const coreAllocator = @import("Allocator.zig").allocator;

const HandleMapSOA = @import("../util/handle_map_soa.zig").HandleMapSOA;
const HandleSOA = @import("../util/handle_map_soa.zig").Handle;

const r = @import("racer");
const rt = r.Text;

// FIXME: remove, for testing
const dbg = @import("../util/debug.zig");

// TODO: remove OnSettingsLoad from hooks after all settings ported to new system
// TODO: ?? system watches for changes in values at stored ptrs? so you can just change
// the var plugin-side and the system will store changes, run callbacks, save to
// file, etc by itself. only within section scope or as config'd? don't run callbacks
// except when loading from file (assumption that plugin will handle itself if
// setting vars directly)?
// FIXME: getting a index of handle/sparse_index by using nodeFind likely incorrect, but
// just not an issue so far because no items have needed to be deleted/shuffled yet;
// see iniRead->parse->.section for how to actually resolve handle to value

// DEFS

pub const Handle = HandleSOA(u16);
pub const NullHandle = Handle.getNull();

const DEFAULT_ID = 0xFFFF; // TODO: use ASettings plugin id?

pub const ASettingSent = extern struct {
    name: [*:0]const u8,
    value: Value,

    pub const Value = extern union {
        str: [*:0]const u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        // TODO: decide if any need to error on None type
        pub inline fn fromRaw(value: [*:0]const u8, t: Setting.Type) Value {
            const len = std.mem.len(@as([*:0]const u8, @ptrCast(value)));
            return switch (t) {
                .B => .{ .b = std.mem.eql(u8, "on", value[0..2]) or
                    std.mem.eql(u8, "true", value[0..4]) or
                    value[0] == '1' },
                .I => .{ .i = std.fmt.parseInt(i32, value[0..len], 10) catch @panic("value not i32") },
                .U => .{ .u = std.fmt.parseInt(u32, value[0..len], 10) catch @panic("value not u32") },
                .F => .{ .f = std.fmt.parseFloat(f32, value[0..len]) catch @panic("value not f32") },
                else => .{ .str = value },
            };
        }

        // TODO: decide if any need to error on None type
        pub inline fn fromSetting(setting: *const Setting.Value, t: Setting.Type) Value {
            return switch (t) {
                .B => .{ .b = setting.b },
                .I => .{ .i = setting.i },
                .U => .{ .u = setting.u },
                .F => .{ .f = setting.f },
                else => .{ .str = &setting.str },
            };
        }
    };
};

// TODO: add global st/fn ptrs to fnOnChange def?
pub const Setting = struct {
    section: ?struct { generation: u16, index: u16 } = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    value: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_default: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_saved: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_type: Type = .None,
    value_ptr: ?*anyopaque = null,
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (value: ASettingSent.Value) callconv(.C) void = null,

    pub const Type = enum(u8) { None, Str, F, U, I, B };

    pub const Value = extern union {
        str: [63:0]u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        // TODO: decide if any need to error on None type
        pub inline fn set(self: *Value, v: ASettingSent.Value, t: Type) !void {
            switch (t) {
                .F => self.f = v.f,
                .U => self.u = v.u,
                .I => self.i = v.i,
                .B => self.b = v.b,
                else => _ = try bufPrintZ(&self.str, "{s}", .{v.str}),
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

        pub inline fn getToPtr(self: *Value, p: *anyopaque, t: Type) void {
            return switch (t) {
                .Str => @as(*[63:0]u8, @alignCast(@ptrCast(p))).* = @as(*[63:0]u8, @ptrCast(&self.str)).*,
                .F => @as(*f32, @alignCast(@ptrCast(p))).* = @as(*f32, @ptrCast(&self.f)).*,
                .U => @as(*u32, @alignCast(@ptrCast(p))).* = @as(*u32, @ptrCast(&self.u)).*,
                .I => @as(*i32, @alignCast(@ptrCast(p))).* = @as(*i32, @ptrCast(&self.i)).*,
                .B => @as(*bool, @alignCast(@ptrCast(p))).* = @as(*bool, @ptrCast(&self.b)).*,
                else => @panic("setting value type must not be None"),
            };
        }

        /// raw (string) to value
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
        /// value to raw (string)
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

        pub inline fn eql(self: *Value, other: ASettingSent.Value, t: Type) bool {
            return switch (t) {
                .B => self.b == other.b,
                .I => self.i == other.i,
                .U => self.u == other.u,
                .F => self.f == other.f,
                else => {
                    const len = std.mem.len(@as([*:0]const u8, @ptrCast(&self.str)));
                    return std.mem.eql(u8, @as([*:0]const u8, @ptrCast(&self.str))[0..len], other.str[0..len]);
                },
            };
        }
    };

    const Flags = enum(u32) {
        HasOwner,
        FileUpdated,
        ChangedSinceLastRead,
        ProcessedSinceLastRead, // marker to let you know, e.g. don't unset ChangedSinceLastRead
        ValueIsSet,
        ValueNotConverted,
        SavedValueIsSet,
        SavedValueNotConverted,
        DefaultValueIsSet,
        DefaultValueNotConverted,
        InSectionUpdateQueue,
    };

    inline fn sent2setting(setting: ASettingSent.Value) Value {
        _ = setting;
    }
};

// reserved settings: AutoSave, UseGlobalAutoSave
// TODO: add global st/fn ptrs to fnOnChange def?
// FIXME: section->index may become invalid when handle expires due to swapRemove
// in handle_map; same problem with Setting->section too
// need to confirm if this is an issue, and maybe rework how connecting parents works
pub const Section = struct {
    section: ?struct { generation: u16, index: u16 } = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (changed: [*]ASettingSent, len: usize) callconv(.C) void = null,

    const Flags = enum(u32) {
        HasOwner,
        AutoSave,
        UpdateQueued,
    };
};

// reserved global settings: AutoSave
const ASettings = struct {
    const check_freq: u32 = 1000 / 24; // in lieu of every frame
    var data_sections: HandleMapSOA(Section, u16) = undefined;
    var data_settings: HandleMapSOA(Setting, u16) = undefined;
    var flags: EnumSet(Flags) = EnumSet(Flags).initEmpty();
    var last_check: u32 = 0;
    var last_filetime: w32f.FILETIME = undefined;
    var section_update_queue: ArrayList(ASettingSent) = undefined;

    var h_section_plugin: ?Handle = null;
    var h_section_core: ?Handle = null;
    var h_s_settings_version: ?Handle = null;
    var s_settings_version: u32 = 1;

    const Flags = enum(u32) {
        AutoSave,
    };

    pub fn init(alloc: Allocator) void {
        data_sections = HandleMapSOA(Section, u16).init(alloc);
        data_settings = HandleMapSOA(Setting, u16).init(alloc);
        section_update_queue = ArrayList(ASettingSent).init(alloc);
        // TODO: load from file
    }

    pub fn deinit() void {
        // TODO: save to file if needed
        data_sections.deinit();
        data_settings.deinit();
        section_update_queue.deinit();
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub inline fn nodeFind(
        map: anytype, // handle_map_*
        parent: ?Handle,
        name: [*:0]const u8,
    ) ?u16 {
        if (parent != null and
            (parent.?.isNull() or
            !data_sections.hasHandle(parent.?))) return null;

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
        if (section != null and
            (section.?.isNull() or
            !data_sections.hasHandle(section.?))) return error.SectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeFind(data_sections, section, name) != null) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&section_new.name, "{s}", .{name});

        return try data_sections.insert(DEFAULT_ID, section_new);
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub fn sectionOccupy(
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        fnOnChange: ?*const fn ([*]ASettingSent, usize) callconv(.C) void,
    ) !Handle {
        const existing_i = nodeFind(data_sections, section, name);

        var data: Section = Section{};
        if (existing_i) |i| {
            if (data_sections.handles.items[i].owner != DEFAULT_ID) return error.SectionAlreadyOwned;
            data = data_sections.values.get(i);
        } else {
            data.section = if (section) |s| .{ .generation = s.generation, .index = s.index } else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        data.fnOnChange = fnOnChange;

        if (existing_i) |i| {
            data_sections.values.set(i, data);
            data_sections.handles.items[i].owner = owner;
            data_sections.sparse_indices.items[i].owner = owner;
            return data_sections.handles.items[i];
        } else {
            return data_sections.insert(owner, data);
        }
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    /// release ownership of a section node, and all of the children below it
    pub fn sectionVacate(
        handle: Handle,
    ) void {
        var data: Section = data_sections.get(handle) orelse return;

        const sec_slice_sections = data_sections.values.items(.section);
        for (sec_slice_sections, 0..) |*s, i| {
            if (s.* != null and s.*.?.generation == handle.generation and s.*.?.index == handle.index) {
                const h: Handle = data_sections.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) sectionVacate(h);
            }
        }

        const set_slice_sections = data_settings.values.items(.section);
        for (set_slice_sections, 0..) |*s, i| {
            if (s.* != null and s.*.?.generation == handle.generation and s.*.?.index == handle.index) {
                const h: Handle = data_settings.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) settingVacate(h);
            }
        }

        data.fnOnChange = null;

        data_sections.handles.items[handle.index].owner = DEFAULT_ID;
        data_sections.sparse_indices.items[handle.index].owner = DEFAULT_ID;
        data_sections.values.set(handle.index, data);
    }

    pub fn sectionRunUpdate(handle: Handle) void {
        var section: Section = data_sections.get(handle) orelse return;
        if (section.fnOnChange == null) return;

        section_update_queue.clearRetainingCapacity();

        const slices = data_settings.values.slice();
        const sl_sections = slices.items(.section);
        const sl_flags: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_names = slices.items(.name);
        const sl_values = slices.items(.value);
        const sl_types = slices.items(.value_type);

        for (sl_sections, sl_flags, sl_names, sl_values, sl_types) |*s, *f, *n, *v, t| {
            if (s.* == null or s.*.?.generation != handle.generation or s.*.?.index != handle.index) continue;
            if (!f.contains(.InSectionUpdateQueue)) continue;
            if (t == .None) continue;

            f.remove(.InSectionUpdateQueue);
            const send_data = ASettingSent{ .name = n, .value = ASettingSent.Value.fromSetting(v, t) };
            section_update_queue.append(send_data) catch continue;
        }

        section.fnOnChange.?(section_update_queue.items.ptr, section_update_queue.items.len);
    }

    pub fn sectionRunUpdateAll() void {
        for (data_sections.handles.items) |handle|
            sectionRunUpdate(handle);
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    pub fn settingNew(
        section: ?Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> value_saved
        from_file: bool,
    ) !Handle {
        if (section != null and
            (section.?.isNull() or
            !data_sections.hasHandle(section.?))) return error.SectionDoesNotExist;

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

        return try data_settings.insert(DEFAULT_ID, setting);
    }

    // FIXME: review how the handle map is being manipulated with respect to index
    // to make sure it's not messing with the mapping
    // FIXME: error handling (catch unreachable)
    /// take ownership of a setting
    /// will cause callback to run on the initial value
    pub fn settingOccupy(
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        value_type: Setting.Type,
        value_default: ASettingSent.Value,
        value_ptr: ?*anyopaque,
        fnOnChange: ?*const fn (ASettingSent.Value) callconv(.C) void,
    ) !Handle {
        std.debug.assert(value_type != .None);
        if (section) |s| {
            if (s.owner != owner) @panic("owner and handle owner must match");
            if (!data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = nodeFind(data_settings, section, name);

        var data: Setting = Setting{};
        if (existing_i) |i| {
            if (data_settings.handles.items[i].owner != DEFAULT_ID) return error.SettingAlreadyOwned;
            data = data_settings.values.get(i);
        } else {
            data.section = if (section) |s| .{ .generation = s.generation, .index = s.index } else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        // NOTE: existing data assumed to be raw (new, unprocessed or released)
        if (data.flags.contains(.ValueIsSet)) {
            data.value.raw2type(value_type) catch {
                // invalid data = use default, will be cleaned next file write
                data.value.set(value_default, value_type) catch unreachable;
            };
            if (!data.value.eql(value_default, value_type))
                data.flags.insert(.InSectionUpdateQueue);
            if (data.flags.contains(.SavedValueIsSet))
                data.value_saved.raw2type(value_type) catch data.flags.insert(.SavedValueNotConverted);
        } else {
            data.value.set(value_default, value_type) catch unreachable;
            data.flags.insert(.ValueIsSet);
        }
        data.value_type = value_type;
        data.value_default.set(value_default, value_type) catch unreachable;
        data.flags.insert(.DefaultValueIsSet);
        data.value_ptr = value_ptr;
        if (value_ptr) |p|
            data.value.getToPtr(p, data.value_type);
        data.fnOnChange = fnOnChange;
        if (fnOnChange) |f|
            f(ASettingSent.Value.fromSetting(&data.value, data.value_type));

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
    pub fn settingVacate(
        handle: Handle,
    ) void {
        var data: Setting = data_settings.get(handle) orelse return;
        std.debug.assert(data.flags.contains(.ValueIsSet));

        data.fnOnChange = null;

        data.value_default = .{ .str = std.mem.zeroes([63:0]u8) };
        data.flags.remove(.DefaultValueIsSet);

        data.value.type2raw(data.value_type) catch @panic("settingVacate: 'value' invalid");
        if (!data.flags.contains(.SavedValueNotConverted))
            data.value_saved.type2raw(data.value_type) catch @panic("settingVacate: 'value_saved' invalid");
        data.flags.remove(.SavedValueNotConverted);

        data.value_type = .None;

        data_settings.handles.items[handle.index].owner = DEFAULT_ID;
        data_settings.sparse_indices.items[handle.index].owner = DEFAULT_ID;
        data_settings.values.set(handle.index, data);
    }

    // TODO: ValueUpdated flag?
    /// trigger setting update with new value
    /// will cause callback to run
    pub fn settingUpdate(
        handle: Handle,
        value: ASettingSent.Value,
    ) void {
        const i = data_settings.getIndex(handle) orelse return;
        const slices = data_settings.values.slice();
        const t: Setting.Type = slices.items(.value_type)[i];
        const value_out: *Setting.Value = &slices.items(.value)[i];

        if (value_out.eql(value, t)) return;

        value_out.set(value, t) catch return;

        slices.items(.flags)[i].insert(.InSectionUpdateQueue);
        if (slices.items(.value_ptr)[i]) |p| value_out.getToPtr(p, t);
        if (slices.items(.fnOnChange)[i]) |f| f(value);
    }

    pub fn vacateOwner(owner: u16) void {
        // settings first for better cache use of data_settings processes
        for (ASettings.data_settings.handles.items) |h|
            if (h.owner == owner) ASettings.settingVacate(h);

        for (ASettings.data_sections.handles.items) |h|
            if (h.owner == owner) ASettings.sectionVacate(h);
    }

    // TODO: dumping stuff i might need here
    //pub fn iniParse() void {}
    //pub fn iniWrite() void {}
    //pub fn jsonParse() void {}
    //pub fn jsonWrite() void {}
    //pub fn cleanupSave() void {} // remove settings from file not defined by a plugin etc.
    //pub fn cleanupSaveOccupiedSectionsOnly() void {} // leave 'junk' data on file for unloaded sections
    //pub fn saveAuto(_: ?Handle) void {}
    //pub fn save(_: ?Handle) void {}
    //pub fn sort() void {}

    // TODO: update existing settings, run callbacks
    pub fn iniRead(alloc: Allocator, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var parser = ini.parse(alloc, file.reader());
        defer parser.deinit();

        var sec_handle: ?Handle = null;
        while (try parser.next()) |record| {
            switch (record) {
                .section => |name| {
                    const section_i = nodeFind(data_sections, null, name);
                    sec_handle = if (section_i) |i|
                        data_sections.handles.items[i]
                    else
                        sectionNew(null, name) catch null;
                },
                .property => |kv| {
                    const setting_i = nodeFind(data_settings, sec_handle, kv.key);
                    if (setting_i) |i| {
                        const handle = data_settings.handles.items[i]; // WARN: could be invalid
                        const set_slices = data_settings.values.slice();
                        const set_types = set_slices.items(.value_type);
                        const set_values: []Setting.Value = set_slices.items(.value);
                        const set_saved: []Setting.Value = set_slices.items(.value_saved);

                        const send_val = ASettingSent.Value.fromRaw(kv.value, set_types[i]);

                        if (!set_saved[i].eql(send_val, set_types[i]))
                            try set_saved[i].set(send_val, set_types[i]);

                        if (!set_values[i].eql(send_val, set_types[i]))
                            settingUpdate(handle, send_val);
                    } else {
                        _ = try settingNew(sec_handle, kv.key, kv.value, true);
                    }
                },
                .enumeration => |value| { // FIXME: impl
                    _ = value;
                },
            }
        }

        sectionRunUpdateAll();
    }

    fn load() bool {
        var fd: w32fs.WIN32_FIND_DATAA = undefined;
        _ = w32fs.FindFirstFileA("annodue/settings.ini", &fd);
        if (filetime_eql(&fd.ftLastWriteTime, &ASettings.last_filetime))
            return false;

        ASettings.iniRead(coreAllocator(), "annodue/settings.ini") catch return false;
        ASettings.last_filetime = fd.ftLastWriteTime;

        return true;
    }
};

// FIXME: copied from hook.zig; move both to util?
fn filetime_eql(t1: *w32f.FILETIME, t2: *w32f.FILETIME) bool {
    return (t1.dwLowDateTime == t2.dwLowDateTime and
        t1.dwHighDateTime == t2.dwHighDateTime);
}

// GLOBAL EXPORTS

// TODO: generally - make the plugin-facing stuff operate under 'plugin' section,
// which is initialized internally

pub fn ASectionOccupy(
    section: Handle,
    name: [*:0]const u8,
    fnOnChange: ?*const fn ([*]ASettingSent, usize) callconv(.C) void,
) callconv(.C) Handle {
    return ASettings.sectionOccupy(
        workingOwner(),
        if (section.isNull()) null else section, // TODO: internal 'plugin' section
        name,
        fnOnChange,
    ) catch NullHandle;
}

pub fn ASectionVacate(handle: Handle) callconv(.C) void {
    ASettings.sectionVacate(handle);
}

pub fn ASettingOccupy(
    section: Handle,
    name: [*:0]const u8,
    value_type: Setting.Type,
    value_default: ASettingSent.Value,
    value_ptr: ?*anyopaque,
    fnOnChange: ?*const fn (ASettingSent.Value) callconv(.C) void,
) callconv(.C) Handle {
    return ASettings.settingOccupy(
        workingOwner(),
        if (section.isNull()) null else section,
        name,
        value_type,
        value_default,
        value_ptr,
        fnOnChange,
    ) catch NullHandle;
}

pub fn ASettingVacate(handle: Handle) callconv(.C) void {
    ASettings.settingVacate(handle);
}

pub fn ASettingUpdate(handle: Handle, value: ASettingSent.Value) callconv(.C) void {
    ASettings.settingUpdate(handle, value);
}

pub fn AVacateAll() callconv(.C) void {
    ASettings.vacateOwner(workingOwner());
}

// HOOKS

// TODO: move below to commented test block
fn updateSet1(value: ASettingSent.Value) callconv(.C) void {
    dbg.ConsoleOut("set1 changed to {d:4.2}\n", .{value.f}) catch {};
}

pub fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    ASettings.init(coreAllocator());
    _ = ASettings.load();
    //ASettings.h_section_core = ASettings.sectionNew(null, "Core") catch NullHandle;
    //ASettings.h_section_plugin = ASettings.sectionNew(null, "Plugin") catch NullHandle;
    ASettings.h_s_settings_version =
        gf.ASettingOccupy(NullHandle, "SETTINGS_VERSION", .U, .{ .u = 1 }, &ASettings.s_settings_version, null);

    // TODO: move below to commented test block
    // TODO: add setting occupy -> string type test

    //_ = ASettings.sectionNew(null, "Sec1") catch {};
    //_ = ASettings.sectionNew(null, "Sec2") catch {};
    //_ = ASettings.sectionNew(null, "Sec2") catch {}; // expect: NameTaken error -> skipped
    //const sec1 = ASettings.sectionOccupy(0x0000, null, "Sec1", null) catch NullHandle;
    //const sec2 = ASettings.sectionOccupy(0x0001, null, "Sec2", null) catch NullHandle;

    //_ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.settingNew(null, "Set2", "Val2", false) catch {};
    //_ = ASettings.settingNew(sec2, "Set3", "Val3", false) catch {};
    //_ = ASettings.settingNew(null, "Set4", "Val4", false) catch {};
    //_ = ASettings.settingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    //_ = ASettings.settingNew(null, "Set5", "Val5", false) catch {};

    //const occ1 = ASettings.settingOccupy(0x0000, sec1, "Set1", .F, .{ .f = 987.654 }, null, updateSet1) catch NullHandle;
    //_ = ASettings.settingOccupy(0x0000, sec1, "Set1", .F, .{ .f = 987.654 }, null, null) catch {}; // expect: ignored
    //const occ2 = ASettings.settingOccupy(0x0000, null, "Set6", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //_ = ASettings.settingOccupy(0x0000, null, "Set6", .F, .{ .f = 876.543 }, null, null) catch {}; // export: ignored

    //ASettings.settingUpdate(occ1, .{ .f = 678.543 }); // expect: changed value
    //ASettings.settingVacate(occ2); // expect: undefined default, etc.

    //const sec3 = ASettings.sectionOccupy(0x0000, sec2, "Sec3", null) catch NullHandle;
    //_ = ASettings.settingNew(sec3, "Set7", "Val7", false) catch {};
    //_ = ASettings.settingOccupy(0x0000, sec3, "Set8", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //ASettings.sectionVacate(sec3);

    //ASettings.vacateOwner(0x0000); // expect: everything undefined default, etc.
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    ASettings.deinit();
}

pub fn OnPluginDeinit(owner: u16) callconv(.C) void {
    ASettings.vacateOwner(owner);
}

pub fn GameLoopB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (gs.timestamp > ASettings.last_check + ASettings.check_freq)
        _ = ASettings.load();
    ASettings.last_check = gs.timestamp;
}

// FIXME: remove, for testing
pub fn Draw2DB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (!gf.InputGetKbRaw(.RSHIFT).on()) return;

    const s = struct {
        const rate: f32 = 300;
        var y_off: i16 = 0;
    };

    _ = gf.GDrawRect(.Debug, 0, 0, 400, 480, 0x000020E0);
    var x: i16 = 0;
    var y: i16 = 0 + s.y_off;
    drawSettings(gf, null, &x, &y);

    var h: i16 = y - s.y_off;
    var dif: i16 = @intFromFloat(gs.dt_f * s.rate);
    if (gf.InputGetKbRaw(.PRIOR).on()) s.y_off = @min(s.y_off + dif, 0); // scroll up
    if (gf.InputGetKbRaw(.NEXT).on()) s.y_off = std.math.clamp(s.y_off - dif, -h + 480, 0); // scroll dn
}

// TODO: maybe adapt for test script
fn drawSettings(gf: *GlobalFn, section: ?Handle, x_ref: *i16, y_ref: *i16) void {
    for (0..ASettings.data_settings.values.len) |i| {
        const value: Setting = ASettings.data_settings.values.get(i);
        if ((section == null) != (value.section == null)) continue;
        if (section != null and
            (value.section.?.generation != section.?.generation or
            value.section.?.index != section.?.index)) continue;

        _ = gf.GDrawText(.Debug, rt.MakeText(x_ref.*, y_ref.*, "{s}", .{value.name}, null, null) catch null);
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.MakeText(256, y_ref.*, "{any}", .{value.value.b}, null, null) catch null,
            .F => rt.MakeText(256, y_ref.*, "{d:4.2}", .{value.value.f}, null, null) catch null,
            .U => rt.MakeText(256, y_ref.*, "{d}", .{value.value.u}, null, null) catch null,
            .I => rt.MakeText(256, y_ref.*, "{d}", .{value.value.i}, null, null) catch null,
            else => rt.MakeText(256, y_ref.*, "{s}", .{value.value.str}, null, null) catch null,
        });
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.MakeText(312, y_ref.*, "{any}", .{value.value_default.b}, null, null) catch null,
            .F => rt.MakeText(312, y_ref.*, "{d:4.2}", .{value.value_default.f}, null, null) catch null,
            .U => rt.MakeText(312, y_ref.*, "{d}", .{value.value_default.u}, null, null) catch null,
            .I => rt.MakeText(312, y_ref.*, "{d}", .{value.value_default.i}, null, null) catch null,
            .Str => rt.MakeText(312, y_ref.*, "{s}", .{value.value_default.str}, null, null) catch null,
            .None => rt.MakeText(312, y_ref.*, "{s}", .{"undefined"}, null, null) catch null,
        });
        _ = gf.GDrawText(.Debug, rt.MakeText(368, y_ref.*, "{s}", .{@tagName(value.value_type)}, null, null) catch null);
        y_ref.* += 10;
    }

    for (0..ASettings.data_sections.values.len) |i| {
        const value: Section = ASettings.data_sections.values.get(i);
        if ((section == null) != (value.section == null)) continue;
        if (section != null and
            (value.section.?.generation != section.?.generation or
            value.section.?.index != section.?.index)) continue;

        //y_ref.* += 4;
        _ = gf.GDrawText(.Debug, rt.MakeText(x_ref.*, y_ref.*, "{s}", .{value.name}, null, null) catch null);
        y_ref.* += 10;

        x_ref.* += 12;
        const handle: Handle = ASettings.data_sections.handles.items[i];
        drawSettings(gf, handle, x_ref, y_ref);
        x_ref.* -= 12;
    }
}

// TODO: impl testing in build script; cannot test statically because imports out of scope
// TODO: move testing stuff to here but commented in meantime
test {
    // ...
}
