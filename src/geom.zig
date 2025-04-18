const std = @import("std");
const vec = @import("./vec.zig");
const hit = @import("./hit.zig");
const ecs = @import("./ecs.zig");

const AABB = hit.AABB;
const Hit = hit.Hit;
const V3 = vec.V3;
const Ray = vec.Ray;

pub const Sphere = struct {
    center: Ray,
    radius: f64,
    material: ecs.MaterialHandle,

    pub fn stationary(center: V3, radius: f64, material: ecs.MaterialHandle) Sphere {
        return .{
            .center = .{ .origin = center, .dir = .{} },
            .radius = radius,
            .material = material,
        };
    }

    pub fn boundingBox(self: *const Sphere) AABB {
        const rad = V3.of(self.radius);
        const o1 = self.center.origin;
        const o2 = self.center.at(1);
        const b1 = AABB.init(o1.sub(rad), o1.add(rad));
        const b2 = AABB.init(o2.sub(rad), o2.add(rad));
        return AABB.enclose(b1, b2);
    }

    pub fn hit(ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit {
        const self: *const Sphere = @ptrCast(@alignCast(ptr));
        return self.hitInner(ray, tmin, tmax);
    }

    fn hitInner(self: *const Sphere, ray: *const Ray, tmin: f64, tmax: f64) ?Hit {
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

test "sphere bbox" {
    const stat = Sphere.stationary(.{}, 1, .{ .idx = 0 });
    const s_bbox = stat.boundingBox();
    try std.testing.expect(s_bbox.low.close(V3.of(-1)));
    try std.testing.expect(s_bbox.high.close(V3.ones()));

    const move = Sphere{
        .center = .{ .origin = .{}, .dir = V3.ones() },
        .radius = 1,
        .material = .{ .idx = 0 },
    };

    const m_bbox = move.boundingBox();
    try std.testing.expect(m_bbox.low.close(V3.of(-1)));
    try std.testing.expect(m_bbox.high.close(V3.of(2)));
}
