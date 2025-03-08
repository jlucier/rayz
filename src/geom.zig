const std = @import("std");
const vec = @import("./vec.zig");
const hit = @import("./hit.zig");
const mat = @import("./material.zig");

const Hit = hit.Hit;

pub const Sphere = struct {
    center: vec.V3,
    radius: f64,
    material: mat.Material,

    pub fn hit(ptr: *const anyopaque, ray: *const vec.Ray, tmin: f64, tmax: f64) ?Hit {
        const self: *const Sphere = @ptrCast(@alignCast(ptr));
        return self.hitInner(ray, tmin, tmax);
    }

    fn hitInner(self: *const Sphere, ray: *const vec.Ray, tmin: f64, tmax: f64) ?Hit {
        // check quadratic formula discriminant for roots, if real roots then hit
        const offset = self.center.sub(ray.origin);

        const a = ray.dir.dot(ray.dir);
        const half_b = ray.dir.dot(offset);
        const c = offset.dot(offset) - self.radius * self.radius;

        const discriminant = half_b * half_b - a * c;
        const t1 = (half_b - @sqrt(discriminant)) / a;
        const t2 = (half_b + @sqrt(discriminant)) / a;

        std.debug.print("offset: {}\na: {d}\nh: {d}\nc: {d}\ndisc: {d}\nt: {d}\n", .{
            offset,
            a,
            half_b,
            c,
            discriminant,
            t1,
        });
        if (discriminant < 0)
            return null;

        const t: ?f64 = if (t1 >= tmin and t1 <= tmax) t1 //
            else if (t2 >= tmin and t2 <= tmax) t2 //
            else null;

        if (t == null)
            return null;

        const point = ray.at(t.?);
        const n = point.sub(self.center).unit();
        return Hit.init(ray, point, n, t.?, self.material);
    }
};
