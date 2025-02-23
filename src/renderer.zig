const std = @import("std");
const geom = @import("./geom.zig");
const image = @import("./image.zig");

const Image = image.Image;
const Camera = image.Camera;
const V3 = geom.V3;
const Ray = geom.Ray;
const Hit = geom.Hit;

pub const Hittable = struct {
    ptr: *const anyopaque,
    hit: *const fn (ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit,
};

pub const Tracer = struct {
    camera: Camera,
    img: Image,
    hittables: std.ArrayList(Hittable),

    pub fn init(allocator: std.mem.Allocator, img_w: usize, aspect_ratio: f64) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / aspect_ratio);

        return .{
            .camera = Camera.initStandard(aspect_ratio, 2.0),
            .img = try Image.initEmpty(allocator, height, img_w),
            .hittables = std.ArrayList(Hittable).init(allocator),
        };
    }

    pub fn deinit(self: *const Tracer) void {
        self.hittables.deinit();
        self.img.deinit();
    }

    pub fn addObject(self: *Tracer, obj: Hittable) !void {
        try self.hittables.append(obj);
    }

    pub fn render(self: *const Tracer) void {
        var i: usize = 0;
        while (i < self.img.h) : (i += 1) {
            var j: usize = 0;
            while (j < self.img.w) : (j += 1) {
                const ray = Ray{ .dir = self.camera.pxToVp(&self.img, i, j), .origin = .{} };

                var hit: ?Hit = null;
                for (self.hittables.items) |obj| {
                    const maxt = if (hit) |h| h.t else std.math.inf(f64);

                    if (obj.hit(obj.ptr, &ray, 0, maxt)) |new_hit| {
                        hit = new_hit;
                    }
                }
                // 0,0 = lower left
                self.img.pixels[(self.img.h - 1 - i) * self.img.w + j] = rayColor(&ray, hit);
            }
        }
    }

    fn rayColor(ray: *const Ray, maybe_hit: ?Hit) V3 {
        if (maybe_hit) |hit| {
            return hit.normal.add(V3.ones()).mul(0.5);
        }
        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
        return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(V3.init(0.5, 0.7, 1.0).mul(t));
    }
};
