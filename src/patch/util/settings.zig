const settings = @This();

const std = @import("std");
const ini = @import("../import/import.zig").ini;

pub const IniValue = union(enum) {
    b: bool,
    i: i32,
    u: u32,
    f: f32,
};

pub const IniValueError = error{
    KeyNotFound,
    NotParseable,
    NotValid,
};

pub const SettingsError = error{
    ManagerNotInitialized,
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
            bool => self.values.put(key, .{ .b = value }) catch unreachable,
            i32 => self.values.put(key, .{ .i = value }) catch unreachable,
            u32 => self.values.put(key, .{ .u = value }) catch unreachable,
            f32 => self.values.put(key, .{ .f = value }) catch unreachable,
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
                    if (std.mem.eql(u8, "true", value) or value[0] == '1') {
                        item.value_ptr.*.b = true;
                        return;
                    }
                    if (std.mem.eql(u8, "false", value) or value[0] == '0') {
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
        self.groups.put(group.name, group) catch unreachable;
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
};
