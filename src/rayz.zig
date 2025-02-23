const std = @import("std");
const image = @import("./image.zig");
const vec = @import("./vec.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Image = image.Image;
const Camera = image.Camera;

fn hitSphere(ray: *const Ray, origin: V3, radius: f64) f64 {
    // check quadratic formula discriminant for roots, if real roots then hit
    const offset = ray.origin.sub(origin);

    const a = ray.dir.dot(ray.dir);
    const half_b = ray.dir.dot(offset);
    const c = offset.dot(offset) - radius * radius;

    const discriminant = half_b * half_b - a * c;
    if (discriminant < 0) {
        return -1.0;
    }
    return (-half_b - @sqrt(discriminant)) / a;
}

fn rayColor(ray: *const Ray) V3 {
    const sphere_og = V3.init(0, 0, -1);
    const soln = hitSphere(ray, sphere_og, 0.5);
    if (soln >= 0) {
        const n = ray.at(soln).sub(sphere_og).unit();
        return n.add(V3.ones()).mul(0.5);
    }

    // miss, background gradient
    const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
    return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(V3.init(0.5, 0.7, 1.0).mul(t));
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const img_w = try std.fmt.parseUnsigned(usize, args.next().?, 10);
    const fimg_w: f64 = @floatFromInt(img_w);

    const cam = Camera.initStandard(16.0 / 9.0, 2);
    const height: usize = @intFromFloat(fimg_w / cam.aspect_ratio);

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

    if (args.next()) |out_fname| {
        const f = try std.fs.cwd().createFile(out_fname, .{ .read = false, .truncate = true });
        defer f.close();
        try im.writePPM(f);
    } else {
        try im.writePPM(std.io.getStdOut());
    }
}
