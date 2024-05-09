const settings = @This();

const std = @import("std");
const ini = @import("zigini");

// TODO: convert hashmaps to ArrayList, so that settings in default file retains
// order as defined in patch/core/Settings.zig

pub const IniValue = union(enum) {
    b: bool,
    i: i32,
    u: u32,
    f: f32,

    pub fn allocFmt(self: *IniValue, alloc: std.mem.Allocator) ![]u8 {
        return switch (self.*) {
            .b => |val| std.fmt.allocPrint(alloc, "{s}", .{if (val) "on" else "off"}),
            .i => |val| std.fmt.allocPrint(alloc, "{d}", .{val}),
            .u => |val| std.fmt.allocPrint(alloc, "{d}", .{val}),
            .f => |val| std.fmt.allocPrint(alloc, "{d:4.2}", .{val}),
        };
    }
};

pub const IniValueError = error{
    KeyNotFound,
    NotParseable,
    NotValid,
};

pub const SettingsError = error{
    ManagerNotInitialized,
};

// FIXME: basically just StringHashMap->Entry, how to get that type?
const SettingsGroupItem = extern struct {
    key: *[]const u8,
    value: *IniValue,
};

pub const SettingsGroup = struct {
    name: []const u8,
    values: std.StringHashMap(IniValue),

    pub fn init(alloc: std.mem.Allocator, name: []const u8) SettingsGroup {
        return .{
            .values = std.StringHashMap(IniValue).init(alloc),
            .name = name,
        };
    }

    pub fn deinit(self: *SettingsGroup) void {
        self.values.deinit();
    }

    pub fn add(self: *SettingsGroup, key: []const u8, comptime T: type, value: T) void {
        switch (T) {
            bool => self.values.put(key, .{ .b = value }) catch
                @panic("failed to add bool setting to settings group"),
            i32 => self.values.put(key, .{ .i = value }) catch
                @panic("failed to add i32 setting to settings group"),
            u32 => self.values.put(key, .{ .u = value }) catch
                @panic("failed to add u32 setting to settings group"),
            f32 => self.values.put(key, .{ .f = value }) catch
                @panic("failed to add f32 setting to settings group"),
            else => return,
        }
    }

    pub fn get(self: *SettingsGroup, key: []const u8, comptime T: type) T {
        var value = self.values.get(key);
        return switch (T) {
            bool => if (value) |v| v.b else false,
            i32 => if (value) |v| v.i else 0,
            u32 => if (value) |v| v.u else 0,
            f32 => if (value) |v| v.f else 0,
            else => undefined,
        };
    }

    pub fn update(self: *SettingsGroup, key: []const u8, value: []const u8) !void {
        var kv = self.values.getEntry(key);
        if (kv) |item| {
            return switch (item.value_ptr.*) {
                .b => {
                    if (std.mem.eql(u8, "on", value) or std.mem.eql(u8, "true", value) or value[0] == '1') {
                        item.value_ptr.*.b = true;
                        return;
                    }
                    if (std.mem.eql(u8, "off", value) or std.mem.eql(u8, "false", value) or value[0] == '0') {
                        item.value_ptr.*.b = false;
                        return;
                    }
                    return IniValueError.NotValid;
                },
                .i => {
                    item.value_ptr.*.i = try std.fmt.parseInt(i32, value, 10);
                },
                .u => {
                    item.value_ptr.*.u = try std.fmt.parseInt(u32, value, 10);
                },
                .f => {
                    item.value_ptr.*.f = try std.fmt.parseFloat(f32, value);
                },
            };
        }
    }

    fn lessThanFnItem(_: void, a: SettingsGroupItem, b: SettingsGroupItem) bool {
        const a_k = a.key.*;
        const b_k = b.key.*;
        var i: u32 = 0;
        while (i < a_k.len and i < b_k.len) : (i += 1) {
            if (a_k[i] == b_k[i]) continue;
            return a_k[i] < b_k[i];
        }
        return a_k.len < b_k.len;
    }

    pub fn sorted(self: *SettingsGroup) !std.ArrayList(SettingsGroupItem) {
        var list = std.ArrayList(SettingsGroupItem).init(self.values.allocator);

        var it = self.values.iterator();
        while (it.next()) |kv|
            try list.append(.{ .key = kv.key_ptr, .value = kv.value_ptr });

        std.mem.sort(SettingsGroupItem, list.items, {}, lessThanFnItem);

        return list;
    }
};

// FIXME: basically just StringHashMap->Entry, how to get that type?
const SettingsManagerItem = struct {
    key: *[]const u8,
    value: *SettingsGroup,
};

pub const SettingsManager = struct {
    global: SettingsGroup,
    groups: std.StringHashMap(*SettingsGroup),

    pub fn init(alloc: std.mem.Allocator) SettingsManager {
        return .{
            .global = SettingsGroup.init(alloc, "__SettingsManager_global__"),
            .groups = std.StringHashMap(*SettingsGroup).init(alloc),
        };
    }

    pub fn deinit(self: *SettingsManager) void {
        self.groups.deinit();
        self.global.deinit();
    }

    pub fn add(self: *SettingsManager, group: *SettingsGroup) void {
        self.groups.put(group.name, group) catch @panic("failed to add settings group to manager");
    }

    pub fn read_ini(self: *SettingsManager, alloc: std.mem.Allocator, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var parser = ini.parse(alloc, file.reader());
        defer parser.deinit();

        var group: *SettingsGroup = &self.global;
        while (try parser.next()) |record| {
            switch (record) {
                .section => |heading| {
                    group = if (self.groups.getEntry(heading)) |g| g.value_ptr.* else &self.global;
                },
                .property => |kv| {
                    try group.update(kv.key, kv.value);
                },
                .enumeration => |value| { // FIXME: implement
                    _ = value;
                },
            }
        }
    }

    fn lessThanFnItem(_: void, a: SettingsManagerItem, b: SettingsManagerItem) bool {
        const a_k = a.key.*;
        const b_k = b.key.*;
        var i: u32 = 0;
        while (i < a_k.len and i < b_k.len) : (i += 1) {
            if (a_k[i] == b_k[i]) continue;
            return a_k[i] < b_k[i];
        }
        return a_k.len < b_k.len;
    }

    pub fn sorted(self: *SettingsManager) !std.ArrayList(SettingsManagerItem) {
        var list = std.ArrayList(SettingsManagerItem).init(self.groups.allocator);

        var it = self.groups.iterator();
        while (it.next()) |kv|
            try list.append(.{ .key = kv.key_ptr, .value = kv.value_ptr.* });

        std.mem.sort(SettingsManagerItem, list.items, {}, lessThanFnItem);

        return list;
    }
};
