const std = @import("std");
const vec = @import("./vec.zig");
const image = @import("./image.zig");
const hitmod = @import("./hit.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;
const Hittable = hitmod.Hittable;

const DEG_TO_RAD = std.math.pi / 180.0;
const ASPECT_RATIO = 16.0 / 9.0;

pub const Camera = struct {
    px_delta: V3,
    lower_left: V3,

    pub fn initStandard(
        vfov: f64,
        focal_length: f64,
        img_height: usize,
        img_width: usize,
    ) Camera {
        const fh: f64 = @floatFromInt(img_height);
        const fw: f64 = @floatFromInt(img_width);

        const height = 2 * std.math.tan(vfov * DEG_TO_RAD / 2.0) * focal_length;
        const width = height * fw / fh;

        const px_delta = V3.init(width / fw, -height / fh, 0);
        return .{
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

pub const Tracer = struct {
    camera: Camera,
    img: image.Image,
    hittables: std.ArrayList(Hittable),
    rng: std.Random.DefaultPrng,
    max_bounces: usize = 50,
    samples_per_px: usize = 100,

    pub fn init(allocator: std.mem.Allocator, img_w: usize) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / ASPECT_RATIO);

        return .{
            .camera = Camera.initStandard(90.0, 1.0, height, img_w),
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

        while (j < self.img.h) : (j += 1) {
            var i: usize = 0;
            const fj: f64 = @floatFromInt(j);
            const fh: f64 = @floatFromInt(self.img.h);
            std.debug.print("\rProgress: {d:.2}%", .{fj / fh * 100});
            while (i < self.img.w) : (i += 1) {
                var r: usize = 0;
                var acc_color = V3{};
                while (r < self.samples_per_px) : (r += 1) {
                    const ray = Ray{
                        .dir = self.camera.pxToVp(i, j, self.rng.random()),
                        .origin = .{},
                    };
                    rays += 1;

                    acc_color = acc_color.add(self.bounceRay(ray, self.max_bounces));
                }

                self.img.pixels[j * self.img.w + i] = //
                    acc_color.div(@floatFromInt(self.samples_per_px));
            }
        }
        std.debug.print("\rProgress: {d:.2}%", .{100.0});
        std.debug.print("\n", .{});
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

    fn bounceRay(self: *Tracer, ray: Ray, depth: usize) V3 {
        if (depth == 0)
            return V3{};

        if (self.findHit(ray)) |hit| {
            // bounce light
            var ret = V3{};
            if (hit.material.scatter(self.rng.random(), &ray, &hit)) |res| {
                ret = self.bounceRay(res.ray, depth - 1).vecMul(res.attenuation);
            }
            return ret;
        }
        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y() + 1.0);
        return V3.init(1.0, 1.0, 1.0).mul(1.0 - t).add(V3.init(0.5, 0.7, 1.0).mul(t));
    }
};
