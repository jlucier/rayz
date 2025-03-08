const std = @import("std");
const V3 = @import("./vec.zig").V3;

pub const Image = struct {
    h: usize,
    w: usize,
    pixels: []V3,
    allocator: ?std.mem.Allocator,

    pub fn initEmpty(allocator: std.mem.Allocator, h: usize, w: usize) !Image {
        return .{
            .h = h,
            .w = w,
            .pixels = try allocator.alloc(V3, h * w),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Image) void {
        if (self.allocator) |a| {
            a.free(self.pixels);
        }
    }

    pub fn at(self: *Image, i: usize, j: usize) *V3 {
        return &self.pixels[i * self.w + j];
    }

    pub fn writePPM(self: *const Image, f: std.fs.File) !void {
        const w = f.writer();

        try w.print("P3\n{} {}\n{}\n", .{ self.w, self.h, 255 });

        for (self.pixels) |px| {
            const clm = px.sqrt().clamp(0, 1);
            const x: u8 = @intFromFloat(clm.x() * 255);
            const y: u8 = @intFromFloat(clm.y() * 255);
            const z: u8 = @intFromFloat(clm.z() * 255);
            try w.print("{d} {d} {d}\n", .{ x, y, z });
        }
    }
};
