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

const HandleMap = @import("../util/handle_map.zig").HandleMap;
const SparseIndex = @import("../util/handle_map.zig").SparseIndex(u16);
pub const Handle = @import("../util/handle_map.zig").Handle(u16);
pub const NullHandle = Handle.getNull();

const PPanic = @import("../util/debug.zig").PPanic;

const r = @import("racer");
const rt = r.Text;

// TODO: add global st/fn ptrs to fnOnChange defs?

// SYSTEM OVERVIEW
// - support for bool, u32, i32, f32, and strings (64 bytes null-terminated)
// - settings stored as tree, with branch nodes representing sections/categories
// - tree is expanded on demand; not pre-seeded by design, to maximize flexibility
// - handle-based ownership of setting and section nodes
// - setting and section defs merged from different sources as needed, as long as no ownership conflict
// - callback behaviours available for both individual settings updates and collective section updates
// - settings hot-loaded from file; game-side changes written to file periodically

// PLUGIN DEVELOPER NOTES
// - use ASettingSectionOccupy to define a setting category
// - then, use ASettingOccupy to assign settings to the category
// - prefer doing this setup during OnInit, and prefer using plugin name for
//   section to avoid naming collisions
// - define setting value_ptr to save you the trouble of updating your local value manually
// - define setting fnOnChange to do any post-processing on setting update automatically
// - setting callback and pointer update will happen after setting is occupied, whenever
//   the value changes on file, and when you call ASettingUpdate
// - define section fnOnChange to do any settings coordination needed, e.g. for
//   multi-setting derived values
// - section callback will run after OnInit, and whenever values change on file; call
//   ASettingSectionRunUpdate to manually run the section callback, e.g. after closing
//   a related plugin menu
// - various cleanup functions are available in the api; batch vacating will be
//   done for you after OnDeinit
// - see official plugin source code for usage examples; cam7 is a good place to start

// DEFS

const SETTINGS_VERSION: u32 = 2;
const DEFAULT_ID = 0xFFFF; // TODO: use ASettings plugin id?
const FILENAME = "annodue/settings.ini";
const FILENAME_TEST = "annodue/settings_test.ini";
const FILENAME_ACTIVE = FILENAME_TEST;

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
        pub fn fromSent(self: *Value, v: ASettingSent.Value, t: Type) !void {
            switch (t) {
                .F => self.f = v.f,
                .U => self.u = v.u,
                .I => self.i = v.i,
                .B => self.b = v.b,
                else => _ = try bufPrintZ(&self.str, "{s}", .{v.str}),
            }
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

        pub fn writeToPtr(self: *Value, p: *anyopaque, t: Type) void {
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
    var data_sections: HandleMap(Section, u16) = undefined;
    var data_settings: HandleMap(Setting, u16) = undefined;
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
        data_sections = HandleMap(Section, u16).init(alloc);
        data_settings = HandleMap(Setting, u16).init(alloc);
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
        if (parent != null and (parent.?.isNull() or !data_sections.hasHandle(parent.?))) return null;

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
        section: ?Handle,
        name: [*:0]const u8,
    ) !Handle {
        if (section != null and
            (section.?.isNull() or
            !data_sections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (nodeFind(data_sections, section, name) != null) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.section = .{ .generation = s.generation, .index = s.index };
        _ = try bufPrintZ(&section_new.name, "{s}", .{name});

        return try data_sections.insert(DEFAULT_ID, section_new);
    }

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for settingOccupy)
    // FIXME: use data ref instead of making new data item? also applies to settingOccupy, maybe others
    // FIXME: impl 'update owner' function in handle_map for cases like here?
    // search for 'sparse_indices.items[' for all uses
    /// assign owner to a section.
    /// will prevent all other owners from creating children to the section.
    pub fn sectionOccupy(
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        fnOnChange: ?*const fn ([*]ASettingSent, usize) callconv(.C) void,
    ) !Handle {
        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) PPanic("owners must match - owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = nodeFind(data_sections, section, name);

        var data: *Section = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (data_sections.handles.items[i].owner != DEFAULT_ID) return error.SectionAlreadyOwned;
            data_sections.handles.items[i].owner = owner;
            data_sections.sparse_indices.items[data_sections.handles.items[i].index].owner = owner;
            handle_new = data_sections.handles.items[i];
            data = &data_sections.values.items[i];
        } else {
            handle_new = try data_sections.insert(owner, .{});
            data = data_sections.get(handle_new).?;
            data.section = if (section) |s| .{ .generation = s.generation, .index = s.index } else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        data.fnOnChange = fnOnChange;

        return handle_new;
    }

    /// release ownership of a section node, and all of the children in the settings
    /// tree below it. calls settingVacate on applicable settings.
    pub fn sectionVacate(
        handle: Handle,
    ) void {
        var data: *Section = data_sections.get(handle) orelse return;

        for (data_sections.values.items, 0..) |*s, i| {
            if (s.section != null and ParentHandle.eql(s.section, handle)) {
                const h: Handle = data_sections.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) sectionVacate(h);
            }
        }

        for (data_settings.values.items, 0..) |*s, i| {
            if (s.section != null and ParentHandle.eql(s.section, handle)) {
                const h: Handle = data_settings.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) settingVacate(h);
            }
        }

        data.fnOnChange = null;

        var s_index: *SparseIndex = &data_sections.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        data_sections.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// run section update callback on the recently updated settings of that group.
    pub fn sectionRunUpdate(handle: Handle) void {
        const sec: *Section = data_sections.get(handle) orelse return;
        const sec_fn = sec.fnOnChange orelse return;

        section_update_queue.clearRetainingCapacity();

        for (data_settings.values.items) |*s| {
            if (s.section == null or !ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.InSectionUpdateQueue)) continue;
            if (s.value_type == .None) continue;

            s.flags.remove(.InSectionUpdateQueue);
            const send_data = ASettingSent{
                .name = &s.name,
                .value = ASettingSent.Value.fromSetting(&s.value, s.value_type),
            };
            section_update_queue.append(send_data) catch continue;
        }

        sec_fn(section_update_queue.items.ptr, section_update_queue.items.len);
    }

    /// run sectionRunUpdate on all sections that are occupied by the given owner.
    pub fn sectionRunUpdateOwner(owner: u16) void {
        for (data_sections.handles.items) |handle|
            if (handle.owner == owner) sectionRunUpdate(handle);
    }

    /// run sectionRunUpdate on all sections.
    pub fn sectionRunUpdateAll() void {
        for (data_sections.handles.items) |handle|
            sectionRunUpdate(handle);
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the value loaded frome file.
    /// settings that are not on file are not affected.
    pub fn sectionResetToSaved(handle: ?Handle) void {
        for (data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.SavedValueIsSet)) continue;

            s.value = s.value_saved;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn sectionResetToDefaults(handle: ?Handle) void {
        for (data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;
            if (!s.flags.contains(.DefaultValueIsSet)) continue;

            s.value = s.value_default;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings that are direct children of the section associated
    /// with the given handle, removing their data entirely
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

    /// create a new raw setting in the data set using a minimal definition. prefer
    /// settingOccupy for regular api-facing use.
    pub fn settingNew(
        section: ?Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> value_saved
        from_file: bool,
    ) !Handle {
        if (section != null and
            (section.?.isNull() or
            !data_sections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

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

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for sectionOccupy)
    // FIXME: assert input name length (also do so for other functions)
    // FIXME: test - output handle contains input owner (same for sectionOccupy)
    // FIXME: error handling (catch unreachable)
    /// assign an owner to a setting and apply a definition, creating the setting
    /// data if needed. will update value in external pointer callback to run update
    /// callback using the initial value (the existing value if available, or the default)
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
            if (s.owner != owner) PPanic("owners must match - owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!data_sections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = nodeFind(data_settings, section, name);

        var data: *Setting = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (data_settings.handles.items[i].owner != DEFAULT_ID) return error.SettingAlreadyOwned;
            data_settings.handles.items[i].owner = owner;
            data_settings.sparse_indices.items[data_settings.handles.items[i].index].owner = owner;
            handle_new = data_settings.handles.items[i];
            data = &data_settings.values.items[i];
        } else {
            handle_new = try data_settings.insert(owner, .{});
            data = data_settings.get(handle_new).?;
            data.section = if (section) |s| ParentHandle.fromHandle(s) else null;
            _ = try bufPrintZ(&data.name, "{s}", .{name});
        }

        // NOTE: existing data assumed to be raw (new, unprocessed or released)
        if (data.flags.contains(.ValueIsSet)) {
            data.value.raw2type(value_type) catch {
                // invalid data = use default, will be cleaned next file write
                data.value.fromSent(value_default, value_type) catch unreachable;
            };
            if (!data.value.eqlSent(value_default, value_type))
                data.flags.insert(.InSectionUpdateQueue);
            if (data.flags.contains(.SavedValueIsSet))
                data.value_saved.raw2type(value_type) catch data.flags.insert(.SavedValueNotConverted);
        } else {
            data.value.fromSent(value_default, value_type) catch unreachable;
            data.flags.insert(.ValueIsSet);
        }
        data.value_type = value_type;
        data.value_default.fromSent(value_default, value_type) catch unreachable;
        data.flags.insert(.DefaultValueIsSet);

        data.value_ptr = value_ptr;
        if (value_ptr) |p| data.value.writeToPtr(p, data.value_type);

        data.fnOnChange = fnOnChange;
        if (fnOnChange) |f| f(ASettingSent.Value.fromSetting(&data.value, data.value_type));

        return handle_new;
    }

    /// remove owner from a setting and clear its definition.
    pub fn settingVacate(
        handle: Handle,
    ) void {
        var data: *Setting = data_settings.get(handle) orelse return;
        std.debug.assert(data.flags.contains(.ValueIsSet));

        data.fnOnChange = null;

        data.value_default = .{ .str = std.mem.zeroes([63:0]u8) };
        data.flags.remove(.DefaultValueIsSet);

        data.value.type2raw(data.value_type) catch @panic("settingVacate: 'value' invalid");
        if (!data.flags.contains(.SavedValueNotConverted))
            data.value_saved.type2raw(data.value_type) catch @panic("settingVacate: 'value_saved' invalid");
        data.flags.remove(.SavedValueNotConverted);

        data.value_type = .None;

        var s_index: *SparseIndex = &data_settings.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        data_settings.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// trigger setting update with new value.
    /// will update value in external pointer callback to run update callback.
    pub fn settingUpdate(
        handle: Handle,
        value: ASettingSent.Value,
    ) void {
        var s: *Setting = data_settings.get(handle) orelse return;

        if (s.value.eqlSent(value, s.value_type)) return;

        s.value.fromSent(value, s.value_type) catch return;

        s.flags.insert(.InSectionUpdateQueue);
        if (s.value_ptr) |p| s.value.writeToPtr(p, s.value_type);
        if (s.fnOnChange) |f| f(value);
    }

    /// restore all settings to the value loaded from file.
    /// settings that are not on file are not affected.
    pub fn settingResetAllToSaved() void {
        for (data_settings.values.items) |*s| {
            if (!s.flags.contains(.SavedValueIsSet)) continue;
            s.value = s.value_saved;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn settingResetAllToDefaults() void {
        for (data_settings.values.items) |*s| {
            if (!s.flags.contains(.DefaultValueIsSet)) continue;
            s.value = s.value_default;
            s.flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings, removing their data entirely
    pub fn settingRemoveAllVacant() void {
        const len = data_settings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (data_settings.values.items[i].flags.contains(.DefaultValueIsSet)) continue;
            _ = data_settings.remove(data_settings.handles.items[i]);
        }
    }

    /// free all sections and settings of the given owner, allowing them to be
    /// assigned a new owner
    pub fn vacateOwner(owner: u16) void {
        // settings first for better cache use of data_settings processes
        for (ASettings.data_settings.handles.items) |h|
            if (h.owner == owner) ASettings.settingVacate(h);

        for (ASettings.data_sections.handles.items) |h|
            if (h.owner == owner) ASettings.sectionVacate(h);
    }

    // TODO: convert to reader to match iniWrite?
    /// read ini-formatted settings from file
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
                        const s = &data_settings.values.items[i];
                        const h = data_settings.handles.items[i];

                        // don't override value that has already been changed by something else
                        if (s.flags.contains(.SavedValueIsSet) and
                            !s.value.eql(&s.value_saved, s.value_type)) continue;

                        const send_val = ASettingSent.Value.fromRaw(kv.value, s.value_type);

                        if (!s.value_saved.eqlSent(send_val, s.value_type))
                            try s.value_saved.fromSent(send_val, s.value_type);

                        if (!s.value.eqlSent(send_val, s.value_type))
                            settingUpdate(h, send_val);
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

    /// read settings from file
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

    /// write all settings to buffer in ini format
    pub fn iniWrite(writer: anytype) !void {
        try iniWriteSection(writer, null);
        for (data_sections.handles.items) |h|
            try iniWriteSection(writer, h);
    }

    // TODO: sorting both settings and sections?
    // TODO: track and output whether file had changes?
    /// write settings section to buffer in ini format
    fn iniWriteSection(writer: anytype, handle: ?Handle) !void {
        if (handle) |h| blk: {
            const section: *Section = data_sections.get(h) orelse break :blk;
            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&section.name)));
            _ = try writer.write("[");
            _ = try writer.write(section.name[0..nlen]);
            _ = try writer.write("]\n");
        }

        for (data_settings.values.items) |*s| {
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

    /// write settings to file, but only if autosave setting is enabled
    fn saveAuto() !void {
        if (s_save_auto)
            try save();
    }

    /// post-processing of sections and settings, to make settings ready for next write
    fn saveCleanup() void {
        for (data_settings.values.items) |*s| {
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
    fn savePrepare() u32 {
        var changed: u32 = 0;

        changed += savePrepareSection(null);
        for (data_sections.handles.items) |h|
            changed += savePrepareSection(h);

        return changed;
    }

    /// see savePrepare for explanation
    /// @return     number of settings that would actually change in the file as a result of writing
    fn savePrepareSection(handle: ?Handle) u32 {
        var changed: u32 = 0;
        for (data_settings.values.items) |*s| {
            if (!ParentHandle.eql(s.section, handle)) continue;

            // only keep uninitialized settings if they were already on file
            if (!s.flags.contains(.DefaultValueIsSet) and
                !s.flags.contains(.SavedValueIsSet)) continue;

            // only store initialized settings if they are not default
            if (!s_save_defaults and s.flags.contains(.DefaultValueIsSet) and
                s.value_default.eql(&s.value, s.value_type)) continue;

            if ((s.flags.contains(.SavedValueIsSet) and !s.value_saved.eql(&s.value, s.value_type)) or
                (!s.flags.contains(.SavedValueIsSet) and s_save_defaults))
                changed += 1;

            s.value_saved = s.value;
            s.flags.insert(.SavedValueIsSet);
            s.flags.insert(.FileUpdatedLastWrite);

            s.flags.insert(.InFileWriteQueue);
        }
        return changed;
    }
};

// GLOBAL

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

// CORE MODULE EXPORTS

// TODO: generally - make the plugin-facing stuff operate under 'plugin' section,
// which is initialized internally; same for core, identify via id range check.
// i.e. settings tree looks like this after moving to json-based settings
// [root]
// - <global stuff goes here>
// - core
// -- <insert here when core module using ASetting* with null parent>
// - plugin
// -- <insert here when plugin using ASetting* with null parent>

/// take ownership of a section and apply a definition
/// @section        section handle of desired parent as received from ASettingSectionOccupy; use
///                 NullHandle for no parent
/// @name           identifying string for section; max 63 chars, used to represent the section on file
/// @fnOnChange     callback function that will be run on all recently updated settings in this section
///                 collectively when ASettingSectionRunUpdate is called; use this to post-process
///                 settings that are needed to work in tandem to derive a value
/// @return         handle to section
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

/// release ownership of a section and all its children, automatically running
/// ASettingVacate as needed.
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionVacate(handle: Handle) callconv(.C) void {
    ASettings.sectionVacate(handle);
}

/// manually call fnOnChange section callback on any 'changed' settings
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionRunUpdate(handle: Handle) callconv(.C) void {
    ASettings.sectionRunUpdate(handle);
}

/// revert entries under the given section back to owner-defined defaults
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionResetDefault(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToDefaults(handle);
}

/// revert entries under the given section back to values on file
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionResetFile(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToSaved(handle);
}

/// remove superfluous entries loaded from file under the given section
/// will be reflected in the settings file on the following save write
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionClean(handle: Handle) callconv(.C) void {
    ASettings.sectionResetToDefaults(handle);
}

// FIXME: logging - error before returning NullHandle (do same with ASectionOccupy)
/// take ownership of a setting and apply a definition
/// setting will be rejected if caller is plugin and no valid section handle is provided
/// @section        section handle of desired parent as received from ASettingSectionOccupy; use
///                 NullHandle for no parent
/// @name           identifying string for setting; max 63 chars, used to represent the setting on file
/// @value_type     enum value corresponding to string, u32, i32, f32 or bool types. max 63 chars for strings
/// @value_default  union interpreted as the type specified by @value_type
/// @value_ptr      memory location to be automatically updated with value via ASettingUpdate
/// @fnOnChange     callback function that will be run when the value is updated with ASettingUpdate
/// @return         handle to setting
pub fn ASettingOccupy(
    section: Handle,
    name: [*:0]const u8,
    value_type: Setting.Type,
    value_default: ASettingSent.Value,
    value_ptr: ?*anyopaque,
    fnOnChange: ?*const fn (ASettingSent.Value) callconv(.C) void,
) callconv(.C) Handle {
    if (!workingOwnerIsSystem() and section.isNull()) return NullHandle;
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

/// release ownership of a setting, clearing its definition and internally
/// returning the value to raw (string-formatted) data.
/// @handle     setting handle as received from ASettingOccupy
pub fn ASettingVacate(handle: Handle) callconv(.C) void {
    ASettings.settingVacate(handle);
}

/// update setting with a new value, passing on the value to the defined
/// external sources.
/// @handle     setting handle as received from ASettingOccupy
/// @value      union interpreted as the type defined with ASettingOccupy
pub fn ASettingUpdate(handle: Handle, value: ASettingSent.Value) callconv(.C) void {
    ASettings.settingUpdate(handle, value);
}

/// release ownership and definitions of all sections and settings associated
/// with the caller.
/// for internal use; will do nothing if caller is plugin
pub fn AVacateAll() callconv(.C) void {
    if (!workingOwnerIsSystem()) return;
    ASettings.vacateOwner(workingOwner());
}

/// revert all entries back to owner-defined defaults
/// for internal use; will do nothing if caller is plugin
pub fn ASettingResetAllDefault() callconv(.C) void {
    if (!workingOwnerIsSystem()) return;
    ASettings.settingResetAllToDefaults();
}

/// revert all entries back to values on file
/// for internal use; will do nothing if caller is plugin
pub fn ASettingResetAllFile() callconv(.C) void {
    if (!workingOwnerIsSystem()) return;
    ASettings.settingResetAllToSaved();
}

/// remove all superfluous entries loaded from file
/// will be reflected in the settings file on the following save write
/// for internal use; will do nothing if caller is plugin
pub fn ASettingCleanAll() callconv(.C) void {
    if (!workingOwnerIsSystem()) return;
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
    for (ASettings.data_settings.values.items) |value| {
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

    for (0..ASettings.data_sections.values.items.len) |i| {
        const value: *Section = &ASettings.data_sections.values.items[i];
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
