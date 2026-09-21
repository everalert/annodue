// TODO: ?? change DEFAULT_ID
// TODO: add global st/fn ptrs to fnOnChange defs?
// TODO: change save_defaults to false once annodue stops releasing Safe builds (also in settingOccupy call)
// TODO: minor cleanup with handle_map 'update owner' fn?
// TODO: ?? update nomenclature from 'Occupy' -> 'Register', also 'Sent' -> 'Msg'?
// FIXME: is it necessary to have an explicit default value passed to SettingOccupy
//  when the default could be derived from the pointer? isn't it a bug to even
//  allow calling ASettingOccupy without either a value pointer or an update callback?

// SYSTEM OVERVIEW
// - support for bool, u32, i32, f32, and strings (64 bytes null-terminated)
// - settings stored as tree, with branch nodes representing sections/categories
// - tree is expanded on demand; not pre-seeded by design, to maximize flexibility
// - handle-based ownership of setting and section nodes
// - setting and section defs merged from different sources as needed, as long as no ownership conflict
// - callback behaviours available for both individual settings updates and collective section updates
// - settings hot-loaded from file; game-side changes written to file periodically

const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const EnumSet = std.EnumSet;
const bufPrintZ = std.fmt.bufPrintZ;
const assert = std.debug.assert;

const ini = @import("zigini");

const HandleMap = @import("../handle_map.zig").HandleMap;
const SparseIndex = @import("../handle_map.zig").SparseIndex(u16);
pub const Handle = @import("../handle_map.zig").Handle(u16);
pub const HANDLE_NULL = Handle.getNull();

const MiB = @import("../base/base_memory.zig").MiB;

const HotReloaderHandle = ?*SettingManager;
const HotReloader = @import("../hot_reload.zig").HotReload(HotReloaderHandle, 1);

// DEFS

const SETTINGS_VERSION: u32 = 2;
const DEFAULT_ID = 0xFFFF;

pub const ParentHandle = extern struct {
    generation: u16,
    index: u16,

    /// helper to test equality of nullable parent and regular handles
    fn eql(p: ?ParentHandle, h: ?Handle) bool {
        if ((p == null) != (h == null)) return false;
        if (p != null and (p.?.index != h.?.index or p.?.generation != h.?.generation)) return false;
        return true;
    }

    fn fromHandle(h: Handle) ParentHandle {
        return .{
            .generation = h.generation,
            .index = h.index,
        };
    }
};

pub const Kind = enum(u8) { None, Str, F, U, I, B };

pub const Message = extern struct {
    name: [*:0]const u8,
    value: Value,

    pub const Value = extern union {
        str: [*:0]const u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        pub fn fromRaw(value: [*:0]const u8, t: Kind) Value {
            const len = std.mem.len(@as([*:0]const u8, @ptrCast(value)));
            assert(len > 0 and len <= 63);

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

        pub fn fromSetting(setting: *const Setting.Value, t: Kind) Value {
            return switch (t) {
                .B => .{ .b = setting.b },
                .I => .{ .i = setting.i },
                .U => .{ .u = setting.u },
                .F => .{ .f = setting.f },
                else => .{ .str = &setting.str },
            };
        }
    };

    // FIXME: update all core and plugins with section update functions to use
    //  this in their update loop
    /// convenience function for checking if the setting matches a given handle
    pub fn IsSetting(self: *const Message, name: [*:0]const u8) bool {
        return std.mem.orderZ(u8, self.name, name) == .eq;
    }
};

pub const Setting = struct {
    section: ?ParentHandle = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    value: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_default: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_saved: Value = .{ .str = std.mem.zeroes([63:0]u8) },
    value_type: Kind = .None,
    value_ptr: ?*anyopaque = null,
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (value: Message.Value) callconv(.C) void = null,

    pub const Value = extern union {
        str: [63:0]u8,
        f: f32,
        u: u32,
        i: i32,
        b: bool,

        pub fn fromSent(self: *Value, v: Message.Value, t: Kind) !void {
            switch (t) {
                .F => self.f = v.f,
                .U => self.u = v.u,
                .I => self.i = v.i,
                .B => self.b = v.b,
                else => _ = try bufPrintZ(&self.str, "{s}", .{v.str}),
            }
        }

        /// raw (string) to value
        pub fn raw2type(self: *Value, t: Kind) !void {
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
        pub fn type2raw(self: *Value, t: Kind) !void {
            switch (t) {
                .B => _ = try bufPrintZ(&self.str, "{s}", .{if (self.b) "on" else "off"}),
                .I => _ = try bufPrintZ(&self.str, "{d}", .{self.i}),
                .U => _ = try bufPrintZ(&self.str, "{d}", .{self.u}),
                .F => _ = try bufPrintZ(&self.str, "{d:4.2}", .{self.f}),
                .Str => {},
                else => @panic("setting input value type must not be None"),
            }
        }

        pub fn type2type(self: *Value, t1: Kind, t2: type) !void {
            try self.type2raw(t1);
            try self.raw2type(t2);
        }

        pub fn eql(self: *const Value, other: *const Value, t: Kind) bool {
            return switch (t) {
                .B => self.b == other.b,
                .I => self.i == other.i,
                .U => self.u == other.u,
                .F => self.f == other.f,
                else => return std.mem.orderZ(u8, &self.str, &other.str) == .eq,
            };
        }

        pub fn eqlSent(self: *const Value, other: Message.Value, t: Kind) bool {
            return switch (t) {
                .B => self.b == other.b,
                .I => self.i == other.i,
                .U => self.u == other.u,
                .F => self.f == other.f,
                else => return std.mem.orderZ(u8, &self.str, other.str) == .eq,
            };
        }

        pub fn write(self: *const Value, writer: anytype, t: Kind) !void {
            switch (t) {
                .B => try std.fmt.format(writer, "{s}", .{if (self.b) "on" else "off"}),
                .I => try std.fmt.format(writer, "{d}", .{self.i}),
                .U => try std.fmt.format(writer, "{d}", .{self.u}),
                .F => try std.fmt.format(writer, "{d:4.2}", .{self.f}),
                else => try std.fmt.format(writer, "{s}", .{@as([*:0]const u8, @ptrCast(&self.str))}),
            }
        }

        pub fn writeToPtr(self: *Value, p: *anyopaque, t: Kind) void {
            return switch (t) {
                .Str => @as(*[63:0]u8, @alignCast(@ptrCast(p))).* = @as(*[63:0]u8, @ptrCast(&self.str)).*,
                .F => @as(*f32, @alignCast(@ptrCast(p))).* = @as(*f32, @ptrCast(&self.f)).*,
                .U => @as(*u32, @alignCast(@ptrCast(p))).* = @as(*u32, @ptrCast(&self.u)).*,
                .I => @as(*i32, @alignCast(@ptrCast(p))).* = @as(*i32, @ptrCast(&self.i)).*,
                .B => @as(*bool, @alignCast(@ptrCast(p))).* = @as(*bool, @ptrCast(&self.b)).*,
                else => @panic("setting value type must not be None"),
            };
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
pub const Section = struct {
    section: ?ParentHandle = null,
    name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    fnOnChange: ?*const fn (changed: [*]Message, len: usize) callconv(.C) void = null,

    const Flags = enum(u32) {
        HasOwner,
        AutoSave,
        UpdateQueued,
    };
};

// reserved global settings: AutoSave
pub const SettingManager = struct {
    data_sections: HandleMap(Section, u16) = undefined,
    data_settings: HandleMap(Setting, u16) = undefined,
    flags: EnumSet(Flags) = EnumSet(Flags).initEmpty(),
    hot_reload: HotReloader = undefined,
    file_exists: bool = false,
    skip_next_load: bool = false,
    section_update_queue: ArrayList(Message) = undefined,
    file_name: [:0]const u8 = &.{},

    h_section_plugin: ?Handle = null,
    h_section_core: ?Handle = null,
    h_s_settings_version: ?Handle = null,
    h_s_save_auto: ?Handle = null,
    h_s_save_defaults: ?Handle = null,
    s_settings_version: u32 = 1,
    s_save_auto: bool = true,
    s_save_defaults: bool = true,

    scratch_fba: FixedBufferAllocator = undefined,
    scratch_alloc: Allocator = undefined,

    const Flags = enum(u32) {
        AutoSave,
    };

    pub fn Init(
        out: *SettingManager,
        buf: []u8,
        filename: [:0]const u8,
    ) !void {
        out.* = .{};

        out.file_name = filename;

        out.scratch_fba = FixedBufferAllocator.init(buf);
        out.scratch_alloc = out.scratch_fba.allocator();

        out.data_sections = HandleMap(Section, u16).init(out.scratch_alloc);
        out.data_settings = HandleMap(Setting, u16).init(out.scratch_alloc);
        out.section_update_queue = ArrayList(Message).init(out.scratch_alloc);

        HotReloader.Init(&out.hot_reload, iniLoad, iniUnload);
        out.hot_reload.CheckDelay = 250;
        out.hot_reload.TrackFileAlways(out.file_name, out);

        out.h_s_settings_version =
            try out.settingOccupy(DEFAULT_ID, null, "SETTINGS_VERSION", .U, .{ .u = 0 }, &out.s_settings_version, null);
        out.h_s_save_auto =
            try out.settingOccupy(DEFAULT_ID, null, "SETTINGS_SAVE_AUTO", .B, .{ .b = true }, &out.s_save_auto, null);
        out.h_s_save_defaults =
            try out.settingOccupy(DEFAULT_ID, null, "SETTINGS_SAVE_DEFAULTS", .B, .{ .b = true }, &out.s_save_defaults, null);

        // ensure version is written to file by defaulting to 0 and setting here
        out.settingUpdate(out.h_s_settings_version.?, .{ .u = SETTINGS_VERSION });
    }

    pub fn Deinit(self: *SettingManager) void {
        self.data_sections.deinit();
        self.data_settings.deinit();
        self.section_update_queue.deinit();
    }

    /// gets index of data matching name and parenting pattern
    /// index will be valid for map's data and handle arrays, use handle.index
    /// for sparse_indices array index
    pub fn nodeFind(
        self: *SettingManager,
        map: anytype, // handle_map_*
        parent: ?Handle,
        name: [*:0]const u8,
    ) ?u16 {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        if (parent != null and (parent.?.isNull() or !self.data_sections.hasHandle(parent.?))) return null;

        const name_len = std.mem.len(name) + 1; // include sentinel

        for (map.values.items, 0..) |*v, i| {
            if (!ParentHandle.eql(v.section, parent)) continue;
            if (!std.mem.eql(u8, v.name[0..name_len], name[0..name_len])) continue;
            return @intCast(i);
        }

        return null;
    }

    /// create a new raw section in the data set using a minimal definition. prefer
    /// sectionOccupy for regular api-facing use.
    pub fn sectionNew(
        self: *SettingManager,
        section: ?Handle,
        name: [*:0]const u8,
    ) !Handle {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        if (section != null and
            (section.?.isNull() or
            !self.data_sections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (self.nodeFind(self.data_sections, section, name) != null) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&section_new.name, "{s}", .{name});

        return try self.data_sections.insert(DEFAULT_ID, section_new);
    }

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for settingOccupy)
    /// assign owner to a section.
    /// will prevent all other owners from creating children to the section.
    pub fn sectionOccupy(
        self: *SettingManager,
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        fnOnChange: ?*const fn ([*]Message, usize) callconv(.C) void,
    ) !Handle {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) std.debug.panic("owner mismatch:  owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!self.data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = self.nodeFind(self.data_sections, section, name);

        var data: *Section = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (self.data_sections.handles.items[i].owner != DEFAULT_ID) return error.SectionAlreadyOwned;
            self.data_sections.handles.items[i].owner = owner;
            self.data_sections.sparse_indices.items[self.data_sections.handles.items[i].index].owner = owner;
            handle_new = self.data_sections.handles.items[i];
            data = &self.data_sections.values.items[i];
        } else {
            handle_new = try self.data_sections.insert(owner, .{});
            data = self.data_sections.get(handle_new).?;
            data.section = if (section) |s| .{ .generation = s.generation, .index = s.index } else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        data.fnOnChange = fnOnChange;

        return handle_new;
    }

    /// release ownership of a section node, and all of the children in the settings
    /// tree below it. calls settingVacate on applicable settings.
    pub fn sectionVacate(
        self: *SettingManager,
        handle: Handle,
    ) void {
        var data: *Section = self.data_sections.get(handle) orelse return;

        for (self.data_sections.values.items, 0..) |*s, i| {
            if (s.section != null and ParentHandle.eql(s.section, handle)) {
                const h: Handle = self.data_sections.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) self.sectionVacate(h);
            }
        }

        for (self.data_settings.values.items, 0..) |*s, i| {
            if (s.section != null and ParentHandle.eql(s.section, handle)) {
                const h: Handle = self.data_settings.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) self.settingVacate(h);
            }
        }

        data.fnOnChange = null;

        var s_index: *SparseIndex = &self.data_sections.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        self.data_sections.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// run section update callback on the recently updated settings of that group.
    pub fn sectionRunUpdate(self: *SettingManager, handle: Handle) void {
        const sec: *Section = self.data_sections.get(handle) orelse return;
        const sec_fn = sec.fnOnChange orelse return;

        self.section_update_queue.clearRetainingCapacity();

        for (self.data_settings.values.items) |*s| {
            if (s.section == null or !ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.InSectionUpdateQueue)) continue;
            if (s.value_type == .None) continue;

            s.flags.remove(.InSectionUpdateQueue);
            const send_data = Message{
                .name = &s.name,
                .value = Message.Value.fromSetting(&s.value, s.value_type),
            };
            self.section_update_queue.append(send_data) catch continue;
        }

        sec_fn(self.section_update_queue.items.ptr, self.section_update_queue.items.len);
    }

    /// run sectionRunUpdate on all sections that are occupied by the given owner.
    pub fn sectionRunUpdateOwner(self: *SettingManager, owner: u16) void {
        for (self.data_sections.handles.items) |handle|
            if (handle.owner == owner) self.sectionRunUpdate(handle);
    }

    /// run sectionRunUpdate on all sections.
    pub fn sectionRunUpdateAll(
        self: *SettingManager,
    ) void {
        for (self.data_sections.handles.items) |handle|
            self.sectionRunUpdate(handle);
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the value loaded frome file.
    /// settings that are not on file are not affected.
    pub fn sectionResetToSaved(self: *SettingManager, handle: ?Handle) void {
        for (self.data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.SavedValueIsSet)) continue;

            s.value = s.value_saved;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn sectionResetToDefaults(self: *SettingManager, handle: ?Handle) void {
        for (self.data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.DefaultValueIsSet)) continue;

            s.value = s.value_default;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings that are direct children of the section associated
    /// with the given handle, removing their data entirely
    pub fn sectionRemoveVacant(self: *SettingManager, handle: ?Handle) void {
        const slices = self.data_settings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.flags);

        const len = self.data_settings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (!ParentHandle.eql(sl_sec[i], handle)) continue;
            if (sl_fl[i].contains(.DefaultValueIsSet)) continue;
            _ = self.data_settings.remove(self.data_settings.handles.items[i]);
        }
    }

    /// create a new raw setting in the data set using a minimal definition. prefer
    /// settingOccupy for regular api-facing use.
    pub fn settingNew(
        self: *SettingManager,
        section: ?Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> value_saved
        from_file: bool,
    ) !Handle {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);
        assert(std.mem.len(value) > 0 and std.mem.len(value) <= 63);

        if (section != null and
            (section.?.isNull() or
            !self.data_sections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (self.nodeFind(self.data_settings, section, name) != null) return error.NameTaken;

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

        return try self.data_settings.insert(DEFAULT_ID, setting);
    }

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for sectionOccupy)
    // FIXME: test - output handle contains input owner (same for sectionOccupy)
    /// assign an owner to a setting and apply a definition, creating the setting
    /// data if needed. will update value in external pointer callback to run update
    /// callback using the initial value (the existing value if available, or the default)
    pub fn settingOccupy(
        self: *SettingManager,
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        value_type: Kind,
        value_default: Message.Value,
        value_ptr: ?*anyopaque,
        fnOnChange: ?*const fn (Message.Value) callconv(.C) void,
    ) !Handle {
        assert(value_type != .None);
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) std.debug.panic("owner mismatch:  owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!self.data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = self.nodeFind(self.data_settings, section, name);

        var data: *Setting = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (self.data_settings.handles.items[i].owner != DEFAULT_ID) return error.SettingAlreadyOwned;
            self.data_settings.handles.items[i].owner = owner;
            self.data_settings.sparse_indices.items[self.data_settings.handles.items[i].index].owner = owner;
            handle_new = self.data_settings.handles.items[i];
            data = &self.data_settings.values.items[i];
        } else {
            handle_new = try self.data_settings.insert(owner, .{});
            data = self.data_settings.get(handle_new).?;
            data.section = if (section) |s| ParentHandle.fromHandle(s) else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        // NOTE: existing data assumed to be raw (new, unprocessed or released)
        if (data.flags.contains(.ValueIsSet)) {
            data.value.raw2type(value_type) catch {
                // invalid data = use default, will be cleaned next file write
                data.value.fromSent(value_default, value_type) catch unreachable; // value_type assertion = OK
            };
            if (!data.value.eqlSent(value_default, value_type))
                data.flags.insert(.InSectionUpdateQueue);
            if (data.flags.contains(.SavedValueIsSet))
                data.value_saved.raw2type(value_type) catch data.flags.insert(.SavedValueNotConverted);
        } else {
            data.value.fromSent(value_default, value_type) catch unreachable; // value_type assertion = OK
            data.flags.insert(.ValueIsSet);
        }
        data.value_type = value_type;
        data.value_default.fromSent(value_default, value_type) catch unreachable; // value_type assertion = OK
        data.flags.insert(.DefaultValueIsSet);

        data.value_ptr = value_ptr;
        if (value_ptr) |p| data.value.writeToPtr(p, data.value_type);

        data.fnOnChange = fnOnChange;
        if (fnOnChange) |f| f(Message.Value.fromSetting(&data.value, data.value_type));

        return handle_new;
    }

    /// remove owner from a setting and clear its definition.
    pub fn settingVacate(
        self: *SettingManager,
        handle: Handle,
    ) void {
        var data: *Setting = self.data_settings.get(handle) orelse return;
        assert(data.flags.contains(.ValueIsSet));

        data.fnOnChange = null;

        data.value_default = .{ .str = std.mem.zeroes([63:0]u8) };
        data.flags.remove(.DefaultValueIsSet);

        data.value.type2raw(data.value_type) catch @panic("settingVacate: 'value' invalid");
        if (!data.flags.contains(.SavedValueNotConverted))
            data.value_saved.type2raw(data.value_type) catch @panic("settingVacate: 'value_saved' invalid");
        data.flags.remove(.SavedValueNotConverted);

        data.value_type = .None;

        var s_index: *SparseIndex = &self.data_settings.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        self.data_settings.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// trigger setting update with new value.
    /// will update value in external pointer callback to run update callback.
    pub fn settingUpdate(
        self: *SettingManager,
        handle: Handle,
        value: Message.Value,
    ) void {
        var s: *Setting = self.data_settings.get(handle) orelse return;

        if (s.value.eqlSent(value, s.value_type)) return;

        s.value.fromSent(value, s.value_type) catch return;

        s.flags.insert(.InSectionUpdateQueue);
        if (s.value_ptr) |p| s.value.writeToPtr(p, s.value_type);
        if (s.fnOnChange) |f| f(value);
    }

    /// restore all settings to the value loaded from file.
    /// settings that are not on file are not affected.
    pub fn settingResetAllToSaved(
        self: *SettingManager,
    ) void {
        for (self.data_settings.values.items) |*s| {
            if (!s.flags.contains(.SavedValueIsSet)) continue;
            s.value = s.value_saved;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn settingResetAllToDefaults(
        self: *SettingManager,
    ) void {
        for (self.data_settings.values.items) |*s| {
            if (!s.flags.contains(.DefaultValueIsSet)) continue;
            s.value = s.value_default;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings, removing their data entirely
    pub fn settingRemoveAllVacant(
        self: *SettingManager,
    ) void {
        const len = self.data_settings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (self.data_settings.values.items[i].flags.contains(.DefaultValueIsSet)) continue;
            _ = self.data_settings.remove(self.data_settings.handles.items[i]);
        }
    }

    /// free all sections and settings of the given owner, allowing them to be
    /// assigned a new owner
    pub fn vacateOwner(self: *SettingManager, owner: u16) void {
        // settings first for better cache use of data_settings processes
        for (self.data_settings.handles.items) |h|
            if (h.owner == owner) self.settingVacate(h);

        for (self.data_sections.handles.items) |h|
            if (h.owner == owner) self.sectionVacate(h);
    }

    // TODO: convert to reader to match iniWrite?
    /// read ini-formatted settings from file
    pub fn iniRead(self: *SettingManager, gpa: Allocator, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        //var file_br = std.io.bufferedReader(file.reader());
        //const file_r = file_br.reader();
        const file_r = file.reader();

        var parser = ini.parse(gpa, file_r);
        defer parser.deinit();

        var sec_handle: ?Handle = null;
        while (try parser.next()) |record| {
            switch (record) {
                .section => |name| {
                    const section_i = self.nodeFind(self.data_sections, null, name);
                    sec_handle = if (section_i) |i|
                        self.data_sections.handles.items[i]
                    else
                        self.sectionNew(null, name) catch null;
                },
                .property => |kv| {
                    const setting_i = self.nodeFind(self.data_settings, sec_handle, kv.key);
                    if (setting_i) |i| {
                        const s = &self.data_settings.values.items[i];
                        const h = self.data_settings.handles.items[i];

                        // don't override value that has already been changed by something else
                        if (s.flags.contains(.SavedValueIsSet) and
                            !s.value.eql(&s.value_saved, s.value_type)) continue;

                        const send_val = Message.Value.fromRaw(kv.value, s.value_type);

                        if (!s.value_saved.eqlSent(send_val, s.value_type))
                            try s.value_saved.fromSent(send_val, s.value_type);

                        if (!s.value.eqlSent(send_val, s.value_type))
                            self.settingUpdate(h, send_val);
                    } else {
                        _ = try self.settingNew(sec_handle, kv.key, kv.value, true);
                    }
                },
                .enumeration => |value| { // FIXME: impl
                    _ = value;
                },
            }
        }

        self.sectionRunUpdateAll();
    }

    // callback for HotReload(HotReloadHandle)
    // stub because the settings live throughout the whole program lifetime and
    // will only be updated if a reload occurs
    fn iniUnload(_: ?*SettingManager, _: [:0]const u8, _: [:0]const u8) void {}

    // callback for HotReload(HotReloadHandle)
    /// read settings from file
    fn iniLoad(self: ?*SettingManager, filepath: [:0]const u8, _: [:0]const u8) bool {
        assert(self != null);
        assert(std.mem.eql(u8, self.?.file_name, filepath));

        if (self.?.skip_next_load) {
            self.?.skip_next_load = false;
            return false; // TODO: should be true or false? no effect in current logic tho
        }

        self.?.iniRead(self.?.scratch_alloc, self.?.file_name) catch return false;

        self.?.file_exists = true;
        return true;
    }

    /// write all settings to buffer in ini format
    pub fn iniWrite(self: *SettingManager, writer: anytype) !void {
        try self.iniWriteSection(writer, null);
        for (self.data_sections.handles.items) |h|
            try self.iniWriteSection(writer, h);
    }

    // TODO: sorting both settings and sections?
    /// write settings section to buffer in ini format
    fn iniWriteSection(self: *SettingManager, writer: anytype, handle: ?Handle) !void {
        if (handle) |h| blk: {
            const section: *Section = self.data_sections.get(h) orelse break :blk;
            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&section.name)));
            _ = try writer.write("[");
            _ = try writer.write(section.name[0..nlen]);
            _ = try writer.write("]\n");
        }

        for (self.data_settings.values.items) |*s| {
            if (!s.flags.contains(.InFileWriteQueue) or !ParentHandle.eql(s.section, handle)) continue;

            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&s.name)));
            _ = try writer.write(s.name[0..nlen]);
            _ = try writer.write(" = ");
            try s.value.write(writer, s.value_type);
            _ = try writer.write("\n");

            s.flags.remove(.InFileWriteQueue);
        }

        _ = writer.write("\n") catch {};
    }

    /// write settings to file
    pub fn save(
        self: *SettingManager,
    ) !void {
        const changed_settings: u32 = self.savePrepare();
        if (changed_settings == 0 and (self.s_save_defaults and self.file_exists)) return;

        const file = try std.fs.cwd().createFile(self.file_name, .{}); // .exclusive=true for no file rewrite
        defer file.close();
        var file_bw = std.io.bufferedWriter(file.writer());
        defer _ = file_bw.flush() catch |e|
            std.debug.panic("ASettings(save): write buffer flush: {s}", .{@errorName(e)});
        const file_w = file_bw.writer();

        try self.iniWrite(file_w);
        self.skip_next_load = true;
        self.file_exists = true;

        self.saveCleanup();
    }

    /// write settings to file, but only if autosave setting is enabled
    pub fn saveAuto(self: *SettingManager) !void {
        if (self.s_save_auto)
            try self.save();
    }

    /// post-processing of sections and settings, to make settings ready for next write
    fn saveCleanup(self: *SettingManager) void {
        for (self.data_settings.values.items) |*s| {
            // make sure system knows which settings are no longer on file
            if (!s.flags.contains(.FileUpdatedLastWrite))
                s.flags.remove(.SavedValueIsSet);

            s.flags.remove(.FileUpdatedLastWrite);
        }
    }

    // TODO: convert to flattened version of savePrepareSection logic? OR only call prep
    // on sections marked for saving? i.e. need to handle 'save only one section' case
    /// pre-pass on settings to determine which settings need to be written and how
    /// write functions assume settings are tagged correctly as a result of running this step
    /// @return     number of settings that would actually change in the file as a result of writing
    fn savePrepare(self: *SettingManager) u32 {
        var changed: u32 = 0;

        changed += self.savePrepareSection(null);
        for (self.data_sections.handles.items) |h|
            changed += self.savePrepareSection(h);

        return changed;
    }

    /// see savePrepare for explanation
    /// @return     number of settings that would actually change in the file as a result of writing
    fn savePrepareSection(self: *SettingManager, handle: ?Handle) u32 {
        var changed: u32 = 0;
        for (self.data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;

            // only keep uninitialized settings if they were already on file
            if (!s.flags.contains(.DefaultValueIsSet) and
                !s.flags.contains(.SavedValueIsSet)) continue;

            // only store initialized settings if they are not default
            if (!self.s_save_defaults and s.flags.contains(.DefaultValueIsSet) and
                s.value_default.eql(&s.value, s.value_type)) continue;

            if ((s.flags.contains(.SavedValueIsSet) and !s.value_saved.eql(&s.value, s.value_type)) or
                (!s.flags.contains(.SavedValueIsSet) and self.s_save_defaults))
                changed += 1;

            s.value_saved = s.value;
            s.flags.insert(.SavedValueIsSet);
            s.flags.insert(.FileUpdatedLastWrite);

            s.flags.insert(.InFileWriteQueue);
        }
        return changed;
    }
};

// -----------------------------------------------------------------------------
// DEBUGGING & TESTING

// NOTE: use in testing
fn testUpdateSet1(_: Message.Value) callconv(.C) void {
    //dbg.ConsoleOut("set1 changed to {d:4.2}\n", .{value.f}) catch {};
}

// TODO: tests ensuring updated values actually propagate (i.e. the comparison
//  returns the correct equality), particularly similar strings of different lengths
//  such as "hd"->"hda"
// TODO: impl testing in build script; cannot test statically because imports out of scope
// TODO: move testing stuff to here but commented in meantime
test {
    // TODO: move below to commented test block
    // TODO: add setting occupy -> string type test
    // TODO: use actual owner IDs that don't clash (or just make sure it's all actually test scoped)

    //const sec_base = ASettings.sectionNew(null, "TestBaseSection") catch NullHandle;
    //_ = ASettings.sectionNew(sec_base, "Sec1") catch {};
    //_ = ASettings.sectionNew(sec_base, "Sec2") catch {};
    //_ = ASettings.sectionNew(sec_base, "Sec2") catch {}; // expect: NameTaken error -> skipped
    //const sec1 = ASettings.sectionOccupy(0xF000, sec_base, "Sec1", null) catch NullHandle;
    //const sec2 = ASettings.sectionOccupy(0xF001, sec_base, "Sec2", null) catch NullHandle;

    //_ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.settingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.settingNew(null, "Set2", "Val2", false) catch {};
    //_ = ASettings.settingNew(sec2, "Set3", "Val3", false) catch {};
    //_ = ASettings.settingNew(null, "Set4", "Val4", false) catch {};
    //_ = ASettings.settingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    //_ = ASettings.settingNew(null, "Set5", "Val5", false) catch {};

    //const occ1 = ASettings.settingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, testUpdateSet1) catch NullHandle;
    //_ = ASettings.settingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, null) catch {}; // expect: ignored
    //const occ2 = ASettings.settingOccupy(0xF000, null, "Set6", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //_ = ASettings.settingOccupy(0xF000, null, "Set6", .F, .{ .f = 876.543 }, null, null) catch {}; // export: ignored

    //ASettings.settingUpdate(occ1, .{ .f = 678.543 }); // expect: changed value
    //ASettings.settingVacate(occ2); // expect: undefined default, etc.

    //const sec3 = ASettings.sectionOccupy(0xF001, sec2, "Sec3", null) catch NullHandle;
    //_ = ASettings.settingNew(sec3, "Set7", "Val7", false) catch {};
    //_ = ASettings.settingOccupy(0xF001, sec3, "Set8", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //ASettings.sectionVacate(sec3);

    //ASettings.vacateOwner(0xF000); // expect: everything undefined default, etc.
}
