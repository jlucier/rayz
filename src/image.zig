const std = @import("std");
const V3 = @import("./geom.zig").V3;

pub const Camera = struct {
    aspect_ratio: f64,
    height: f64,
    width: f64,
    focal_length: f64 = 1,

    pub fn initStandard(aspect_ratio: f64, height: f64) Camera {
        return .{
            .aspect_ratio = aspect_ratio,
            .height = height,
            .width = height * aspect_ratio,
        };
    }

    pub fn lower_left(self: *const Camera) V3 {
        return V3.init(-self.width / 2, -self.height / 2, -self.focal_length);
    }

    pub fn pxToVp(self: *const Camera, im: *const Image, py: usize, px: usize) V3 {
        const x: f64 = @floatFromInt(px);
        const y: f64 = @floatFromInt(py);
        const w: f64 = @floatFromInt(im.w - 1);
        const h: f64 = @floatFromInt(im.h - 1);
        const u = x / w * self.width;
        const v = y / h * self.height;

        return self.lower_left().add(V3.init(u, v, 0));
    }
};

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
            const x: u8 = @intFromFloat(px.x() * 255);
            const y: u8 = @intFromFloat(px.y() * 255);
            const z: u8 = @intFromFloat(px.z() * 255);
            try w.print("{d} {d} {d}\n", .{ x, y, z });
        }
    }
};
