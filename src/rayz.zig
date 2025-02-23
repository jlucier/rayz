const std = @import("std");
const image = @import("./image.zig");
const vec = @import("./vec.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Image = image.Image;
const Camera = image.Camera;

fn rayColor(ray: *const Ray) V3 {
    const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
    return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(&V3.init(0.5, 0.7, 1.0).mul(t));
}

pub fn main() !void {
    const cam = Camera{
        .aspect_ratio = 16.0 / 9.0,
        .height = 2,
        .width = 4,
        .focal_length = 1,
    };
    const img_w: usize = 180;
    const height: usize = @intFromFloat(img_w / cam.aspect_ratio);

    var im = try Image.initEmpty(std.heap.page_allocator, height, img_w);
    defer im.deinit();

    var i: usize = 0;
    while (i < im.h) : (i += 1) {
        var j: usize = 0;
        while (j < im.w) : (j += 1) {
            const ray = Ray{ .dir = cam.pxToVp(&im, i, j), .origin = .{} };
            // 0,0 = lower left
            im.pixels[(im.h - 1 - i) * im.w + j] = rayColor(&ray);
        }
    }
    try im.writePPM(std.io.getStdOut());
}
