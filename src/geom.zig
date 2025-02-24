const std = @import("std");
const utils = @import("utils.zig");

pub const V3 = struct {
    v: [3]f64 = .{ 0, 0, 0 },

    pub fn init(x_: f64, y_: f64, z_: f64) V3 {
        return .{ .v = .{ x_, y_, z_ } };
    }

    pub fn random(rng: std.Random, low: f64, high: f64) V3 {
        const scale = high - low;
        return V3.init(
            rng.float(f64) * scale + low,
            rng.float(f64) * scale + low,
            rng.float(f64) * scale + low,
        );
    }

    pub fn randomInUnitSphere(rng: std.Random) V3 {
        while (true) {
            const v = V3.random(rng, 0, 1);
            if (v.mag() < 1)
                return v;
        }
    }

    pub fn ones() V3 {
        return .{ .v = .{ 1, 1, 1 } };
    }

    pub fn x(self: *const V3) f64 {
        return self.v[0];
    }

    pub fn y(self: *const V3) f64 {
        return self.v[1];
    }

    pub fn z(self: *const V3) f64 {
        return self.v[2];
    }

    pub fn add(self: *const V3, o: V3) V3 {
        return .{ .v = .{
            self.x() + o.x(),
            self.y() + o.y(),
            self.z() + o.z(),
        } };
    }

    pub fn sub(self: *const V3, o: V3) V3 {
        return .{ .v = .{
            self.x() - o.x(),
            self.y() - o.y(),
            self.z() - o.z(),
        } };
    }

    pub fn mul(self: *const V3, v: f64) V3 {
        return .{ .v = .{ self.x() * v, self.y() * v, self.z() * v } };
    }
    pub fn div(self: *const V3, v: f64) V3 {
        return self.mul(1 / v);
    }

    pub fn mag(self: *const V3) f64 {
        return @sqrt(self.dot(self.*));
    }

    pub fn unit(self: *const V3) V3 {
        return self.div(self.mag());
    }

    pub fn clamp(self: *const V3, low: f64, high: f64) V3 {
        return V3.init(
            utils.clamp(f64, self.x(), low, high),
            utils.clamp(f64, self.y(), low, high),
            utils.clamp(f64, self.z(), low, high),
        );
    }

    pub fn dot(self: *const V3, o: V3) f64 {
        return self.x() * o.x() + self.y() * o.y() + self.z() * o.z();
    }

    pub fn cross(self: *const V3, o: V3) V3 {
        return .{ .v = .{
            self.y() * o.z() - self.z() * o.y(),
            self.z() * o.x() - self.x() * o.z(),
            self.x() * o.y() - self.y() * o.x(),
        } };
    }
};

pub const Ray = struct {
    origin: V3,
    dir: V3,

    pub fn at(self: *const Ray, t: f64) V3 {
        return self.origin.add(self.dir.mul(t));
    }
};

pub const Hit = struct {
    point: V3,
    normal: V3,
    t: f64,
    front_face: bool,

    pub fn init(ray: *const Ray, point: V3, normal: V3, t: f64) Hit {
        // normal is hitting front if it points against ray dir, otherwise back face
        const front_face = normal.dot(ray.dir) < 0;
        return .{
            .point = point,
            .normal = if (front_face) normal else normal.mul(-1),
            .t = t,
            .front_face = front_face,
        };
    }
};

pub const Sphere = struct {
    center: V3,
    radius: f64,

    pub fn hit(ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit {
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
        return Hit.init(ray, point, n, t);
    }
};
