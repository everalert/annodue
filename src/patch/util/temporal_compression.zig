const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const rg = @import("racer").Global;
const ri = @import("racer").Input;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const msg = @import("message.zig");
const mem = @import("memory.zig");

pub const TemporalCompressor = struct {
    const Self = @This();
    initialized: bool = false,
    frame: usize = 0,
    frame_total: usize = 0,
    last_framecount: u32 = 0,

    const off_input: usize = 0;
    const off_race: usize = ri.COMBINED_SIZE;
    const off_test: usize = off_race + rrd.SIZE;
    const off_hang: usize = off_test + re.Test.SIZE;
    const off_cman: usize = off_hang + re.Hang.SIZE;
    const off_END: usize = off_cman + re.cMan.SIZE;

    pub const frames: usize = 60 * 60 * 8; // 8min @ 60fps
    //const frame_size: usize = off_cman + rc.cMan.SIZE;
    const header_size: usize = std.math.divCeil(usize, off_END, 4 * 8) catch unreachable; // comptime
    const header_type: type = std.packed_int_array.PackedIntArray(u1, header_bits);
    const header_bits: usize = off_END / 4;
    const offsets_off: usize = 0;
    const offsets_size: usize = frames * 4;
    const headers_off: usize = offsets_off + offsets_size;
    const headers_size: usize = header_size * frames;
    const stage_off: usize = headers_off + headers_size;
    const data_off: usize = stage_off + off_END * 2;

    // FIXME: remove gpa/alloc, do some kind of core integration instead
    var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;
    var alloc: ?std.mem.Allocator = null;
    const memory_size: usize = 1024 * 1024 * 64; // 64MB
    var memory: []u8 = undefined;
    var memory_addr: usize = undefined;
    var memory_end_addr: usize = undefined;
    var raw_offsets: [*]u8 = undefined;
    var raw_headers: [*]u8 = undefined;
    var raw_stage: [*]u8 = undefined;
    var offsets: *[frames]usize = undefined;
    var headers: *[frames]header_type = undefined;
    var stage: *[2][off_END / 4]u32 = undefined;
    var data: [*]u8 = undefined;

    const layer_size: isize = 4;
    const layer_depth: isize = 4;
    var layer_widths: [layer_depth]usize = widths: {
        var widths: [layer_depth]usize = undefined;
        for (1..layer_depth + 1) |f| {
            widths[layer_depth - f] = std.math.pow(usize, layer_size, f);
        }
        break :widths widths;
    };
    var layer_indexes: [layer_depth + 1]usize = undefined;
    var layer_index_count: usize = undefined;

    pub fn init(self: *Self) void {
        std.debug.assert(!self.initialized);
        defer self.initialized = true;

        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        alloc = gpa.?.allocator();
        memory = alloc.?.alloc(u8, memory_size) catch @panic("failed to allocate memory for savestate/rewind");
        @memset(memory[0..memory_size], 0x00);

        memory_addr = @intFromPtr(memory.ptr);
        memory_end_addr = @intFromPtr(memory.ptr) + memory_size;
        raw_offsets = memory.ptr + offsets_off;
        raw_headers = memory.ptr + headers_off;
        raw_stage = memory.ptr + stage_off;
        data = memory.ptr + data_off;
        offsets = @as(@TypeOf(offsets), @ptrFromInt(memory_addr + offsets_off));
        headers = @as(@TypeOf(headers), @ptrFromInt(memory_addr + headers_off));
        stage = @as(@TypeOf(stage), @ptrFromInt(memory_addr + stage_off));
    }

    pub fn deinit(self: *Self) void {
        std.debug.assert(self.initialized);
        defer self.initialized = false;

        if (alloc) |a| a.free(memory);
        if (gpa) |_| switch (gpa.?.deinit()) {
            .leak => @panic("leak detected when deinitializing savestate/rewind"),
            else => {},
        };

        self.reset();
    }

    pub fn reset(self: *Self) void {
        if (self.frame == 0) return;
        self.frame = 0;
        self.frame_total = 0;
    }

    // FIXME: better new-frame checking that doesn't only account for tabbing out
    // i.e. also when pausing, physics frozen with ingame feature, etc.
    pub fn saveable(self: *Self) bool {
        std.debug.assert(self.initialized);

        const space_ok: bool = memory_end_addr - @intFromPtr(data) - offsets[self.frame] >= off_END;
        const frames_ok: bool = self.frame < frames - 1;
        return space_ok and frames_ok;
    }

    pub fn get_depth(_: *Self, index: usize) usize {
        var depth: usize = layer_depth;
        var depth_test: usize = index;
        while (depth_test % layer_size == 0 and depth > 0) : (depth -= 1) {
            depth_test /= layer_size;
        }
        return depth;
    }

    pub fn set_layer_indexes(_: *Self, index: usize) void {
        layer_index_count = 0;
        var last_base: usize = 0;
        for (layer_widths) |w| {
            const remainder = index % w;
            const base = index - remainder;
            if (base > 0 and base != last_base) {
                last_base = base;
                layer_indexes[layer_index_count] = base;
                layer_index_count += 1;
            }
            if (remainder < layer_size) {
                if (remainder == 0) break;
                layer_indexes[layer_index_count] = index;
                layer_index_count += 1;
                break;
            }
        }
    }

    pub fn uncompress_frame(self: *Self, index: usize, skip_last: bool) void {
        std.debug.assert(self.initialized);

        @memcpy(raw_stage[0..off_END], data[0..off_END]);

        self.set_layer_indexes(index);
        var indexes: usize = layer_index_count - @intFromBool(skip_last);
        if (indexes == 0) return;

        for (layer_indexes[0..indexes]) |l| {
            const header = &headers[l];
            const frame_data = @as([*]usize, @ptrFromInt(@intFromPtr(data) + offsets[l]));
            var j: usize = 0;
            for (0..header_bits) |h| {
                if (header.get(h) == 1) {
                    stage[0][h] = frame_data[j];
                    j += 1;
                }
            }
        }
    }

    // FIXME: in future, probably can skip the first step each new frame, because
    // the most recent frame would already be in stage1 from last time
    pub fn save_compressed(self: *Self, gs: *GlobalSt) void {
        std.debug.assert(self.initialized);

        self.last_framecount = gs.framecount;

        var data_size: usize = 0;
        if (self.frame > 0) {
            self.uncompress_frame(self.frame, true);

            const s1_base = raw_stage + off_END;
            mem.read_bytes(ri.COMBINED_ADDR, s1_base + off_input, ri.COMBINED_SIZE);
            @memcpy(s1_base + off_race, rrd.PLAYER_SLICE.*);
            @memcpy(s1_base + off_test, re.Test.PLAYER_SLICE.*);
            @memcpy(s1_base + off_hang, re.Manager.entitySlice(.Hang, 0));
            @memcpy(s1_base + off_cman, re.Manager.entitySlice(.cMan, 0));

            var header = &headers[self.frame];
            header.setAll(0);
            var new_frame = @as([*]u32, @ptrFromInt(@intFromPtr(data) + offsets[self.frame]));
            var j: usize = 0;
            for (0..header_bits) |h| {
                if (stage[0][h] != stage[1][h]) {
                    header.set(h, 1);
                    new_frame[j] = stage[1][h];
                    data_size += 4;
                    j += 1;
                }
            }
        } else {
            data_size = off_END;
            mem.read_bytes(ri.COMBINED_ADDR, data + off_input, ri.COMBINED_SIZE);
            @memcpy(data + off_race, rrd.PLAYER_SLICE.*);
            @memcpy(data + off_test, re.Test.PLAYER_SLICE.*);
            @memcpy(data + off_hang, re.Manager.entitySlice(.Hang, 0));
            @memcpy(data + off_cman, re.Manager.entitySlice(.cMan, 0));
        }
        self.frame += 1;
        offsets[self.frame] = offsets[self.frame - 1] + data_size;
    }

    pub fn load_compressed(self: *Self, index: usize) void {
        std.debug.assert(self.initialized);

        self.uncompress_frame(index, false);
        _ = mem.write_bytes(ri.COMBINED_ADDR, &raw_stage[off_input], ri.COMBINED_SIZE);
        @memcpy(rrd.PLAYER_SLICE.*, raw_stage[off_race..off_test]); // WARN: maybe perm issues
        @memcpy(re.Test.PLAYER_SLICE.*, raw_stage[off_test..off_hang]); // WARN: maybe perm issues
        @memcpy(re.Manager.entitySlice(.Hang, 0).ptr, raw_stage[off_hang..off_cman]);
        @memcpy(re.Manager.entitySlice(.cMan, 0).ptr, raw_stage[off_cman..off_END]);
        self.frame = index + 1;
    }
};

// COMPRESSION-RELATED FUNCTIONS
// not really in use/needs work, basically just stuff for testing

// TODO: move to compression lib whenever that happens

// FIXME: assumes array of raw data; rework to adapt it to new compressed data
fn save_file() void {
    const file = std.fs.cwd().createFile("annodue/testdata.bin", .{}) catch |err| return msg.ErrMessage("create file", @errorName(err));
    defer file.close();

    const middle = TemporalCompressor.frame * TemporalCompressor.frame_size;
    const end = TemporalCompressor.frames * TemporalCompressor.frame_size;
    _ = file.write(TemporalCompressor.data[middle..end]) catch return;
    _ = file.write(TemporalCompressor.data[0..middle]) catch return;
}

// FIXME: dumped from patch.zig; need to rework into a generalized function
// TODO: cleanup unreachable after migrating to lib
fn check_compression_potential() void {
    const savestate_size: usize = 0x2428 / 4;
    const savestate_count: usize = 128;
    const savestate_head: usize = savestate_size / 8;
    const layer_size: usize = 4;
    const layer_depth: usize = 4;

    const testfile = std.fs.cwd().openFile("annodue/testdata.bin", .{}) catch unreachable;
    defer testfile.close();
    const reportfile = std.fs.cwd().createFile("annodue/testreport.txt", .{}) catch unreachable;
    defer reportfile.close();

    var data = std.mem.zeroes([layer_depth + 1][savestate_size]u32);
    var total_bytes: usize = 0;

    for (0..savestate_count - 1) |i| {
        var depth: usize = layer_depth;
        var depth_test: usize = i;
        while (depth_test % layer_size == 0 and depth > 0) {
            depth_test /= layer_size;
            depth -= 1;
        }

        _ = testfile.read(@as(*[savestate_size * 4]u8, @ptrCast(&data[depth]))) catch unreachable;
        if (depth < layer_depth) {
            for (depth + 1..layer_depth) |d| {
                data[d] = data[depth];
            }
        }

        const frame_bytes: usize = if (depth > 0) bytes: {
            var dif_count: usize = 0;
            for (data[depth], data[depth - 1]) |new, src| {
                if (new != src) dif_count += 1;
            }
            break :bytes dif_count * 4;
        } else savestate_size * 4;

        var buf: [17]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "Frame {d: >3}:\t{d: >4}\r\n", .{ i + 1, frame_bytes + savestate_head }) catch unreachable;
        _ = reportfile.write(&buf) catch unreachable;
        total_bytes += frame_bytes + savestate_head;
    }

    var buf: [26]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "Total: {d: >8}/{d: >8}\r\n", .{ total_bytes, savestate_size * savestate_count * 4 }) catch unreachable;
    _ = reportfile.write(&buf) catch unreachable;
}
