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

        // check quadratic formula discriminant for roots, if real roots then hit
        const offset = ray.origin.sub(self.center);

        const a = ray.dir.dot(ray.dir);
        const half_b = ray.dir.dot(offset);
        const c = offset.dot(offset) - self.radius * self.radius;

        const discriminant = half_b * half_b - a * c;
        if (discriminant < 0)
            return null;

        const t = (-half_b - @sqrt(discriminant)) / a;
        if (t < tmin or t > tmax)
            return null;

        const point = ray.at(t);
        const n = point.sub(self.center).unit();
        return Hit.init(ray, point, n, t, self.material);
    }
};
