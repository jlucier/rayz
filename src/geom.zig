const std = @import("std");
const vec = @import("./vec.zig");
const hit = @import("./hit.zig");
const mat = @import("./material.zig");

const Hit = hit.Hit;

pub const Sphere = struct {
    center: vec.Ray,
    radius: f64,
    material: mat.Material,

    pub fn hit(ptr: *const anyopaque, ray: *const vec.Ray, tmin: f64, tmax: f64) ?Hit {
        const self: *const Sphere = @ptrCast(@alignCast(ptr));
        return self.hitInner(ray, tmin, tmax);
    }

    fn hitInner(self: *const Sphere, ray: *const vec.Ray, tmin: f64, tmax: f64) ?Hit {
        // check quadratic formula discriminant for roots, if real roots then hit
        const origin_now = self.center.at(ray.time);
        const offset = origin_now.sub(ray.origin);

        const a = ray.dir.dot(ray.dir);
        const half_b = ray.dir.dot(offset);
        const c = offset.dot(offset) - self.radius * self.radius;

        const discriminant = half_b * half_b - a * c;

        if (discriminant < 0)
            return null;

        const rt = @sqrt(discriminant);
        const t1 = (half_b - rt) / a;
        const t2 = (half_b + rt) / a;

        const t: ?f64 = if (t1 >= tmin and t1 <= tmax) t1 //
            else if (t2 >= tmin and t2 <= tmax) t2 //
            else null;

        if (t == null)
            return null;

        const point = ray.at(t.?);
        const n = point.sub(origin_now).unit();
        return Hit.init(ray, point, n, t.?, self.material);
    }
};
