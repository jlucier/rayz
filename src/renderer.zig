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
    look_from: V3,
    px_du: V3,
    px_dv: V3,
    px_origin: V3,
    defocus_u: V3,
    defocus_v: V3,
    defocus: bool,

    pub fn init(
        vfov: f64,
        focus_dist: f64,
        defocus_angle: f64,
        look_from: V3,
        look_at: V3,
        vup: V3,
        img_height: usize,
        img_width: usize,
    ) Camera {
        const fimg_h: f64 = @floatFromInt(img_height);
        const fimg_w: f64 = @floatFromInt(img_width);

        const vp_height = 2 * std.math.tan(vfov * DEG_TO_RAD / 2.0) * focus_dist;
        const vp_width = vp_height * fimg_w / fimg_h;

        const w = look_from.sub(look_at).unit();
        const u = vup.cross(w).unit();
        const v = w.cross(u);

        const vp_u = u.mul(vp_width);
        const vp_v = v.mul(-vp_height);
        const px_du = vp_u.div(fimg_w);
        const px_dv = vp_v.div(fimg_h);
        const defocus_radius = std.math.tan(defocus_angle * DEG_TO_RAD / 2) * focus_dist;

        const vp_origin = look_from.sub(w.mul(focus_dist)).sub(vp_u.div(2)).sub(
            vp_v.div(2),
        ).add(px_du.add(px_dv).mul(0.5));

        return .{
            .look_from = look_from,
            .px_du = px_du,
            .px_dv = px_dv,
            .px_origin = vp_origin,
            .defocus_u = u.mul(defocus_radius),
            .defocus_v = v.mul(defocus_radius),
            .defocus = defocus_angle > 0,
        };
    }

    pub fn getRay(self: *const Camera, px: usize, py: usize, rng: ?std.Random) Ray {
        var x: f64 = @floatFromInt(px);
        var y: f64 = @floatFromInt(py);
        var origin = self.look_from;
        if (rng) |r| {
            x += r.float(f64) - 0.5;
            y += r.float(f64) - 0.5;

            origin = origin.add(self.randomInDefocus(r));
        }

        return .{
            .dir = self.px_du.mul(x).add(self.px_dv.mul(y)).add(
                self.px_origin,
            ).sub(origin),
            .origin = origin,
            .time = if (rng) |r| r.float(f64) else 0,
        };
    }

    fn randomInDefocus(self: *const Camera, rng: std.Random) V3 {
        if (!self.defocus) {
            return .{};
        }

        while (true) {
            const v = V3{ .x = rng.float(f64) * 2 - 1, .y = rng.float(f64) * 2 - 1, .z = 0 };
            if (v.dot(v) <= 1) {
                return self.defocus_u.mul(v.x).add(self.defocus_v.mul(v.y));
            }
        }
    }
};

pub const Tracer = struct {
    camera: Camera,
    img: image.Image,
    hittables: std.ArrayList(Hittable),
    rng: std.Random.DefaultPrng,
    max_bounces: usize = 50,
    samples_per_px: usize = 100,

    pub fn init(
        allocator: std.mem.Allocator,
        img_w: usize,
        vfov: f64,
        focus_dist: f64,
        defocus_angle: f64,
        look_from: V3,
        look_at: V3,
        vup: V3,
    ) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / ASPECT_RATIO);

        return .{
            .camera = Camera.init(
                vfov,
                focus_dist,
                defocus_angle,
                look_from,
                look_at,
                vup,
                height,
                img_w,
            ),
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
                    const ray = self.camera.getRay(i, j, self.rng.random());
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
        const t: f64 = 0.5 * (ray.dir.unit().y + 1.0);
        return V3.ones().mul(1.0 - t).add(V3{ .x = 0.5, .y = 0.7, .z = 1.0 }).mul(t);
    }
};

test "get ray" {
    const cam = Camera.init(
        90,
        V3{ .x = -2, .y = 2, .z = 1 }, // look_from
        V3{ .x = 0, .y = 0, .z = -1 }, // look_at
        V3.y_hat(), // vup
        225,
        400,
    );

    const r1 = cam.getRay(0, 0, null);
    const r2 = cam.getRay(112, 199, null);

    try std.testing.expectApproxEqRel(-0.935834, r1.dir.x, 1e-5);
    try std.testing.expectApproxEqRel(0.815856, r1.dir.y, 1e-5);
    try std.testing.expectApproxEqRel(-7.75169, r1.dir.z, 1e-5);

    try std.testing.expectApproxEqRel(-0.998817, r2.dir.x, 1e-5);
    try std.testing.expectApproxEqRel(-4.18732, r2.dir.y, 1e-5);
    try std.testing.expectApproxEqRel(-2.8115, r2.dir.z, 1e-5);
}
