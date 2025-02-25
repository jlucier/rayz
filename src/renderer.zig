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
    rng: std.rand.DefaultPrng,
    max_bounces: usize = 50,

    pub fn init(allocator: std.mem.Allocator, img_w: usize, aspect_ratio: f64) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / aspect_ratio);

        return .{
            .camera = Camera.initStandard(aspect_ratio, 2.0),
            .img = try Image.initEmpty(allocator, height, img_w),
            .hittables = std.ArrayList(Hittable).init(allocator),
            .rng = std.rand.DefaultPrng.init(blk: {
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
        var i: usize = 0;
        const samples_per_px: usize = 100;

        const w: f64 = @floatFromInt(self.img.w - 1);
        const h: f64 = @floatFromInt(self.img.h - 1);

        while (i < self.img.h) : (i += 1) {
            var j: usize = 0;
            while (j < self.img.w) : (j += 1) {
                var r: usize = 0;
                var acc_color = V3{};
                while (r < samples_per_px) : (r += 1) {
                    const u: f64 = @floatFromInt(j);
                    const v: f64 = @floatFromInt(i);
                    const ray = Ray{
                        .dir = self.camera.uvToVp(
                            (u + self.rng.random().float(f64)) / w,
                            (v + self.rng.random().float(f64)) / h,
                        ),
                        .origin = .{},
                    };
                    rays += 1;

                    const new_color = self.bounceRay(ray, self.max_bounces);
                    acc_color = acc_color.add(new_color);
                }

                // 0,0 = lower left
                self.img.pixels[(self.img.h - 1 - i) * self.img.w + j] = //
                    acc_color.div(@floatFromInt(samples_per_px));
            }
        }
        return rays;
    }

    fn findHit(self: *const Tracer, ray: Ray) ?Hit {
        var maybe_hit: ?Hit = null;
        for (self.hittables.items) |obj| {
            const maxt = if (maybe_hit) |hit| hit.t else std.math.inf(f64);

            if (obj.hit(obj.ptr, &ray, 0, maxt)) |new_hit| {
                maybe_hit = new_hit;
            }
        }
        return maybe_hit;
    }

    fn bounceRay(self: *Tracer, ray: Ray, depth: usize) V3 {
        if (depth == 0)
            return V3{};

        if (self.findHit(ray)) |hit| {
            // bounce light
            const rand_loc = V3.randomInUnitSphere(self.rng.random());
            const target = hit.point.add(hit.normal).add(rand_loc);
            const rand_dir = target.sub(hit.point);
            const bounce = Ray{ .origin = hit.point, .dir = rand_dir };
            return self.bounceRay(bounce, depth - 1).mul(0.5);
        }
        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
        return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(V3.init(0.5, 0.7, 1.0).mul(t));
    }
};
