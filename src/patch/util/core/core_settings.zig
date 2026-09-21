//! simple settings management
//!
//! - ini-based
//! - hot-reloadable

// SYSTEM OVERVIEW
// - support for bool, u32, i32, f32, and strings (64 bytes null-terminated)
// - settings stored as tree, with branch nodes representing sections/categories
// - tree is expanded on demand; not pre-seeded by design, to maximize flexibility
// - handle-based ownership of setting and section nodes
// - setting and section defs merged from different sources as needed, as long as no ownership conflict
// - callback behaviours available for both individual settings updates and collective section updates
// - settings hot-loaded from file; game-side changes written to file periodically

// TODO: tests and api hardening, prior to reworking settings for sqlite or whatever
// TODO: ?? change DEFAULT_ID
// TODO: add global st/fn ptrs to fnOnChange defs?
// TODO: change save_defaults to false once annodue stops releasing Safe builds (also in SettingOccupy call)
// TODO: minor cleanup with handle_map 'update owner' fn?
// TODO: ?? update nomenclature from 'Occupy' -> 'Register', also 'Sent' -> 'Msg'?
// FIXME: is it necessary to have an explicit default value passed to SettingOccupy
//  when the default could be derived from the pointer? isn't it a bug to even
//  allow calling ASettingOccupy without either a value pointer or an update callback?

const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const EnumSet = std.EnumSet;
const bufPrintZ = std.fmt.bufPrintZ;
const assert = std.debug.assert;
const panic = std.debug.panic;

const ini = @import("zigini");

const HandleMap = @import("../handle_map.zig").HandleMap;
const SparseIndex = @import("../handle_map.zig").SparseIndex(u16);
pub const Handle = @import("../handle_map.zig").Handle(u16);
pub const HANDLE_NULL = Handle.getNull();

const MiB = @import("../base/base_memory.zig").MiB;

const HotReloaderHandle = ?*SettingManager;
const HotReloader = @import("../hot_reload.zig").HotReload(HotReloaderHandle, 1);

// DEFS

pub const SETTINGS_VERSION: u32 = 2;
const DEFAULT_ID = 0xFFFF;

const ParentHandle = extern struct {
    Generation: u16,
    Index: u16,

    /// helper to test equality of nullable parent and regular handles
    fn Eql(p: ?ParentHandle, h: ?Handle) bool {
        if ((p == null) != (h == null)) return false;
        if (p != null and (p.?.Index != h.?.index or p.?.Generation != h.?.generation)) return false;
        return true;
    }

    fn FromHandle(h: Handle) ParentHandle {
        return .{
            .Generation = h.generation,
            .Index = h.index,
        };
    }
};

pub const Kind = enum(u8) { None, Str, F, U, I, B };

pub const Message = extern struct {
    Name: [*:0]const u8,
    Value: MessageValue,
};

pub const MessageValue = extern union {
    Str: [*:0]const u8,
    F: f32,
    U: u32,
    I: i32,
    B: bool,

    pub fn FromRaw(value: [*:0]const u8, t: Kind) MessageValue {
        const len = std.mem.len(@as([*:0]const u8, @ptrCast(value)));
        assert(len > 0 and len <= 63);

        return switch (t) {
            .B => .{ .B = std.mem.eql(u8, "on", value[0..2]) or
                std.mem.eql(u8, "true", value[0..4]) or
                value[0] == '1' },
            .I => .{ .I = std.fmt.parseInt(i32, value[0..len], 10) catch @panic("value not i32") },
            .U => .{ .U = std.fmt.parseInt(u32, value[0..len], 10) catch @panic("value not u32") },
            .F => .{ .F = std.fmt.parseFloat(f32, value[0..len]) catch @panic("value not f32") },
            else => .{ .Str = value },
        };
    }

    pub fn FromSetting(setting: *const SettingValue, t: Kind) MessageValue {
        return switch (t) {
            .B => .{ .B = setting.B },
            .I => .{ .I = setting.I },
            .U => .{ .U = setting.U },
            .F => .{ .F = setting.F },
            else => .{ .Str = &setting.Str },
        };
    }
};

const Setting = struct {
    Parent: ?ParentHandle = null,
    Name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    Value: SettingValue = .{ .Str = std.mem.zeroes([63:0]u8) },
    ValueDefault: SettingValue = .{ .Str = std.mem.zeroes([63:0]u8) },
    ValueSaved: SettingValue = .{ .Str = std.mem.zeroes([63:0]u8) },
    ValueKind: Kind = .None,
    pValueTarget: ?*anyopaque = null,
    Flags: EnumSet(SettingFlags) = EnumSet(SettingFlags).initEmpty(),
    fnOnChange: ?*const fn (value: MessageValue) callconv(.C) void = null,
};

const SettingValue = extern union {
    Str: [63:0]u8,
    F: f32,
    U: u32,
    I: i32,
    B: bool,

    fn FromMessage(self: *SettingValue, v: MessageValue, t: Kind) !void {
        switch (t) {
            .F => self.F = v.F,
            .U => self.U = v.U,
            .I => self.I = v.I,
            .B => self.B = v.B,
            else => _ = try bufPrintZ(&self.Str, "{s}", .{v.Str}),
        }
    }

    /// convert internal readable string to typed value
    fn ValueParse(self: *SettingValue, t: Kind) !void {
        const len = std.mem.len(@as([*:0]u8, @ptrCast(&self.Str)));
        switch (t) {
            .B => self.B = std.mem.eql(u8, "on", self.Str[0..2]) or
                std.mem.eql(u8, "true", self.Str[0..4]) or
                self.Str[0] == '1',
            .I => self.I = try std.fmt.parseInt(i32, self.Str[0..len], 10),
            .U => self.U = try std.fmt.parseInt(u32, self.Str[0..len], 10),
            .F => self.F = try std.fmt.parseFloat(f32, self.Str[0..len]),
            .Str => {},
            else => @panic("setting output value type must not be None"),
        }
    }

    /// convert internal typed value to readable string
    fn ValuePrint(self: *SettingValue, t: Kind) !void {
        switch (t) {
            .B => _ = try bufPrintZ(&self.Str, "{s}", .{if (self.B) "on" else "off"}),
            .I => _ = try bufPrintZ(&self.Str, "{d}", .{self.I}),
            .U => _ = try bufPrintZ(&self.Str, "{d}", .{self.U}),
            .F => _ = try bufPrintZ(&self.Str, "{d:4.2}", .{self.F}),
            .Str => {},
            else => @panic("setting input value type must not be None"),
        }
    }

    fn Eql(self: *const SettingValue, other: *const SettingValue, t: Kind) bool {
        return switch (t) {
            .B => self.B == other.B,
            .I => self.I == other.I,
            .U => self.U == other.U,
            .F => self.F == other.F,
            else => return std.mem.orderZ(u8, &self.Str, &other.Str) == .eq,
        };
    }

    fn EqlMessage(self: *const SettingValue, other: MessageValue, t: Kind) bool {
        return switch (t) {
            .B => self.B == other.B,
            .I => self.I == other.I,
            .U => self.U == other.U,
            .F => self.F == other.F,
            else => return std.mem.orderZ(u8, &self.Str, other.Str) == .eq,
        };
    }

    fn Write(self: *const SettingValue, writer: anytype, t: Kind) !void {
        switch (t) {
            .B => try std.fmt.format(writer, "{s}", .{if (self.B) "on" else "off"}),
            .I => try std.fmt.format(writer, "{d}", .{self.I}),
            .U => try std.fmt.format(writer, "{d}", .{self.U}),
            .F => try std.fmt.format(writer, "{d:4.2}", .{self.F}),
            else => try std.fmt.format(writer, "{s}", .{@as([*:0]const u8, @ptrCast(&self.Str))}),
        }
    }

    fn WriteToPtr(self: *SettingValue, p: *anyopaque, t: Kind) void {
        return switch (t) {
            .Str => @as(*[63:0]u8, @alignCast(@ptrCast(p))).* = @as(*[63:0]u8, @ptrCast(&self.Str)).*,
            .F => @as(*f32, @alignCast(@ptrCast(p))).* = @as(*f32, @ptrCast(&self.F)).*,
            .U => @as(*u32, @alignCast(@ptrCast(p))).* = @as(*u32, @ptrCast(&self.U)).*,
            .I => @as(*i32, @alignCast(@ptrCast(p))).* = @as(*i32, @ptrCast(&self.I)).*,
            .B => @as(*bool, @alignCast(@ptrCast(p))).* = @as(*bool, @ptrCast(&self.B)).*,
            else => @panic("setting value type must not be None"),
        };
    }
};

const SettingFlags = enum(u32) {
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

// reserved settings: AutoSave, UseGlobalAutoSave
const Section = struct {
    Parent: ?ParentHandle = null,
    Name: [63:0]u8 = std.mem.zeroes([63:0]u8),
    Flags: EnumSet(SectionFlags) = EnumSet(SectionFlags).initEmpty(),
    fnOnChange: ?*const fn (changed: [*]Message, len: usize) callconv(.C) void = null,
};

const SectionFlags = enum(u32) {
    HasOwner,
    AutoSave,
    UpdateQueued,
};

// reserved global settings: AutoSave
pub const SettingManager = struct {
    DataSections: HandleMap(Section, u16) = undefined,
    DataSettings: HandleMap(Setting, u16) = undefined,
    Flags: EnumSet(SettingManagerFlags) = EnumSet(SettingManagerFlags).initEmpty(),
    HotReload: HotReloader = undefined,
    bSkipNextLoad: bool = false,
    SectionUpdateQueue: ArrayList(Message) = undefined,
    FilePath: [:0]const u8 = &.{},
    bFileExists: bool = false,

    ScratchBuffer: FixedBufferAllocator = undefined,
    ScratchAlloc: Allocator = undefined,

    const SettingManagerFlags = enum(u32) {
        AutoSave,
    };

    pub fn Init(
        out: *SettingManager,
        buf: []u8,
        filename: [:0]const u8,
    ) !void {
        out.* = .{};

        out.FilePath = filename;

        out.ScratchBuffer = FixedBufferAllocator.init(buf);
        out.ScratchAlloc = out.ScratchBuffer.allocator();

        out.DataSections = HandleMap(Section, u16).init(out.ScratchAlloc);
        out.DataSettings = HandleMap(Setting, u16).init(out.ScratchAlloc);
        out.SectionUpdateQueue = ArrayList(Message).init(out.ScratchAlloc);

        HotReloader.Init(&out.HotReload, IniLoad, IniUnload);
        out.HotReload.CheckDelay = 250;
        out.HotReload.TrackFileAlways(out.FilePath, out);
    }

    pub fn Deinit(self: *SettingManager) void {
        self.DataSections.deinit();
        self.DataSettings.deinit();
        self.SectionUpdateQueue.deinit();
    }

    /// gets index of data matching name and parenting pattern
    /// index will be valid for map's data and handle arrays, use handle.index
    /// for sparse_indices array index
    fn NodeFind(
        self: *SettingManager,
        map: anytype, // handle_map_*
        parent: ?Handle,
        name: [*:0]const u8,
    ) ?u16 {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        if (parent != null and (parent.?.isNull() or !self.DataSections.hasHandle(parent.?))) return null;

        const name_len = std.mem.len(name) + 1; // include sentinel

        for (map.values.items, 0..) |*v, i| {
            if (!ParentHandle.Eql(v.Parent, parent)) continue;
            if (!std.mem.eql(u8, v.Name[0..name_len], name[0..name_len])) continue;
            return @intCast(i);
        }

        return null;
    }

    /// create a new raw section in the data set using a minimal definition. prefer
    /// SectionOccupy for regular api-facing use.
    fn SectionNew(
        self: *SettingManager,
        section: ?Handle,
        name: [*:0]const u8,
    ) !Handle {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        if (section != null and
            (section.?.isNull() or
            !self.DataSections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (self.NodeFind(self.DataSections, section, name) != null) return error.NameTaken;

        var section_new = Section{};
        if (section) |s| section_new.Parent = .{ .Generation = s.generation, .Index = s.index };
        _ = try bufPrintZ(&section_new.Name, "{s}", .{name});

        return try self.DataSections.insert(DEFAULT_ID, section_new);
    }

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for SettingOccupy)
    /// assign owner to a section.
    /// will prevent all other owners from creating children to the section.
    pub fn SectionOccupy(
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
            if (s.owner != owner) panic("owner mismatch:  owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!self.DataSections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = self.NodeFind(self.DataSections, section, name);

        var data: *Section = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (self.DataSections.handles.items[i].owner != DEFAULT_ID) return error.SectionAlreadyOwned;
            self.DataSections.handles.items[i].owner = owner;
            self.DataSections.sparse_indices.items[self.DataSections.handles.items[i].index].owner = owner;
            handle_new = self.DataSections.handles.items[i];
            data = &self.DataSections.values.items[i];
        } else {
            handle_new = try self.DataSections.insert(owner, .{});
            data = self.DataSections.get(handle_new).?;
            data.Parent = if (section) |s| .{ .Generation = s.generation, .Index = s.index } else null;
            _ = try bufPrintZ(&data.Name, "{s}", .{name});
        }

        data.fnOnChange = fnOnChange;

        return handle_new;
    }

    /// release ownership of a section node, and all of the children in the settings
    /// tree below it. calls SettingVacate on applicable settings.
    pub fn SectionVacate(
        self: *SettingManager,
        handle: Handle,
    ) void {
        var data: *Section = self.DataSections.get(handle) orelse return;

        for (self.DataSections.values.items, 0..) |*s, i| {
            if (s.Parent != null and ParentHandle.Eql(s.Parent, handle)) {
                const h: Handle = self.DataSections.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) self.SectionVacate(h);
            }
        }

        for (self.DataSettings.values.items, 0..) |*s, i| {
            if (s.Parent != null and ParentHandle.Eql(s.Parent, handle)) {
                const h: Handle = self.DataSettings.handles.items[i];
                if (h.owner != DEFAULT_ID and h.owner == handle.owner) self.SettingVacate(h);
            }
        }

        data.fnOnChange = null;

        var s_index: *SparseIndex = &self.DataSections.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        self.DataSections.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// run section update callback on the recently updated settings of that group.
    pub fn SectionRunUpdate(self: *SettingManager, handle: Handle) void {
        const sec: *Section = self.DataSections.get(handle) orelse return;
        const sec_fn = sec.fnOnChange orelse return;

        self.SectionUpdateQueue.clearRetainingCapacity();

        for (self.DataSettings.values.items) |*s| {
            if (s.Parent == null or !ParentHandle.Eql(s.Parent, handle)) continue;
            if (!s.Flags.contains(.InSectionUpdateQueue)) continue;
            if (s.ValueKind == .None) continue;

            s.Flags.remove(.InSectionUpdateQueue);
            const send_data = Message{
                .Name = &s.Name,
                .Value = MessageValue.FromSetting(&s.Value, s.ValueKind),
            };
            self.SectionUpdateQueue.append(send_data) catch continue;
        }

        sec_fn(self.SectionUpdateQueue.items.ptr, self.SectionUpdateQueue.items.len);
    }

    /// run sectionRunUpdate on all sections that are occupied by the given owner.
    pub fn SectionRunUpdateOwner(self: *SettingManager, owner: u16) void {
        for (self.DataSections.handles.items) |handle|
            if (handle.owner == owner) self.SectionRunUpdate(handle);
    }

    /// run sectionRunUpdate on all sections.
    fn SectionRunUpdateAll(
        self: *SettingManager,
    ) void {
        for (self.DataSections.handles.items) |handle|
            self.SectionRunUpdate(handle);
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the value loaded frome file.
    /// settings that are not on file are not affected.
    pub fn SectionResetToSaved(self: *SettingManager, handle: ?Handle) void {
        for (self.DataSettings.values.items) |*s| {
            if (!ParentHandle.Eql(s.Parent, handle)) continue;
            if (!s.Flags.contains(.SavedValueIsSet)) continue;

            s.Value = s.ValueSaved;
            s.Flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings that are direct children of the section associated
    /// with the give handle to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn SectionResetToDefaults(self: *SettingManager, handle: ?Handle) void {
        for (self.DataSettings.values.items) |*s| {
            if (!ParentHandle.Eql(s.Parent, handle)) continue;
            if (!s.Flags.contains(.DefaultValueIsSet)) continue;

            s.Value = s.ValueDefault;
            s.Flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings that are direct children of the section associated
    /// with the given handle, removing their data entirely
    fn SectionRemoveVacant(self: *SettingManager, handle: ?Handle) void {
        const slices = self.DataSettings.values.slice();
        const sl_sec = slices.items(.section);
        const sl_fl: []EnumSet(Setting.Flags) = slices.items(.Flags);

        const len = self.DataSettings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (!ParentHandle.Eql(sl_sec[i], handle)) continue;
            if (sl_fl[i].contains(.DefaultValueIsSet)) continue;
            _ = self.DataSettings.remove(self.DataSettings.handles.items[i]);
        }
    }

    /// create a new raw setting in the data set using a minimal definition. prefer
    /// SettingOccupy for regular api-facing use.
    fn SettingNew(
        self: *SettingManager,
        section: ?Handle,
        name: [*:0]const u8,
        value: [*:0]const u8, // -> ValueSaved
        from_file: bool,
    ) !Handle {
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);
        assert(std.mem.len(value) > 0 and std.mem.len(value) <= 63);

        if (section != null and
            (section.?.isNull() or
            !self.DataSections.hasHandle(section.?))) return error.ParentSectionDoesNotExist;

        const name_len = std.mem.len(name);
        if (name_len == 0 or name_len > 63) return error.NameLengthInvalid;
        if (self.NodeFind(self.DataSettings, section, name) != null) return error.NameTaken;

        const value_len = std.mem.len(value);
        if (value_len == 0 or value_len > 63) return error.ValueLengthInvalid;

        var setting = Setting{};
        if (section) |s| setting.Parent = .{ .Generation = s.generation, .Index = s.index };
        _ = try bufPrintZ(&setting.Name, "{s}", .{name});
        _ = try bufPrintZ(&setting.Value.Str, "{s}", .{value});
        setting.Flags.insert(.ValueIsSet);
        if (from_file) {
            _ = try bufPrintZ(&setting.ValueSaved.Str, "{s}", .{value});
            setting.Flags.insert(.SavedValueIsSet);
        }

        return try self.DataSettings.insert(DEFAULT_ID, setting);
    }

    // TODO: allow DEFAULT_ID owner even when section is occupied? (and same for SectionOccupy)
    // FIXME: test - output handle contains input owner (same for SectionOccupy)
    /// assign an owner to a setting and apply a definition, creating the setting
    /// data if needed. will update value in external pointer callback to run update
    /// callback using the initial value (the existing value if available, or the default)
    pub fn SettingOccupy(
        self: *SettingManager,
        owner: u16,
        section: ?Handle,
        name: [*:0]const u8,
        value_kind: Kind,
        value_default: MessageValue,
        p_value_target: ?*anyopaque,
        fnOnChange: ?*const fn (MessageValue) callconv(.C) void,
    ) !Handle {
        assert(value_kind != .None);
        assert(std.mem.len(name) > 0 and std.mem.len(name) <= 63);

        // TODO: return error instead of panic? and move panic to global function?
        if (section) |s| blk: {
            if (s.owner == DEFAULT_ID) break :blk; // allow parenting to vacant sections
            if (s.owner != owner) panic("owner mismatch:  owner:{d}  s.owner:{d}", .{ owner, s.owner });
            if (!self.DataSections.hasHandle(s)) return error.SectionDoesNotExist;
        }

        const existing_i = self.NodeFind(self.DataSettings, section, name);

        var data: *Setting = undefined;
        var handle_new: Handle = undefined;
        if (existing_i) |i| {
            if (self.DataSettings.handles.items[i].owner != DEFAULT_ID) return error.SettingAlreadyOwned;
            self.DataSettings.handles.items[i].owner = owner;
            self.DataSettings.sparse_indices.items[self.DataSettings.handles.items[i].index].owner = owner;
            handle_new = self.DataSettings.handles.items[i];
            data = &self.DataSettings.values.items[i];
        } else {
            handle_new = try self.DataSettings.insert(owner, .{});
            data = self.DataSettings.get(handle_new).?;
            data.Parent = if (section) |s| ParentHandle.FromHandle(s) else null;
            _ = try bufPrintZ(&data.Name, "{s}", .{name});
        }

        // NOTE: existing data assumed to be raw (new, unprocessed or released)
        if (data.Flags.contains(.ValueIsSet)) {
            data.Value.ValueParse(value_kind) catch {
                // invalid data = use default, will be cleaned next file write
                data.Value.FromMessage(value_default, value_kind) catch unreachable; // value_kind assertion = OK
            };
            if (!data.Value.EqlMessage(value_default, value_kind))
                data.Flags.insert(.InSectionUpdateQueue);
            if (data.Flags.contains(.SavedValueIsSet))
                data.ValueSaved.ValueParse(value_kind) catch data.Flags.insert(.SavedValueNotConverted);
        } else {
            data.Value.FromMessage(value_default, value_kind) catch unreachable; // value_kind assertion = OK
            data.Flags.insert(.ValueIsSet);
        }
        data.ValueKind = value_kind;
        data.ValueDefault.FromMessage(value_default, value_kind) catch unreachable; // value_kind assertion = OK
        data.Flags.insert(.DefaultValueIsSet);

        data.pValueTarget = p_value_target;
        if (p_value_target) |p| data.Value.WriteToPtr(p, data.ValueKind);

        data.fnOnChange = fnOnChange;
        if (fnOnChange) |f| f(MessageValue.FromSetting(&data.Value, data.ValueKind));

        return handle_new;
    }

    /// remove owner from a setting and clear its definition.
    pub fn SettingVacate(
        self: *SettingManager,
        handle: Handle,
    ) void {
        var data: *Setting = self.DataSettings.get(handle) orelse return;
        assert(data.Flags.contains(.ValueIsSet));

        data.fnOnChange = null;

        data.ValueDefault = .{ .Str = std.mem.zeroes([63:0]u8) };
        data.Flags.remove(.DefaultValueIsSet);

        data.Value.ValuePrint(data.ValueKind) catch @panic("SettingVacate: 'value' invalid");
        if (!data.Flags.contains(.SavedValueNotConverted))
            data.ValueSaved.ValuePrint(data.ValueKind) catch @panic("SettingVacate: 'ValueSaved' invalid");
        data.Flags.remove(.SavedValueNotConverted);

        data.ValueKind = .None;

        var s_index: *SparseIndex = &self.DataSettings.sparse_indices.items[handle.index];
        s_index.owner = DEFAULT_ID;
        self.DataSettings.handles.items[s_index.index_or_next].owner = DEFAULT_ID;
    }

    /// trigger setting update with new value.
    /// will update value in external pointer callback to run update callback.
    pub fn SettingUpdate(
        self: *SettingManager,
        handle: Handle,
        value: MessageValue,
    ) void {
        var s: *Setting = self.DataSettings.get(handle) orelse return;

        if (s.Value.EqlMessage(value, s.ValueKind)) return;

        s.Value.FromMessage(value, s.ValueKind) catch return;

        s.Flags.insert(.InSectionUpdateQueue);
        if (s.pValueTarget) |p| s.Value.WriteToPtr(p, s.ValueKind);
        if (s.fnOnChange) |f| f(value);
    }

    /// restore all settings to the value loaded from file.
    /// settings that are not on file are not affected.
    pub fn SettingResetAllToSaved(
        self: *SettingManager,
    ) void {
        for (self.DataSettings.values.items) |*s| {
            if (!s.Flags.contains(.SavedValueIsSet)) continue;
            s.Value = s.ValueSaved;
            s.Flags.insert(.ValueIsSet);
        }
    }

    /// restore all settings to the default value defined by their owner.
    /// settings that do not have an owner are not affected.
    pub fn SettingResetAllToDefaults(
        self: *SettingManager,
    ) void {
        for (self.DataSettings.values.items) |*s| {
            if (!s.Flags.contains(.DefaultValueIsSet)) continue;
            s.Value = s.ValueDefault;
            s.Flags.insert(.ValueIsSet);
        }
    }

    /// scrub all unoccupied settings, removing their data entirely
    pub fn SettingRemoveAllVacant(
        self: *SettingManager,
    ) void {
        const len = self.DataSettings.handles.items.len;
        for (0..len) |j| {
            const i = len - j - 1;
            if (self.DataSettings.values.items[i].Flags.contains(.DefaultValueIsSet)) continue;
            _ = self.DataSettings.remove(self.DataSettings.handles.items[i]);
        }
    }

    /// free all sections and settings of the given owner, allowing them to be
    /// assigned a new owner
    pub fn VacateOwner(self: *SettingManager, owner: u16) void {
        // settings first for better cache use of DataSettings processes
        for (self.DataSettings.handles.items) |h|
            if (h.owner == owner) self.SettingVacate(h);

        for (self.DataSections.handles.items) |h|
            if (h.owner == owner) self.SectionVacate(h);
    }

    // TODO: convert to reader to match iniWrite?
    /// read ini-formatted settings from file
    fn IniRead(self: *SettingManager, gpa: Allocator, filename: []const u8) !void {
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
                    const section_i = self.NodeFind(self.DataSections, null, name);
                    sec_handle = if (section_i) |i|
                        self.DataSections.handles.items[i]
                    else
                        self.SectionNew(null, name) catch null;
                },
                .property => |kv| {
                    const setting_i = self.NodeFind(self.DataSettings, sec_handle, kv.key);
                    if (setting_i) |i| {
                        const s = &self.DataSettings.values.items[i];
                        const h = self.DataSettings.handles.items[i];

                        // don't override value that has already been changed by something else
                        if (s.Flags.contains(.SavedValueIsSet) and
                            !s.Value.Eql(&s.ValueSaved, s.ValueKind)) continue;

                        const send_val = MessageValue.FromRaw(kv.value, s.ValueKind);

                        if (!s.ValueSaved.EqlMessage(send_val, s.ValueKind))
                            try s.ValueSaved.FromMessage(send_val, s.ValueKind);

                        if (!s.Value.EqlMessage(send_val, s.ValueKind))
                            self.SettingUpdate(h, send_val);
                    } else {
                        _ = try self.SettingNew(sec_handle, kv.key, kv.value, true);
                    }
                },
                .enumeration => |value| { // FIXME: impl
                    _ = value;
                },
            }
        }

        self.SectionRunUpdateAll();
    }

    // callback for HotReload(HotReloadHandle)
    // stub because the settings live throughout the whole program lifetime and
    // will only be updated if a reload occurs
    fn IniUnload(_: ?*SettingManager, _: [:0]const u8, _: [:0]const u8) void {}

    // callback for HotReload(HotReloadHandle)
    /// read settings from file
    fn IniLoad(self: ?*SettingManager, filepath: [:0]const u8, _: [:0]const u8) bool {
        assert(self != null);
        assert(std.mem.eql(u8, self.?.FilePath, filepath));

        if (self.?.bSkipNextLoad) {
            self.?.bSkipNextLoad = false;
            return false; // TODO: should be true or false? no effect in current logic tho
        }

        self.?.IniRead(self.?.ScratchAlloc, self.?.FilePath) catch return false;

        self.?.bFileExists = true;
        return true;
    }

    /// write all settings to buffer in ini format
    fn IniWrite(self: *SettingManager, writer: anytype) !void {
        try self.IniWriteSection(writer, null);
        for (self.DataSections.handles.items) |h|
            try self.IniWriteSection(writer, h);
    }

    // TODO: sorting both settings and sections?
    /// write settings section to buffer in ini format
    fn IniWriteSection(self: *SettingManager, writer: anytype, handle: ?Handle) !void {
        if (handle) |h| blk: {
            const section: *Section = self.DataSections.get(h) orelse break :blk;
            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&section.Name)));
            _ = try writer.write("[");
            _ = try writer.write(section.Name[0..nlen]);
            _ = try writer.write("]\n");
        }

        for (self.DataSettings.values.items) |*s| {
            if (!s.Flags.contains(.InFileWriteQueue) or !ParentHandle.Eql(s.Parent, handle)) continue;

            const nlen = std.mem.len(@as([*:0]const u8, @ptrCast(&s.Name)));
            _ = try writer.write(s.Name[0..nlen]);
            _ = try writer.write(" = ");
            try s.Value.Write(writer, s.ValueKind);
            _ = try writer.write("\n");

            s.Flags.remove(.InFileWriteQueue);
        }

        _ = writer.write("\n") catch {};
    }

    /// write settings to file
    pub fn Save(
        self: *SettingManager,
        b_save_defaults: bool,
    ) !void {
        const changed_settings: u32 = self.SavePrepare(b_save_defaults);
        if (changed_settings == 0 and (b_save_defaults and self.bFileExists)) return;

        const file = try std.fs.cwd().createFile(self.FilePath, .{}); // .exclusive=true for no file rewrite
        defer file.close();
        var file_bw = std.io.bufferedWriter(file.writer());
        defer _ = file_bw.flush() catch |e|
            panic("ASettings(Save): write buffer flush: {s}", .{@errorName(e)});
        const file_w = file_bw.writer();

        try self.IniWrite(file_w);
        self.bSkipNextLoad = true;
        self.bFileExists = true;

        self.SaveCleanup();
    }

    /// post-processing of sections and settings, to make settings ready for next write
    fn SaveCleanup(self: *SettingManager) void {
        for (self.DataSettings.values.items) |*s| {
            // make sure system knows which settings are no longer on file
            if (!s.Flags.contains(.FileUpdatedLastWrite))
                s.Flags.remove(.SavedValueIsSet);

            s.Flags.remove(.FileUpdatedLastWrite);
        }
    }

    // TODO: convert to flattened version of savePrepareSection logic? OR only call prep
    // on sections marked for saving? i.e. need to handle 'save only one section' case
    /// pre-pass on settings to determine which settings need to be written and how
    /// write functions assume settings are tagged correctly as a result of running this step
    /// @return     number of settings that would actually change in the file as a result of writing
    fn SavePrepare(self: *SettingManager, b_save_defaults: bool) u32 {
        var changed: u32 = 0;

        changed += self.SavePrepareSection(null, b_save_defaults);
        for (self.DataSections.handles.items) |h|
            changed += self.SavePrepareSection(h, b_save_defaults);

        return changed;
    }

    /// see savePrepare for explanation
    /// @return     number of settings that would actually change in the file as a result of writing
    fn SavePrepareSection(self: *SettingManager, handle: ?Handle, b_save_defaults: bool) u32 {
        var changed: u32 = 0;
        for (self.DataSettings.values.items) |*s| {
            if (!ParentHandle.Eql(s.Parent, handle)) continue;

            // only keep uninitialized settings if they were already on file
            if (!s.Flags.contains(.DefaultValueIsSet) and
                !s.Flags.contains(.SavedValueIsSet)) continue;

            // only store initialized settings if they are not default
            if (!b_save_defaults and s.Flags.contains(.DefaultValueIsSet) and
                s.ValueDefault.Eql(&s.Value, s.ValueKind)) continue;

            if ((s.Flags.contains(.SavedValueIsSet) and !s.ValueSaved.Eql(&s.Value, s.ValueKind)) or
                (!s.Flags.contains(.SavedValueIsSet) and b_save_defaults))
                changed += 1;

            s.ValueSaved = s.Value;
            s.Flags.insert(.SavedValueIsSet);
            s.Flags.insert(.FileUpdatedLastWrite);

            s.Flags.insert(.InFileWriteQueue);
        }
        return changed;
    }
};

// -----------------------------------------------------------------------------
// DEBUGGING & TESTING

// NOTE: use in testing
fn testUpdateSet1(_: MessageValue) callconv(.C) void {
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

    //const sec_base = ASettings.SectionNew(null, "TestBaseSection") catch NullHandle;
    //_ = ASettings.SectionNew(sec_base, "Sec1") catch {};
    //_ = ASettings.SectionNew(sec_base, "Sec2") catch {};
    //_ = ASettings.SectionNew(sec_base, "Sec2") catch {}; // expect: NameTaken error -> skipped
    //const sec1 = ASettings.SectionOccupy(0xF000, sec_base, "Sec1", null) catch NullHandle;
    //const sec2 = ASettings.SectionOccupy(0xF001, sec_base, "Sec2", null) catch NullHandle;

    //_ = ASettings.SettingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.SettingNew(sec1, "Set1", "123.456", false) catch {};
    //_ = ASettings.SettingNew(null, "Set2", "Val2", false) catch {};
    //_ = ASettings.SettingNew(sec2, "Set3", "Val3", false) catch {};
    //_ = ASettings.SettingNew(null, "Set4", "Val4", false) catch {};
    //_ = ASettings.SettingNew(null, "Set4", "Val42", false) catch {}; // expect: NameTaken error -> skipped
    //_ = ASettings.SettingNew(null, "Set5", "Val5", false) catch {};

    //const occ1 = ASettings.SettingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, testUpdateSet1) catch NullHandle;
    //_ = ASettings.SettingOccupy(0xF000, sec1, "Set1", .F, .{ .f = 987.654 }, null, null) catch {}; // expect: ignored
    //const occ2 = ASettings.SettingOccupy(0xF000, null, "Set6", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //_ = ASettings.SettingOccupy(0xF000, null, "Set6", .F, .{ .f = 876.543 }, null, null) catch {}; // export: ignored

    //ASettings.SettingUpdate(occ1, .{ .f = 678.543 }); // expect: changed value
    //ASettings.SettingVacate(occ2); // expect: undefined default, etc.

    //const sec3 = ASettings.SectionOccupy(0xF001, sec2, "Sec3", null) catch NullHandle;
    //_ = ASettings.SettingNew(sec3, "Set7", "Val7", false) catch {};
    //_ = ASettings.SettingOccupy(0xF001, sec3, "Set8", .F, .{ .f = 987.654 }, null, null) catch NullHandle;
    //ASettings.SectionVacate(sec3);

    //ASettings.VacateOwner(0xF000); // expect: everything undefined default, etc.
}
