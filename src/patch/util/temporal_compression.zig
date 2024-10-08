const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;

const rg = @import("racer").Global;
const ri = @import("racer").Input;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const msg = @import("message.zig");
const mem = @import("memory.zig");

// TODO: convenient way to repurpose an instance for different data? i.e. rerun init
// but without alloc stuff
// TODO: impl compression as option for actual compression logic
// TODO: impl testing
// TODO: overall needs some cleanup/reorganisation, mainly surrounding implementation
// of alt compression options, which are not currently available in the compressor itself

pub const DataPoint = struct {
    data: ?[]u8 = null,
    off: usize = 0, // local offset in packed frame
};

/// @item_size      number of bytes per discrete value for diff purposes
/// @layer_size     number of frames on a layer per layer keyframe
/// @layer_depth    max number of layers, i.e. max number of decodes to recover a frame's data
pub fn TemporalCompressor(
    comptime item_size: usize,
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

    const dflt_frames: usize = 60 * 60 * 8; // 8min @ 60fps

    return struct {
        const Self = @This();

        sources: []DataPoint = undefined,

        frames: usize = 0,
        offsets_off: usize = 0,
        offsets_size: usize = 0,
        headers_off: usize = 0,
        headers_size: usize = 0, // entire header block
        header_size: usize = 0, // individual header
        stage_off: usize = 0,
        stage_items: usize = 0,
        data_off: usize = 0,

        initialized: bool = false,
        frame: usize = 0,
        frame_total: usize = 0, // FIXME: unused?
        frame_size: usize = 0,
        last_framecount: usize = 0,

        // FIXME: remove gpa/alloc, do some kind of core integration instead
        gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null,
        alloc: ?std.mem.Allocator = null,
        memory: []u8 = undefined,
        raw_offsets: [*]u8 = undefined,
        raw_headers: [*]u8 = undefined,
        raw_stage: [*]u8 = undefined,
        offsets: []usize = undefined,
        data: [*]u8 = undefined,

        layer_indexes: [layer_depth + 1]usize = undefined,
        layer_index_count: usize = undefined,

        // TODO: take in allocator, sources slice
        pub fn init(self: *Self) void {
            std.debug.assert(!self.initialized);
            defer self.initialized = true;

            // calc sizes

            self.mapSources();
            self.header_size = std.math.divCeil(usize, self.frame_size, item_size * 8) catch
                @panic("failed to calculate header size");

            self.frames = dflt_frames;
            self.offsets_off = 0;
            self.offsets_size = self.frames * item_size;
            self.headers_off = 0 + self.offsets_size;
            self.headers_size = self.header_size * self.frames;
            self.stage_off = self.headers_off + self.headers_size;
            self.stage_items = self.frame_size / item_size;
            self.data_off = self.stage_off + self.frame_size * 2;

            // allocate

            self.gpa = std.heap.GeneralPurposeAllocator(.{}){};
            self.alloc = self.gpa.?.allocator();
            self.memory = self.alloc.?.alloc(u8, memory_size) catch
                @panic("failed to allocate memory for savestate/rewind");
            @memset(self.memory[0..memory_size], 0x00);

            self.raw_offsets = self.memory.ptr + self.offsets_off;
            self.raw_headers = self.memory.ptr + self.headers_off;
            self.raw_stage = self.memory.ptr + self.stage_off;
            self.data = self.memory.ptr + self.data_off;
            self.offsets = @as([*]usize, @ptrCast(@alignCast(self.memory.ptr + self.offsets_off)))[0..self.frames];
        }

        pub fn deinit(self: *Self) void {
            if (!self.initialized) return;
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

        pub fn canSave(self: *Self) bool {
            std.debug.assert(self.initialized);
            const space_ok: bool = @intFromPtr(self.memory.ptr + self.memory.len) -
                @intFromPtr(self.data) - self.offsets[self.frame] >= self.frame_size;
            const frames_ok: bool = self.frame < self.frames - 1;
            return space_ok and frames_ok;
        }

        /// configure offsets of each source, and set total size
        fn mapSources(self: *Self) void {
            var offset: usize = 0;
            for (self.sources) |*source| {
                std.debug.assert(source.data != null);
                std.debug.assert(source.data.?.len % item_size == 0);
                source.off = offset;
                offset += source.data.?.len;
            }
            self.frame_size = offset;
        }

        inline fn getHeader(self: *Self, index: usize) []u8 {
            std.debug.assert(index < self.frames);
            const base = index * self.header_size;
            return self.raw_headers[base .. base + self.header_size];
        }

        inline fn getStage(self: *Self, index: usize) []ItemType {
            std.debug.assert(index < 2);
            const base = index * self.stage_items;
            return @as([*]ItemType, @ptrCast(@alignCast(self.raw_stage)))[base .. base + self.stage_items];
        }

        // TODO: rework this to eliminate edge cases where depth should be >0, e.g. first handful of frames
        /// get number of compression layers deep the frame at given index is
        /// @index      frame to target
        fn getDepth(_: *Self, index: usize) usize {
            var depth: usize = layer_depth;
            var depth_test: usize = index;
            while (depth_test % layer_size == 0 and depth > 0) : (depth -= 1)
                depth_test /= layer_size;
            return depth;
        }

        /// update list of compression tree indexes with those for frame at given index
        /// @index      frame to target
        fn setLayerIndexes(self: *Self, index: usize) void {
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

        // TODO: return slice?
        /// decode frame into stage 0
        /// @index      frame to decode
        /// @skip_last  don't decode last layer in chain, used to set basis for new encode
        pub fn decode(self: *Self, index: usize, skip_last: bool) void {
            std.debug.assert(self.initialized);

            @memcpy(self.raw_stage[0..self.frame_size], self.data[0..self.frame_size]);

            self.setLayerIndexes(index);
            var indexes: usize = self.layer_index_count - @intFromBool(skip_last);
            if (indexes == 0) return;

            for (self.layer_indexes[0..indexes]) |l| {
                const header = self.getHeader(l);
                const frame_data = @as([*]usize, @ptrFromInt(@intFromPtr(self.data) + self.offsets[l]));
                var stage = self.getStage(0);
                var j: usize = 0;
                for (0..self.stage_items) |h| {
                    const byte = h / 8;
                    const mask: u8 = @as(u8, 1) << @as(u3, @intCast(h % 8));
                    if (header[byte] & mask > 0) {
                        stage[h] = frame_data[j];
                        j += 1;
                    }
                }
            }
        }

        // FIXME: in future, probably can skip the first step each new frame, because
        // the most recent frame would already be in stage1 from last time
        pub fn save(self: *Self, framecount: usize) void {
            std.debug.assert(self.initialized);

            self.last_framecount = framecount;

            var data_size: usize = 0;
            if (self.frame > 0) {
                self.decode(self.frame, true);

                const s1_base = self.raw_stage + self.frame_size;
                for (self.sources) |*source|
                    @memcpy(s1_base + source.off, source.data.?);

                var header = self.getHeader(self.frame);
                @memset(header, 0);
                var new_frame = @as([*]u32, @ptrFromInt(@intFromPtr(self.data) + self.offsets[self.frame]));
                var j: usize = 0;
                for (0..self.stage_items) |h| {
                    const byte = h / 8;
                    const mask: u8 = @as(u8, 1) << @as(u3, @intCast(h % 8));
                    const stage0 = self.getStage(0);
                    const stage1 = self.getStage(1);
                    if (stage0[h] != stage1[h]) {
                        header[byte] |= mask;
                        new_frame[j] = stage1[h];
                        data_size += item_size;
                        j += 1;
                    }
                }
            } else {
                data_size = self.frame_size;
                for (self.sources) |*source|
                    @memcpy(self.data + source.off, source.data.?);
            }
            self.frame += 1;
            self.offsets[self.frame] = self.offsets[self.frame - 1] + data_size;
        }

        pub fn restore(self: *Self, index: usize) void {
            std.debug.assert(self.initialized);

            self.decode(index, false);
            for (self.sources) |*source|
                @memcpy(source.data.?, self.raw_stage[source.off .. source.off + source.data.?.len]);
            self.frame = index + 1;
        }

        const Compression = enum(u16) {
            none,
            bfid, // bitfield-indexed diff
            xrle, // xor + rle
            xrles, // xor + rle signed
        };

        const READ_WRITE_VER: u16 = 0;

        const WriteSettings = struct {
            compression: Compression = .none,
            compression_version: u16 = 0,
            frames: usize = std.math.maxInt(usize),
            headers: bool = true,
        };

        // TODO: reader equiv for input
        // TODO: writing only specific sources
        // TODO: custom starting frame
        /// dump raw data to file, useful for gathering test data
        pub fn write(self: *Self, writer: anytype, opts: WriteSettings) !void {
            std.debug.assert(self.initialized);
            // TODO: double-check idiomatic way of verifying arbitrary passed-in writers, following rejected
            //std.debug.assert(@hasField(writer, "context"));
            //std.debug.assert(@hasDecl(writer, "Error"));
            //std.debug.assert(@hasDecl(writer, "write"));

            // common header
            if (opts.headers) {
                try writer.writeIntNative(u16, READ_WRITE_VER);
                try writer.writeIntNative(u16, @intFromEnum(opts.compression));
                try writer.writeIntNative(u16, opts.compression_version);
                try writer.writeIntNative(usize, opts.frames);
                try writer.writeIntNative(usize, self.frame_size);
                try writer.writeIntNative(usize, self.sources.len);
                for (self.sources) |*source|
                    try writer.writeIntNative(usize, if (source.data) |d| d.len else 0);
            }

            const frame_st: usize = 0;
            const frame_ed: usize = @min(self.frame + 1, opts.frames);
            switch (opts.compression) {
                .none => {
                    for (frame_st..frame_ed) |i| {
                        self.decode(i, false);
                        try writer.writeAll(self.raw_stage[0..self.frame_size]);
                    }
                },
                .bfid => return error.CompressionNotImplemented,
                .xrle => return error.CompressionNotImplemented,
                .xrles => return error.CompressionNotImplemented,
            }
        }

        const TestSettings = struct {
            compression: Compression,
            sub_path: []const u8,
            frame_size: usize,
            item_size: usize = 4,
            layer_size: usize = 4,
            layer_depth: usize = 4,
            headers: bool = false, // false = input data is raw uncompressed dump
            rle_head_size: ?usize = null,
        };

        // TODO: strategy pattern thing for the actual compress step (diffing two frames into an output)
        pub fn calcPotential(alloc: Allocator, writer: anytype, opts: TestSettings) !void {
            std.debug.assert(opts.compression != .none);
            std.debug.assert(opts.frame_size % opts.item_size == 0);

            var str: []u8 = "";
            var substr: []u8 = "";
            const can_write: bool = @hasDecl(@TypeOf(writer), "writeAll");

            // TODO: impl compressed input
            if (opts.headers) return error.CompressedInputNotSupported;

            // TODO: remove arena here, i.e. let caller decide if they will pass in an arena
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();
            var arena_a = arena.allocator();

            const file = try std.fs.cwd().openFile(opts.sub_path, .{});
            defer file.close();

            // header
            if (can_write) {
                str = try allocPrint(arena_a,
                    \\testing: {s}
                    \\---
                    \\compression       {s}
                    \\layer size        {d}
                    \\layer depth       {d}
                    \\item size         {d}
                    \\rle head size     {?d}
                    \\---
                    \\
                , .{
                    opts.sub_path,
                    @tagName(opts.compression),
                    opts.layer_size,
                    opts.layer_depth,
                    opts.item_size,
                    opts.rle_head_size,
                });
                try writer.writeAll(str);
            }

            var stage: []u8 = try arena_a.alloc(u8, opts.frame_size * (opts.layer_depth + 1));

            var frame: usize = 0;
            var size_orig: usize = 0;
            var size_comp: usize = 0;
            const file_r = file.reader();

            while (true) : (frame += 1) {
                var depth: usize = opts.layer_depth;
                var depth_test: usize = frame;
                while (depth_test % opts.layer_size == 0 and depth > 0) : (depth -= 1)
                    depth_test /= opts.layer_size;

                const base = depth * opts.frame_size;
                var data: []u8 = stage[base .. base + opts.frame_size];
                if (try file_r.read(data) < opts.frame_size) break;

                if (depth == 0) {
                    for (0..opts.layer_depth) |d| {
                        const idx = (d + 1) * opts.frame_size;
                        @memcpy(stage[idx .. idx + opts.frame_size], data);
                    }
                }

                const items: usize = opts.frame_size / opts.item_size;
                const frame_bytes: usize = switch (opts.compression) {
                    .none => 0,
                    .bfid => bytes: {
                        const head_size = try std.math.divCeil(usize, opts.frame_size / opts.item_size, 8);
                        if (depth > 0) {
                            const data_prev: []u8 = stage[base - opts.frame_size .. base];
                            var dif_bytes: usize = 0;
                            for (0..items) |i| {
                                const idx = i * opts.item_size;
                                const new = data[idx .. idx + opts.item_size];
                                const src = data_prev[idx .. idx + opts.item_size];
                                if (!std.mem.eql(u8, new, src)) dif_bytes += opts.item_size;
                            }
                            break :bytes dif_bytes + head_size;
                        }
                        break :bytes opts.frame_size + head_size;
                    },
                    .xrle => bytes: {
                        std.debug.assert(opts.rle_head_size != null);
                        const head_size: usize = opts.rle_head_size.?;
                        const head_max: usize = try std.math.powi(usize, 2, 8 * head_size) - 1;
                        var runs: usize = 0;
                        var run_len: usize = 0;
                        var len: usize = 0;
                        var is_same: bool = true;
                        var last = try alloc.alloc(u8, opts.item_size);
                        defer alloc.free(last);
                        @memset(last, 0x00);
                        var total_runs: usize = 0;
                        var max_run_len: usize = 0;
                        var total_run_len: usize = 0;
                        defer if (can_write) blk: {
                            substr = allocPrint(arena_a, "runs:{d: <4}    max:{d: <4}  avg:{d: <4}", .{
                                total_runs,
                                max_run_len,
                                if (total_run_len > 0) total_run_len / total_runs else 0,
                            }) catch break :blk;
                        };

                        if (depth > 0) {
                            const data_prev: []u8 = stage[base - opts.frame_size .. base];
                            for (data, data_prev, 0..) |b1, b2, i| {
                                const x = b1 ^ b2;
                                const sub_i = i % opts.item_size;
                                is_same = is_same and last[sub_i] == x;
                                last[sub_i] = x;
                                if (sub_i + 1 != opts.item_size) continue;
                                defer is_same = true;

                                if (run_len > head_max or !is_same) {
                                    if (max_run_len < run_len) max_run_len = @min(run_len, head_max);
                                    total_run_len += @min(run_len, head_max);
                                    len += head_size + opts.item_size;
                                    runs += 1;
                                    run_len = 0;
                                }
                                run_len += 1;
                            }

                            if (total_runs < runs) total_runs = runs;
                            break :bytes len;
                        }

                        // FIXME: for 0 case, do we still do RLE but against 00 bytes?
                        break :bytes opts.frame_size;
                    },
                    .xrles => bytes: {
                        std.debug.assert(opts.rle_head_size != null);
                        const head_size: usize = opts.rle_head_size.?;
                        const head_max: usize = try std.math.powi(usize, 2, 8 * head_size - 1) - 1;
                        var runs: usize = 0;
                        var run_len: usize = 0;
                        var run_type: enum(u8) { none, same, dif } = .none;
                        var len: usize = 0;
                        var is_same: bool = true;
                        var last = try alloc.alloc(u8, opts.item_size);
                        defer alloc.free(last);
                        @memset(last, 0x00);

                        var total_runs: usize = 0;
                        var pos_runs_total: usize = 0;
                        var pos_run_len_max: usize = 0;
                        var pos_run_len_total: usize = 0;
                        var neg_runs_total: usize = 0;
                        var neg_run_len_max: usize = 0;
                        var neg_run_len_total: usize = 0;
                        defer if (can_write) blk: {
                            substr = allocPrint(arena_a, "runs:{d: <4}    p:{d: <4}  pmax:{d: <4}  pavg:{d: <4}    n:{d: <4}  nmax:{d: <4}  navg:{d: <4}", .{
                                total_runs,
                                pos_runs_total,
                                pos_run_len_max,
                                if (pos_run_len_total > 0) pos_run_len_total / pos_runs_total else 0,
                                neg_runs_total,
                                neg_run_len_max,
                                if (neg_run_len_total > 0) neg_run_len_total / neg_runs_total else 0,
                            }) catch break :blk;
                        };

                        if (depth > 0) {
                            const data_prev: []u8 = stage[base - opts.frame_size .. base];
                            for (data, data_prev, 0..) |b1, b2, i| {
                                const x = b1 ^ b2;
                                const sub_i = i % opts.item_size;
                                is_same = is_same and last[sub_i] == x;
                                last[sub_i] = x;
                                if (sub_i + 1 != opts.item_size) continue;
                                defer is_same = true;

                                switch (run_type) {
                                    .none => {
                                        run_type = if (is_same) .same else .dif;
                                        if (is_same) neg_runs_total += 1 else pos_runs_total += 1;
                                        runs += 1;
                                    },
                                    .same => same: {
                                        if (run_len > head_max) {
                                            if (pos_run_len_max < run_len) pos_run_len_max = head_max;
                                            pos_run_len_total += head_max;
                                            len += head_size + opts.item_size;
                                            run_len = 0;
                                            run_type = .none;
                                            break :same;
                                        }
                                        if (!is_same) {
                                            if (pos_run_len_max < run_len) pos_run_len_max = run_len;
                                            pos_run_len_total += run_len;
                                            len += head_size + opts.item_size;
                                            run_len = 0;
                                            run_type = .dif;
                                            runs += 1;
                                            pos_runs_total += 1;
                                        }
                                    },
                                    .dif => dif: {
                                        if (run_len > head_max) {
                                            if (neg_run_len_max < run_len) neg_run_len_max = head_max;
                                            neg_run_len_total += head_max;
                                            len += head_size + head_max * opts.item_size;
                                            run_len = 0;
                                            run_type = .none;
                                            runs += 1;
                                            break :dif;
                                        }
                                        if (is_same) {
                                            if (neg_run_len_max < run_len) neg_run_len_max = run_len;
                                            neg_run_len_total += run_len;
                                            len += head_size + run_len * opts.item_size;
                                            run_len = 0;
                                            run_type = .same;
                                            runs += 1;
                                            neg_runs_total += 1;
                                        }
                                    },
                                }
                                run_len += 1;
                            }
                            if (run_type == .dif) { // leftovers
                                len += head_size + run_len * opts.item_size;
                                neg_run_len_total += run_len;
                            }

                            if (total_runs < runs) total_runs = runs;
                            break :bytes len;
                        }

                        // FIXME: for 0 case, do we still do RLE but against 00 bytes?
                        break :bytes opts.frame_size;
                    },
                };

                size_orig += opts.frame_size;
                size_comp += frame_bytes;

                if (can_write) {
                    str = try allocPrint(
                        arena_a,
                        "F:{d: <4}  D:{d: <2}    out:{d: <6}    {s}\n",
                        .{ frame, depth, frame_bytes, substr },
                    );
                    try writer.writeAll(str);
                }
            }
            if (can_write) try writer.writeAll("---\n");

            // footer
            if (can_write) {
                str = try allocPrint(arena_a,
                    \\frames            {d}
                    \\frame size        {d}
                    \\original size     {d}
                    \\compressed size   {d}
                    \\ratio             {d:6.4}
                    \\---
                    \\
                    \\
                , .{
                    frame,
                    opts.frame_size,
                    size_orig,
                    size_comp,
                    @as(f32, @floatFromInt(size_comp)) / @as(f32, @floatFromInt(size_orig)),
                });
                try writer.writeAll(str);
            }
        }
    };
}

//test "dump recorded data" {
//    if (gf.InputGetKb(.J, .JustOn)) blk: {
//        const file = std.fs.cwd().createFile("annodue/test_frame_data_dump.bin", .{}) catch break :blk;
//        defer file.close();
//        var file_w = file.writer();
//        state.rec_data.write(file_w, .{ .frames = 256, .headers = false }) catch break :blk;
//        dbg.ConsoleOut(
//            "frame data written to file\n  frame size: 0x{X}\n",
//            .{state.rec_data.frame_size},
//        ) catch {};
//    }
//}

//test "calculate compression potential" {
//    if (gf.InputGetKb(.F, .JustOn)) blk: {
//        const file = std.fs.cwd().createFile("annodue/recording_raw-0x2458-nohead_mgs.bin.txt", .{}) catch
//            break :blk;
//        defer file.close();
//        RewindDataType.calcPotential(alloc, file.writer(), .{
//            .compression = .xrles,
//            .sub_path = "annodue/recording_raw-0x2458-nohead_mgs.bin",
//            .frame_size = 0x2458,
//            .item_size = 1,
//            .rle_head_size = 1,
//        }) catch {};
//    }
//}
