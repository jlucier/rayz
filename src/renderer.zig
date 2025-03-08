const std = @import("std");
const vec = @import("./vec.zig");
const image = @import("./image.zig");
const hitmod = @import("./hit.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;
const Hittable = hitmod.Hittable;

pub const Tracer = struct {
    camera: image.Camera,
    img: image.Image,
    hittables: std.ArrayList(Hittable),
    rng: std.Random.DefaultPrng,
    max_bounces: usize = 50,

    pub fn init(allocator: std.mem.Allocator, img_w: usize, aspect_ratio: f64) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / aspect_ratio);

        const fimg_h: f64 = @floatFromInt(height);
        return .{
            .camera = image.Camera.initStandard(2.0, 2.0 * fimg_w / fimg_h, height, img_w),
            .img = try image.Image.initEmpty(allocator, height, img_w),
            .hittables = std.ArrayList(Hittable).init(allocator),
            .rng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            }),
        };
    }

    pub fn deinit(self: *const Tracer) void {
        self.hittables.deinit();
        self.img.deinit();
    }

    pub fn addObject(self: *Tracer, obj: Hittable) !void {
        try self.hittables.append(obj);
    }

    pub fn render(self: *Tracer) usize {
        var rays: usize = 0;
        var j: usize = 0;
        const samples_per_px: usize = 1;

        while (j < self.img.h) : (j += 1) {
            var i: usize = 0;
            while (i < self.img.w) : (i += 1) {
                var r: usize = 0;
                var acc_color = V3{};
                while (r < samples_per_px) : (r += 1) {
                    const ray = Ray{
                        .dir = self.camera.pxToVp(i, j, null
                            // self.rng.random()
                        ),
                        .origin = .{},
                    };
                    rays += 1;

                    // const new_color = if (i != 49 or j != 15) V3.init(0, 0, 0) //
                    const new_color = self.bounceRay(ray, self.max_bounces, i == 49 and j == 15);
                    acc_color = acc_color.add(new_color);
                }

                self.img.pixels[j * self.img.w + i] = //
                    acc_color.div(@floatFromInt(samples_per_px));
            }
        }
        return rays;
    }

    fn findHit(self: *const Tracer, ray: Ray) ?Hit {
        var maybe_hit: ?Hit = null;
        for (self.hittables.items) |obj| {
            const maxt = if (maybe_hit) |hit| hit.t else std.math.inf(f64);

            if (obj.hit(obj.ptr, &ray, 1e-10, maxt)) |new_hit| {
                maybe_hit = new_hit;
            }
        }
        return maybe_hit;
    }

    fn bounceRay(self: *Tracer, ray: Ray, depth: usize, print: bool) V3 {
        if (depth == 0)
            return V3{};

        if (self.findHit(ray)) |hit| {
            // bounce light
            var ret = V3{};
            const res = hit.material.scatter(self.rng.random(), &ray, &hit).?;
            // if () |res| {
            if (print) {
                std.debug.print("\nog: {}\n", .{ray});
            }
            ret = self.bounceRay(res.ray, depth - 1, print).vecMul(res.attenuation);
            // }
            if (print) {
                std.debug.print("scat: {}\n", .{res.ray});
                std.debug.print("col: {}\n\n", .{ret});
            }
            return ret;
        }
        if (print) {
            std.debug.print("miss! {}\n", .{ray});
        }
        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
        return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(V3.init(0.5, 0.7, 1.0).mul(t));
    }
};
