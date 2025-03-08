const std = @import("std");
const V3 = @import("./vec.zig").V3;

pub const Camera = struct {
    height: f64,
    width: f64,
    img_height: usize,
    img_width: usize,
    focal_length: f64 = 1,
    px_delta: V3,
    lower_left: V3,

    pub fn initStandard(height: f64, width: f64, img_height: usize, img_width: usize) Camera {
        const focal_length: f64 = 1;
        const fh: f64 = @floatFromInt(img_height);
        const fw: f64 = @floatFromInt(img_width);
        const px_delta = V3.init(width / fw, -height / fh, 0);
        return .{
            .height = height,
            .width = width,
            .img_height = img_height,
            .img_width = img_width,
            .focal_length = focal_length,
            .lower_left = V3.init(-width / 2, height / 2, -focal_length).add(px_delta.mul(0.5)),
            .px_delta = px_delta,
        };
    }

    pub fn pxToVp(self: *const Camera, px: usize, py: usize, rng: ?std.Random) V3 {
        var x: f64 = @floatFromInt(px);
        var y: f64 = @floatFromInt(py);
        if (rng) |r| {
            x += r.float(f64);
            y += r.float(f64);
        }

        return V3.init(x * self.px_delta.x(), y * self.px_delta.y(), 0).add(self.lower_left);
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
            const clm = vsqrt(px).clamp(0, 1);
            const x: u8 = @intFromFloat(clm.x() * 255);
            const y: u8 = @intFromFloat(clm.y() * 255);
            const z: u8 = @intFromFloat(clm.z() * 255);
            try w.print("{d} {d} {d}\n", .{ x, y, z });
        }
    }
};

fn vsqrt(v: V3) V3 {
    return V3.init(
        if (v.x() > 0) @sqrt(v.x()) else 0,
        if (v.y() > 0) @sqrt(v.y()) else 0,
        if (v.z() > 0) @sqrt(v.z()) else 0,
    );
}
