const std = @import("std");
const vec = @import("./vec.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

const DEG_TO_RAD = std.math.pi / 180.0;

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
