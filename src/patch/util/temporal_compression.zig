const std = @import("std");

const rg = @import("racer").Global;
const ri = @import("racer").Input;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const msg = @import("message.zig");
const mem = @import("memory.zig");

// the RLE we want
// - main idea: account for long strings of both different values and same values
//   - long strings of different are likely e.g. for matrices
// - probably 15-bit number for count + 1 bit for mode
// - mode bit off = bytes are consecutive same value
// - mode bit on = bytes are consecutive different value

pub const DataPoint = struct {
    addr: usize,
    len: usize,
    off: usize = 0, // local offset in packed frame
};

/// @item_size      number of bytes per discrete value for diff purposes
/// @layer_size     number of frames on a layer per layer keyframe
/// @layer_depth    max number of layers, i.e. max number of decodes to recover a frame's data
pub fn TemporalCompressor(
    comptime item_size: isize,
    comptime layer_size: isize,
    comptime layer_depth: isize,
) type {
    const memory_size: usize = 1024 * 1024 * 64; // 64MB
    const ItemType: type = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = 8 * item_size } });

    const layer_widths: [layer_depth]usize = widths: {
        var widths: [layer_depth]usize = undefined;
        for (1..layer_depth + 1) |f|
            widths[layer_depth - f] = std.math.pow(usize, layer_size, f);
        break :widths widths;
    };

    const off_input: usize = 0;
    const off_race: usize = ri.COMBINED_SIZE;
    const off_test: usize = off_race + rrd.SIZE;
    const off_hang: usize = off_test + re.Test.SIZE;
    const off_cman: usize = off_hang + re.Hang.SIZE;
    const off_END: usize = off_cman + re.cMan.SIZE;
    std.debug.assert(off_END % item_size == 0);
    const items: usize = off_END / item_size;

    const header_bits: usize = off_END / item_size;
    const header_size: usize = std.math.divCeil(usize, off_END, item_size * 8) catch unreachable; // comptime
    const HeaderType: type = std.packed_int_array.PackedIntArray(u1, header_bits);

    const dflt_frames: usize = 60 * 60 * 8; // 8min @ 60fps

    return struct {
        const Self = @This();

        frames: usize = 0,
        //const frame_size: usize = off_cman + rc.cMan.SIZE;
        offsets_off: usize = 0,
        offsets_size: usize = 0,
        headers_off: usize = 0,
        headers_size: usize = 0,
        stage_off: usize = 0,
        data_off: usize = 0,

        initialized: bool = false,
        frame: usize = 0,
        frame_total: usize = 0,
        last_framecount: u32 = 0,

        //sources: []DataPoint,
        //datalen: usize = 0,

        // FIXME: remove gpa/alloc, do some kind of core integration instead
        gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null,
        alloc: ?std.mem.Allocator = null,
        memory: []u8 = undefined,
        memory_addr: usize = undefined,
        memory_end_addr: usize = undefined,
        raw_offsets: [*]u8 = undefined,
        raw_headers: [*]u8 = undefined,
        raw_stage: [*]u8 = undefined,
        offsets: []usize = undefined,
        headers: []HeaderType = undefined,
        stage: [][items]ItemType = undefined,
        data: [*]u8 = undefined,

        layer_indexes: [layer_depth + 1]usize = undefined,
        layer_index_count: usize = undefined,

        pub fn init(self: *Self) void {
            std.debug.assert(!self.initialized);
            defer self.initialized = true;

            // calc sizes

            self.frames = dflt_frames;
            self.offsets_off = 0;
            self.offsets_size = self.frames * item_size;
            self.headers_off = 0 + self.offsets_size;
            self.headers_size = header_size * self.frames;
            self.stage_off = self.headers_off + self.headers_size;
            self.data_off = self.stage_off + off_END * 2;

            // allocate

            self.gpa = std.heap.GeneralPurposeAllocator(.{}){};
            self.alloc = self.gpa.?.allocator();
            self.memory = self.alloc.?.alloc(u8, memory_size) catch
                @panic("failed to allocate memory for savestate/rewind");
            @memset(self.memory[0..memory_size], 0x00);

            self.memory_addr = @intFromPtr(self.memory.ptr);
            self.memory_end_addr = @intFromPtr(self.memory.ptr) + memory_size;
            self.raw_offsets = self.memory.ptr + self.offsets_off;
            self.raw_headers = self.memory.ptr + self.headers_off;
            self.raw_stage = self.memory.ptr + self.stage_off;
            self.data = self.memory.ptr + self.data_off;
            self.offsets = @as([*]usize, @ptrFromInt(self.memory_addr + self.offsets_off))[0..self.frames];
            self.headers = @as([*]HeaderType, @ptrFromInt(self.memory_addr + self.headers_off))[0..self.frames];
            self.stage = @as([*][items]ItemType, @ptrFromInt(self.memory_addr + self.stage_off))[0..self.frames];
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.initialized);
            defer self.initialized = false;

            if (self.alloc) |a| a.free(self.memory);
            if (self.gpa) |_| switch (self.gpa.?.deinit()) {
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

            const space_ok: bool = self.memory_end_addr - @intFromPtr(self.data) - self.offsets[self.frame] >= off_END;
            const frames_ok: bool = self.frame < self.frames - 1;
            return space_ok and frames_ok;
        }

        /// get number of compression layers deep the frame at given index is
        pub fn get_depth(_: *Self, index: usize) usize {
            var depth: usize = layer_depth;
            var depth_test: usize = index;
            while (depth_test % layer_size == 0 and depth > 0) : (depth -= 1) {
                depth_test /= layer_size;
            }
            return depth;
        }

        /// update list of compression tree indexes with those for frame at given index
        pub fn set_layer_indexes(self: *Self, index: usize) void {
            self.layer_index_count = 0;
            var last_base: usize = 0;
            for (layer_widths) |w| {
                const remainder = index % w;
                const base = index - remainder;
                if (base > 0 and base != last_base) {
                    last_base = base;
                    self.layer_indexes[self.layer_index_count] = base;
                    self.layer_index_count += 1;
                }
                if (remainder < layer_size) {
                    if (remainder == 0) break;
                    self.layer_indexes[self.layer_index_count] = index;
                    self.layer_index_count += 1;
                    break;
                }
            }
        }

        pub fn uncompress_frame(self: *Self, index: usize, skip_last: bool) void {
            std.debug.assert(self.initialized);

            @memcpy(self.raw_stage[0..off_END], self.data[0..off_END]);

            self.set_layer_indexes(index);
            var indexes: usize = self.layer_index_count - @intFromBool(skip_last);
            if (indexes == 0) return;

            for (self.layer_indexes[0..indexes]) |l| {
                const header = &self.headers[l];
                const frame_data = @as([*]usize, @ptrFromInt(@intFromPtr(self.data) + self.offsets[l]));
                var j: usize = 0;
                for (0..header_bits) |h| {
                    if (header.get(h) == 1) {
                        self.stage[0][h] = frame_data[j];
                        j += 1;
                    }
                }
            }
        }

        // FIXME: in future, probably can skip the first step each new frame, because
        // the most recent frame would already be in stage1 from last time
        pub fn save_compressed(self: *Self, framecount: usize) void {
            std.debug.assert(self.initialized);

            self.last_framecount = framecount;

            var data_size: usize = 0;
            if (self.frame > 0) {
                self.uncompress_frame(self.frame, true);

                const s1_base = self.raw_stage + off_END;
                mem.read_bytes(ri.COMBINED_ADDR, s1_base + off_input, ri.COMBINED_SIZE);
                @memcpy(s1_base + off_race, rrd.PLAYER_SLICE.*);
                @memcpy(s1_base + off_test, re.Test.PLAYER_SLICE.*);
                @memcpy(s1_base + off_hang, re.Manager.entitySlice(.Hang, 0));
                @memcpy(s1_base + off_cman, re.Manager.entitySlice(.cMan, 0));

                var header = &self.headers[self.frame];
                header.setAll(0);
                var new_frame = @as([*]u32, @ptrFromInt(@intFromPtr(self.data) + self.offsets[self.frame]));
                var j: usize = 0;
                for (0..header_bits) |h| {
                    if (self.stage[0][h] != self.stage[1][h]) {
                        header.set(h, 1);
                        new_frame[j] = self.stage[1][h];
                        data_size += item_size;
                        j += 1;
                    }
                }
            } else {
                data_size = off_END;
                mem.read_bytes(ri.COMBINED_ADDR, self.data + off_input, ri.COMBINED_SIZE);
                @memcpy(self.data + off_race, rrd.PLAYER_SLICE.*);
                @memcpy(self.data + off_test, re.Test.PLAYER_SLICE.*);
                @memcpy(self.data + off_hang, re.Manager.entitySlice(.Hang, 0));
                @memcpy(self.data + off_cman, re.Manager.entitySlice(.cMan, 0));
            }
            self.frame += 1;
            self.offsets[self.frame] = self.offsets[self.frame - 1] + data_size;
        }

        pub fn load_compressed(self: *Self, index: usize) void {
            std.debug.assert(self.initialized);

            self.uncompress_frame(index, false);
            _ = mem.write_bytes(ri.COMBINED_ADDR, &self.raw_stage[off_input], ri.COMBINED_SIZE);
            @memcpy(rrd.PLAYER_SLICE.*, self.raw_stage[off_race..off_test]); // WARN: maybe perm issues
            @memcpy(re.Test.PLAYER_SLICE.*, self.raw_stage[off_test..off_hang]); // WARN: maybe perm issues
            @memcpy(re.Manager.entitySlice(.Hang, 0).ptr, self.raw_stage[off_hang..off_cman]);
            @memcpy(re.Manager.entitySlice(.cMan, 0).ptr, self.raw_stage[off_cman..off_END]);
            self.frame = index + 1;
        }
    };
}

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
