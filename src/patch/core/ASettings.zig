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
const workingOwnerIsSystem = @import("Hook.zig").PluginState.workingOwnerIsSystem;
const coreAllocator = @import("Allocator.zig").allocator;

const HandleMapSOA = @import("../util/handle_map_soa.zig").HandleMapSOA;
const SparseIndex = @import("../util/handle_map_soa.zig").SparseIndex(u16);
pub const Handle = @import("../util/handle_map_soa.zig").Handle(u16);
pub const NullHandle = Handle.getNull();

const dbg = @import("../util/debug.zig");

const r = @import("racer");
const rt = r.Text;

// FIXME: not really sure handle maps needed to be SOA tbh, test using non-SOA handle_map
// in separate branch if majority of functions are using majority of slices anyways

// DEFS

const SETTINGS_VERSION: u32 = 2;
const DEFAULT_ID = 0xFFFF; // TODO: use ASettings plugin id?
const FILENAME = "annodue/settings.ini";
const FILENAME_TEST = "annodue/settings_test.ini";
const FILENAME_ACTIVE = FILENAME_TEST;

pub const ParentHandle = extern struct {
    generation: u16,
    index: u16,

    fn eql(p: ?ParentHandle, h: ?Handle) bool {
        if ((p == null) != (h == null)) return false;
        if (p != null and (p.?.index != h.?.index or p.?.generation != h.?.generation)) return false;
        return true;
    }
};

pub const ASettingSent = extern struct {
    name: [*:0]const u8,
    value: Value,

    pub const Value = extern union {
        str: [*:0]const u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        pub fn fromRaw(value: [*:0]const u8, t: Setting.Type) Value {
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

        pub fn fromSetting(setting: *const Setting.Value, t: Setting.Type) Value {
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
    section: ?ParentHandle = null,
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
        pub fn setSent(self: *Value, v: ASettingSent.Value, t: Type) !void {
            switch (t) {
                .F => self.f = v.f,
                .U => self.u = v.u,
                .I => self.i = v.i,
                .B => self.b = v.b,
                else => _ = try bufPrintZ(&self.str, "{s}", .{v.str}),
            }
        }

        pub fn get(self: *Value, t: Type) Value {
            return switch (t) {
                .Str => self.str,
                .F => self.f,
                .U => self.u,
                .I => self.i,
                .B => self.b,
                else => @panic("setting value type must not be None"),
            };
        }

        pub fn getToPtr(self: *Value, p: *anyopaque, t: Type) void {
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
        pub fn raw2type(self: *Value, t: Type) !void {
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

        /// value to raw (string)
        pub fn type2raw(self: *Value, t: Type) !void {
            switch (t) {
                .B => _ = try bufPrintZ(&self.str, "{s}", .{if (self.b) "on" else "off"}),
                .I => _ = try bufPrintZ(&self.str, "{d}", .{self.i}),
                .U => _ = try bufPrintZ(&self.str, "{d}", .{self.u}),
                .F => _ = try bufPrintZ(&self.str, "{d:4.2}", .{self.f}),
                .Str => {},
                else => @panic("setting input value type must not be None"),
            }
        }

        pub fn type2type(self: *Value, t1: Type, t2: type) !void {
            try self.type2raw(t1);
            try self.raw2type(t2);
        }

        pub fn eql(self: *const Value, other: *const Value, t: Type) bool {
            return switch (t) {
                .B => self.b == other.b,
                .I => self.i == other.i,
                .U => self.u == other.u,
                .F => self.f == other.f,
                else => {
                    const len = std.mem.len(@as([*:0]const u8, @ptrCast(&self.str)));
                    return std.mem.eql(u8, self.str[0..len], other.str[0..len]);
                },
            };
        }

        pub fn eqlSent(self: *const Value, other: ASettingSent.Value, t: Type) bool {
            return switch (t) {
                .B => self.b == other.b,
                .I => self.i == other.i,
                .U => self.u == other.u,
                .F => self.f == other.f,
                else => {
                    const len = std.mem.len(@as([*:0]const u8, @ptrCast(&self.str)));
                    return std.mem.eql(u8, self.str[0..len], other.str[0..len]);
                },
            };
        }

        pub fn write(self: *const Value, writer: anytype, t: Type) !void {
            switch (t) {
                .B => try std.fmt.format(writer, "{s}", .{if (self.b) "on" else "off"}),
                .I => try std.fmt.format(writer, "{d}", .{self.i}),
                .U => try std.fmt.format(writer, "{d}", .{self.u}),
                .F => try std.fmt.format(writer, "{d:4.2}", .{self.f}),
                else => try std.fmt.format(writer, "{s}", .{@as([*:0]const u8, @ptrCast(&self.str))}),
            }
        }
    };

    const Flags = enum(u32) {
        HasOwner,
        FileUpdatedLastWrite,
        ChangedSinceLastRead,
        ProcessedSinceLastRead, // marker to let you know, e.g. don't unset ChangedSinceLastRead
        ValueIsSet,
        ValueNotConverted,
        SavedValueIsSet,
        SavedValueNotConverted,
        DefaultValueIsSet,
        DefaultValueNotConverted,
        InSectionUpdateQueue, // marked to be added to array that is sent with section update callback
        InFileWriteQueue, // marked during preprocessing
    };
};

// reserved settings: AutoSave, UseGlobalAutoSave
// TODO: add global st/fn ptrs to fnOnChange def?
pub const Section = struct {
    section: ?ParentHandle = null,
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
pub const ASettings = struct {
    const check_freq: u32 = 1000 / 24; // in lieu of every frame
    var data_sections: HandleMapSOA(Section, u16) = undefined;
    var data_settings: HandleMapSOA(Setting, u16) = undefined;
    var flags: EnumSet(Flags) = EnumSet(Flags).initEmpty();
    var last_check: u32 = 0;
    var last_filetime: w32f.FILETIME = undefined;
    var file_exists: bool = false;
    var skip_next_load: bool = false;
    var section_update_queue: ArrayList(ASettingSent) = undefined;

    var h_section_plugin: ?Handle = null;
    var h_section_core: ?Handle = null;
    var h_s_settings_version: ?Handle = null;
    var h_s_save_auto: ?Handle = null;
    var h_s_save_defaults: ?Handle = null;
    // TODO: change to false once annodue stops releasing Safe builds (also in settingOccupy call)
    var s_settings_version: u32 = 1;
    var s_save_auto: bool = true;
    var s_save_defaults: bool = true;

    const Flags = enum(u32) {
        AutoSave,
    };

    pub fn init(alloc: Allocator) void {
        data_sections = HandleMapSOA(Section, u16).init(alloc);
        data_settings = HandleMapSOA(Setting, u16).init(alloc);
        section_update_queue = ArrayList(ASettingSent).init(alloc);
    }

    pub fn deinit() void {
        data_sections.deinit();
        data_settings.deinit();
        section_update_queue.deinit();
    }

    /// gets index of data matching name and parenting pattern
    /// index will be valid for map's data and handle arrays, use handle.index
    /// for sparse_indices array index
    pub fn nodeFind(
        map: anytype, // handle_map_*
        parent: ?Handle,
        name: [*:0]const u8,
    ) ?u16 {
        if (parent != null and
            (parent.?.isNull() or
            !data_sections.hasHandle(parent.?))) return null;

        const name_len = std.mem.len(name) + 1; // include sentinel
        const slices = map.values.slice();
        const sl_name = slices.items(.name);
        const sl_sec = slices.items(.section);
        for (sl_name, sl_sec, 0..) |*n, *s, i| {
            if (!ParentHandle.eql(s.*, parent)) continue;
            if (!std.mem.eql(u8, n[0..name_len], name[0..name_len]))
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

    // FIXME: use data ref instead of making new data item? also applies to settingOccupy, maybe others
    // FIXME: impl 'update owner' function in handle_map for cases like here?
    // search for 'sparse_indices.items[' for all uses
    pub fn sectionOccupy(
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        fnOnChange: ?*const fn ([*]ASettingSent, usize) callconv(.C) void,
    ) !Handle {
        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) dbg.PPanic("owners must match - owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

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
            data_sections.sparse_indices.items[data_sections.handles.items[i].index].owner = owner;
            return data_sections.handles.items[i];
        } else {
            return data_sections.insert(owner, data);
        }
    }

    /// release ownership of a section node, and all of the children below it
    pub fn sectionVacate(
        handle: Handle,
    ) void {
        var data_i = data_sections.getIndex(handle) orelse return;

        const sec_slices = data_sections.values.slice();
        const sec_sl_fn = sec_slices.items(.fnOnChange);
        const sec_sl_sec = sec_slices.items(.section);
        for (sec_sl_sec, 0..) |*s, i| {
            if (s.* != null and ParentHandle.eql(s.*, handle)) {
                const h: Handle = data_sections.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) sectionVacate(h);
            }
        }

        const set_sl_sec = data_settings.values.items(.section);
        for (set_sl_sec, 0..) |*s, i| {
            if (s.* != null and ParentHandle.eql(s.*, handle)) {
                const h: Handle = data_settings.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) settingVacate(h);
            }
        }

        sec_sl_fn[data_i] = null;
        data_sections.sparse_indices.items[handle.index].owner = DEFAULT_ID;
        data_sections.handles.items[data_i].owner = DEFAULT_ID;
    }

    pub fn sectionRunUpdate(handle: Handle) void {
        const sec_i = data_sections.getIndex(handle) orelse return;
        const sec_fn = data_sections.values.items(.fnOnChange)[sec_i] orelse return;

        section_update_queue.clearRetainingCapacity();

        const slices = data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_name = slices.items(.name);
        const sl_val = slices.items(.value);
        const sl_t = slices.items(.value_type);

        for (sl_sec, sl_fl, sl_name, sl_val, sl_t) |*s, *f, *n, *v, t| {
            if (s.* == null or !ParentHandle.eql(s.*, handle)) continue;
            if (!f.contains(.InSectionUpdateQueue)) continue;
            if (t == .None) continue;

            f.remove(.InSectionUpdateQueue);
            const send_data = ASettingSent{ .name = n, .value = ASettingSent.Value.fromSetting(v, t) };
            section_update_queue.append(send_data) catch continue;
        }

        sec_fn(section_update_queue.items.ptr, section_update_queue.items.len);
    }

    pub fn sectionRunUpdateOwner(owner: u16) void {
        for (data_sections.handles.items) |handle|
            if (handle.owner == owner) sectionRunUpdate(handle);
    }

    pub fn sectionRunUpdateAll() void {
        for (data_sections.handles.items) |handle|
            sectionRunUpdate(handle);
    }

    pub fn sectionResetToSaved(handle: ?Handle) void {
        const slices = data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_val = slices.items(.value);
        const sl_vals = slices.items(.value_saved);

        for (sl_sec, sl_fl, sl_val, sl_vals) |*s, *f, *v, *vs| {
            if (!ParentHandle.eql(s.*, handle)) continue;
            if (!f.contains(.SavedValueIsSet)) continue;

            v.* = vs.*;
            f.insert(.ValueIsSet);
        }
    }

    pub fn sectionResetToDefaults(handle: ?Handle) void {
        const slices = data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_val = slices.items(.value);
        const sl_vald = slices.items(.value_default);

        for (sl_sec, sl_fl, sl_val, sl_vald) |*s, *f, *v, *vd| {
            if (!ParentHandle.eql(s.*, handle)) continue;
            if (!f.contains(.DefaultValueIsSet)) continue;

            v.* = vd.*;
            f.insert(.ValueIsSet);
        }
    }

    pub fn sectionRemoveVacant(handle: ?Handle) void {
        const slices = data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);

        const len = data_settings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (!ParentHandle.eql(sl_sec[i], handle)) continue;
            if (sl_fl[i].contains(.DefaultValueIsSet)) continue;
            _ = data_settings.remove(data_settings.handles.items[i]);
        }
    }

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

        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) dbg.PPanic("owners must match - owner:{d}  s.owner:{d}", .{ owner, s.owner });
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
                data.value.setSent(value_default, value_type) catch unreachable;
            };
            if (!data.value.eqlSent(value_default, value_type))
                data.flags.insert(.InSectionUpdateQueue);
            if (data.flags.contains(.SavedValueIsSet))
                data.value_saved.raw2type(value_type) catch data.flags.insert(.SavedValueNotConverted);
        } else {
            data.value.setSent(value_default, value_type) catch unreachable;
            data.flags.insert(.ValueIsSet);
        }
        data.value_type = value_type;
        data.value_default.setSent(value_default, value_type) catch unreachable;
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
            data_settings.sparse_indices.items[data_settings.handles.items[i].index].owner = owner;
            return data_settings.handles.items[i];
        } else {
            return data_settings.insert(owner, data);
        }
    }

    pub fn settingVacate(
        handle: Handle,
    ) void {
        const data_i = data_settings.getIndex(handle) orelse return;
        const slices = data_settings.values.slice();
        const fl: *EnumSet(Setting.Flags) = &slices.items(.flags)[data_i];
        std.debug.assert(fl.contains(.ValueIsSet));

        const val: *Setting.Value = &slices.items(.value)[data_i];
        const vals: *Setting.Value = &slices.items(.value_saved)[data_i];
        const vald: *Setting.Value = &slices.items(.value_default)[data_i];
        const t: *Setting.Type = &slices.items(.value_type)[data_i];
        const f = &slices.items(.fnOnChange)[data_i];

        f.* = null;

        vald.* = .{ .str = std.mem.zeroes([63:0]u8) };
        fl.remove(.DefaultValueIsSet);

        val.type2raw(t.*) catch @panic("settingVacate: 'value' invalid");
        if (!fl.contains(.SavedValueNotConverted))
            vals.type2raw(t.*) catch @panic("settingVacate: 'value_saved' invalid");
        fl.remove(.SavedValueNotConverted);

        t.* = .None;

        data_settings.sparse_indices.items[handle.index].owner = DEFAULT_ID;
        data_settings.handles.items[data_i].owner = DEFAULT_ID;
    }

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

        if (value_out.eqlSent(value, t)) return;

        value_out.setSent(value, t) catch return;

        slices.items(.flags)[i].insert(.InSectionUpdateQueue);
        if (slices.items(.value_ptr)[i]) |p| value_out.getToPtr(p, t);
        if (slices.items(.fnOnChange)[i]) |f| f(value);
    }

    pub fn settingResetAllToSaved() void {
        const slices = data_settings.values.slice();
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_val = slices.items(.value);
        const sl_vals = slices.items(.value_saved);

        for (sl_fl, sl_val, sl_vals) |*f, *v, *vs| {
            if (!f.contains(.SavedValueIsSet)) continue;
            v.* = vs.*;
            f.insert(.ValueIsSet);
        }
    }

    pub fn settingResetAllToDefaults() void {
        const slices = data_settings.values.slice();
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_val = slices.items(.value);
        const sl_vald = slices.items(.value_default);

        for (sl_fl, sl_val, sl_vald) |*f, *v, *vd| {
            if (!f.contains(.DefaultValueIsSet)) continue;
            v.* = vd.*;
            f.insert(.ValueIsSet);
        }
    }

    pub fn settingRemoveAllVacant() void {
        const slices = data_settings.values.slice();
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);

        const len = data_settings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (sl_fl[i].contains(.DefaultValueIsSet)) continue;
            _ = data_settings.remove(data_settings.handles.items[i]);
        }
    }

    pub fn vacateOwner(owner: u16) void {
        // settings first for better cache use of data_settings processes
        for (ASettings.data_settings.handles.items) |h|
            if (h.owner == owner) ASettings.settingVacate(h);

        for (ASettings.data_sections.handles.items) |h|
            if (h.owner == owner) ASettings.sectionVacate(h);
    }

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
                        const slices = data_settings.values.slice();
                        const sl_t = slices.items(.value_type);
                        const sl_val: []Setting.Value = slices.items(.value);
                        const sl_vals: []Setting.Value = slices.items(.value_saved);
                        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);

                        // don't override value that has already been changed by something else
                        if (sl_fl[i].contains(.SavedValueIsSet) and
                            !sl_val[i].eql(&sl_vals[i], sl_t[i])) continue;

                        const send_val = ASettingSent.Value.fromRaw(kv.value, sl_t[i]);

                        if (!sl_vals[i].eqlSent(send_val, sl_t[i]))
                            try sl_vals[i].setSent(send_val, sl_t[i]);

                        if (!sl_val[i].eqlSent(send_val, sl_t[i]))
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

        const find_handle = w32fs.FindFirstFileA(FILENAME_ACTIVE, &fd);
        defer _ = w32fs.FindClose(find_handle);
        if (-1 == find_handle) return false;

        if (filetime_eql(&fd.ftLastWriteTime, &ASettings.last_filetime))
            return false;

        ASettings.last_filetime = fd.ftLastWriteTime;

        if (skip_next_load) {
            skip_next_load = false;
            return false;
        }

        ASettings.iniRead(coreAllocator(), FILENAME_ACTIVE) catch return false;

        file_exists = true;
        return true;
    }

    // TODO: sorting both settings and sections?
    pub fn iniWrite(writer: anytype) !void {
        try iniWriteSection(writer, null);
        for (data_sections.handles.items) |h|
            try iniWriteSection(writer, h);
    }

    // TODO: track and output whether file had changes
    fn iniWriteSection(writer: anytype, handle: ?Handle) !void {
        if (handle) |h| {
            const section: Section = data_sections.get(h).?;
            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&section.name)));
            _ = try writer.write("[");
            _ = try writer.write(section.name[0..nlen]);
            _ = try writer.write("]\n");
        }

        const slices = data_settings.values.slice();
        const sl_sec: []?ParentHandle = slices.items(.section);
        const sl_name: [][63:0]u8 = slices.items(.name);
        const sl_val: []Setting.Value = slices.items(.value);
        const sl_f: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_t: []Setting.Type = slices.items(.value_type);
        for (sl_sec, sl_name, sl_val, sl_f, sl_t) |*sec, *name, *val, *fl, t| {
            if (!fl.contains(.InFileWriteQueue) or !ParentHandle.eql(sec.*, handle)) continue;

            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(name.ptr)));
            _ = try writer.write(name[0..nlen]);
            _ = try writer.write(" = ");
            try val.write(writer, t);
            _ = try writer.write("\n");

            fl.remove(.InFileWriteQueue);
        }
        _ = writer.write("\n") catch {};
    }

    fn save() !void {
        const changed_settings: u32 = savePrepare();
        if (changed_settings == 0 and (s_save_defaults and file_exists)) return;

        const file = try std.fs.cwd().createFile(FILENAME_ACTIVE, .{}); // .exclusive=true for no file rewrite
        defer file.close();
        var file_w = file.writer();

        try iniWrite(file_w);
        skip_next_load = true;
        file_exists = true;

        saveCleanup();
    }

    fn saveAuto() !void {
        if (s_save_auto)
            try save();
    }

    /// post-processing of sections and settings, to make settings ready for next write
    fn saveCleanup() void {
        const slices = data_settings.values.slice();
        const sl_f: []EnumSet(Setting.Flags) = slices.items(.flags);
        for (sl_f) |*fl| {
            // make sure system knows which settings are no longer on file
            if (!fl.contains(.FileUpdatedLastWrite))
                fl.remove(.SavedValueIsSet);

            fl.remove(.FileUpdatedLastWrite);
        }
    }

    // TODO: convert to flattened version of savePrepareSection logic? OR only call prep
    // on sections marked for saving? i.e. need to handle 'save only one section' case
    /// pre-pass on settings to determine which settings need to be written and how
    /// write functions assume settings are tagged correctly as a result of running this step
    /// @return     number of settings that would actually change in the file as a result of writing
    fn savePrepare() u32 {
        var changed: u32 = 0;

        changed += savePrepareSection(null);
        for (data_sections.handles.items) |h|
            changed += savePrepareSection(h);

        return changed;
    }

    /// @return     number of settings that would actually change in the file as a result of writing
    fn savePrepareSection(handle: ?Handle) u32 {
        var changed: u32 = 0;
        const slices = data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_val: []Setting.Value = slices.items(.value);
        const sl_vald: []Setting.Value = slices.items(.value_default);
        const sl_vals: []Setting.Value = slices.items(.value_saved);
        const sl_f: []EnumSet(Setting.Flags) = slices.items(.flags);
        const sl_t: []Setting.Type = slices.items(.value_type);
        for (sl_sec, sl_val, sl_vald, sl_vals, sl_f, sl_t) |sec, *val, *vald, *vals, *fl, t| {
            if (!ParentHandle.eql(sec, handle)) continue;

            // only keep uninitialized settings if they were already on file
            if (!fl.contains(.DefaultValueIsSet) and
                !fl.contains(.SavedValueIsSet)) continue;

            // only store initialized settings if they are not default
            if (!s_save_defaults and fl.contains(.DefaultValueIsSet) and
                vald.eql(val, t)) continue;

            if ((fl.contains(.SavedValueIsSet) and !vals.eql(val, t)) or
                (!fl.contains(.SavedValueIsSet) and s_save_defaults))
                changed += 1;

            vals.* = val.*;
            fl.insert(.SavedValueIsSet);
            fl.insert(.FileUpdatedLastWrite);

            fl.insert(.InFileWriteQueue);
        }
        return changed;
    }
};

pub fn init() !void {
    ASettings.init(coreAllocator());
    _ = ASettings.load();

    ASettings.h_s_settings_version =
        try ASettings.settingOccupy(DEFAULT_ID, null, "SETTINGS_VERSION", .U, .{ .u = 0 }, &ASettings.s_settings_version, null);
    ASettings.h_s_save_auto =
        try ASettings.settingOccupy(DEFAULT_ID, null, "SETTINGS_SAVE_AUTO", .B, .{ .b = true }, &ASettings.s_save_auto, null);
    ASettings.h_s_save_defaults =
        try ASettings.settingOccupy(DEFAULT_ID, null, "SETTINGS_SAVE_DEFAULTS", .B, .{ .b = true }, &ASettings.s_save_defaults, null);

    // ensure version is written to file by defaulting to 0 and setting here
    ASettings.settingUpdate(ASettings.h_s_settings_version.?, .{ .u = SETTINGS_VERSION });
}

pub fn deinit() !void {
    try ASettings.saveAuto();
    ASettings.deinit();
}

// FIXME: copied from hook.zig; move both to util?
fn filetime_eql(t1: *w32f.FILETIME, t2: *w32f.FILETIME) bool {
    return (t1.dwLowDateTime == t2.dwLowDateTime and
        t1.dwHighDateTime == t2.dwHighDateTime);
}

// GLOBAL EXPORTS

// TODO: generally - make the plugin-facing stuff operate under 'plugin' section,
// which is initialized internally; same for core, identify via id range check

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

/// manually call fnOnChange section callback on any 'changed' settings
pub fn ASectionRunUpdate(handle: Handle) callconv(.C) void {
    ASettings.sectionRunUpdate(handle);
}

/// revert entries under the given section back to owner-defined defaults
pub fn ASectionResetDefault(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToDefaults(handle);
}

/// revert entries under the given section back to values on file
pub fn ASectionResetFile(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToSaved(handle);
}

/// remove superfluous entries loaded from file under the given section
/// will be reflected in the settings file on the following save write
pub fn ASectionClean(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToDefaults(handle);
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

/// revert all entries back to owner-defined defaults
pub fn ASettingResetAllDefault() callconv(.C) void {
    ASettings.settingResetAllToDefaults();
}

/// revert all entries back to values on file
pub fn ASettingResetAllFile() callconv(.C) void {
    ASettings.settingResetAllToSaved();
}

/// remove all superfluous entries loaded from file
/// will be reflected in the settings file on the following save write
pub fn ASettingCleanAll() callconv(.C) void {
    ASettings.settingRemoveAllVacant();
}

/// manually trigger write of settings file
/// for internal use; will do nothing if caller is plugin
pub fn ASave() callconv(.C) void {
    if (!workingOwnerIsSystem()) return;
    ASettings.save() catch {};
}

/// create checkpoint for writing of settings file
/// file will only be written if user has enabled autosave
pub fn ASaveAuto() callconv(.C) void {
    ASettings.saveAuto() catch {};
}

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: move below to commented test block
    // TODO: add setting occupy -> string type test
    // TODO: use actual owner IDs that don't clash (or just make sure it's all actually test scoped)

    const sec_base = ASettings.sectionNew(null, "TestBaseSection") catch NullHandle;
    _ = ASettings.sectionNew(sec_base, "Sec1") catch {};
    _ = ASettings.sectionNew(sec_base, "Sec2") catch {};
    _ = ASettings.sectionNew(sec_base, "Sec2") catch {}; // expect: NameTaken error -> skipped
    const sec1 = ASettings.sectionOccupy(0xF000, sec_base, "Sec1", null) catch NullHandle;
    const sec2 = ASettings.sectionOccupy(0xF001, sec_base, "Sec2", null) catch NullHandle;

    _ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    _ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    _ = ASettings.settingNew(null, "Set2", "Val2", false) catch {};
    _ = ASettings.settingNew(sec2, "Set3", "Val3", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val4", false) catch {};
    _ = ASettings.settingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    _ = ASettings.settingNew(null, "Set5", "Val5", false) catch {};

    const occ1 = ASettings.settingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, testUpdateSet1) catch NullHandle;
    _ = ASettings.settingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, null) catch {}; // expect: ignored
    const occ2 = ASettings.settingOccupy(0xF000, null, "Set6", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    _ = ASettings.settingOccupy(0xF000, null, "Set6", .F, .{ .f = 876.543 }, null, null) catch {}; // export: ignored

    ASettings.settingUpdate(occ1, .{ .f = 678.543 }); // expect: changed value
    ASettings.settingVacate(occ2); // expect: undefined default, etc.

    const sec3 = ASettings.sectionOccupy(0xF001, sec2, "Sec3", null) catch NullHandle;
    _ = ASettings.settingNew(sec3, "Set7", "Val7", false) catch {};
    _ = ASettings.settingOccupy(0xF001, sec3, "Set8", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    ASettings.sectionVacate(sec3);

    ASettings.vacateOwner(0xF000); // expect: everything undefined default, etc.
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnPluginInitA(owner: u16) callconv(.C) void {
    ASettings.sectionRunUpdateOwner(owner);
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    ASettings.vacateOwner(owner);
}

pub fn GameLoopB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (gs.in_race.new())
        ASettings.saveAuto() catch {};

    if (gs.timestamp > ASettings.last_check + ASettings.check_freq)
        _ = ASettings.load();
    ASettings.last_check = gs.timestamp;
}

// FIXME: remove, for testing
pub fn Draw2DB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (gf.InputGetKbRaw(.J) == .JustOn)
        ASettings.saveAuto() catch {};

    if (!gf.InputGetKbRaw(.RSHIFT).on()) return;

    const s = struct {
        const rate: f32 = 300;
        var y_off: i16 = 0;
    };

    _ = gf.GDrawRect(.Debug, 0, 0, 416, 480, 0x000020E0);
    var x: i16 = 8;
    var y: i16 = 8 + s.y_off;
    drawSettings(gf, null, &x, &y);

    var h: i16 = y - s.y_off;
    var dif: i16 = @intFromFloat(gs.dt_f * s.rate);
    if (gf.InputGetKbRaw(.PRIOR).on()) s.y_off = @min(s.y_off + dif, 0); // scroll up
    if (gf.InputGetKbRaw(.NEXT).on()) s.y_off = std.math.clamp(s.y_off - dif, -h + 480 - 8, 0); // scroll dn
}

// TODO: maybe adapt for test script
// TODO: also maybe adapt for json settings (nesting, etc.)
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
            .None => null,
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

// NOTE: use in testing
fn testUpdateSet1(_: ASettingSent.Value) callconv(.C) void {
    //dbg.ConsoleOut("set1 changed to {d:4.2}\n", .{value.f}) catch {};
}

// TODO: impl testing in build script; cannot test statically because imports out of scope
// TODO: move testing stuff to here but commented in meantime
test {}
