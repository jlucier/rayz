const std = @import("std");
const vec = @import("./vec.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

const DEG_TO_RAD = std.math.pi / 180.0;

pub const Camera = struct {
    lookFrom: V3,
    pxDu: V3,
    pxDv: V3,
    pxOrigin: V3,
    defocusU: V3,
    defocusV: V3,
    defocus: bool,

    pub fn init(
        vfov: f64,
        focusDist: f64,
        defocusAngle: f64,
        lookFrom: V3,
        lookAt: V3,
        vup: V3,
        imgHeight: usize,
        imgWidth: usize,
    ) Camera {
        const fimg_h: f64 = @floatFromInt(imgHeight);
        const fimg_w: f64 = @floatFromInt(imgWidth);

        const vp_height = 2 * std.math.tan(vfov * DEG_TO_RAD / 2.0) * focusDist;
        const vp_width = vp_height * fimg_w / fimg_h;

        const w = lookFrom.sub(lookAt).unit();
        const u = vup.cross(w).unit();
        const v = w.cross(u);

        const vp_u = u.mul(vp_width);
        const vp_v = v.mul(-vp_height);
        const px_du = vp_u.div(fimg_w);
        const px_dv = vp_v.div(fimg_h);
        const defocus_radius = std.math.tan(defocusAngle * DEG_TO_RAD / 2) * focusDist;

        const vp_origin = lookFrom.sub(w.mul(focusDist)).sub(vp_u.div(2)).sub(
            vp_v.div(2),
        ).add(px_du.add(px_dv).mul(0.5));

        return .{
            .lookFrom = lookFrom,
            .pxDu = px_du,
            .pxDv = px_dv,
            .pxOrigin = vp_origin,
            .defocusU = u.mul(defocus_radius),
            .defocusV = v.mul(defocus_radius),
            .defocus = defocusAngle > 0,
        };
    }

    pub fn getRay(self: *const Camera, px: usize, py: usize, rng: ?std.Random) Ray {
        var x: f64 = @floatFromInt(px);
        var y: f64 = @floatFromInt(py);
        var origin = self.lookFrom;
        if (rng) |r| {
            x += r.float(f64) - 0.5;
            y += r.float(f64) - 0.5;

            origin = origin.add(self.randomInDefocus(r));
        }

        return Ray.init(
            origin,
            self.pxDu.mul(x).add(self.pxDv.mul(y)).add(
                self.pxOrigin,
            ).sub(origin), // dir
            if (rng) |r| r.float(f64) else 0,
        );
    }

    fn randomInDefocus(self: *const Camera, rng: std.Random) V3 {
        if (!self.defocus) {
            return .{};
        }

        while (true) {
            const v = V3{ .x = rng.float(f64) * 2 - 1, .y = rng.float(f64) * 2 - 1, .z = 0 };
            if (v.dot(v) <= 1) {
                return self.defocusU.mul(v.x).add(self.defocusV.mul(v.y));
            }
        }
    }
};




