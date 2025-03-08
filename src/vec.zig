const std = @import("std");
const utils = @import("./utils.zig");

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

    pub fn of(v: f64) V3 {
        return .{ .v = .{ v, v, v } };
    }

    pub fn ones() V3 {
        return V3.of(1);
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

    pub fn vecMul(self: *const V3, o: V3) V3 {
        return .{ .v = .{ self.x() * o.x(), self.y() * o.y(), self.z() * o.z() } };
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

    pub fn nearZero(self: *const V3) bool {
        const tol = 1e-8;
        return @abs(self.x()) <= tol and @abs(self.y()) <= tol and @abs(self.z()) <= tol;
    }
};

pub const Ray = struct {
    origin: V3,
    dir: V3,

    pub fn at(self: *const Ray, t: f64) V3 {
        return self.origin.add(self.dir.mul(t));
    }
};

test "v3 add" {
    const a = V3.init(0, 0, 1);
    const b = V3.init(-1, 1, 0);
    const c = a.add(b);

    try std.testing.expectEqual(1, a.mag());

    try std.testing.expectEqual(-1, c.x());
    try std.testing.expectEqual(1, c.y());
    try std.testing.expectEqual(1, c.z());
}

test "v3 mul" {
    const a = V3.init(-1, 1, 0);
    const b = a.mul(-2.5);

    try std.testing.expectEqual(2.5, b.x());
    try std.testing.expectEqual(-2.5, b.y());
    try std.testing.expectEqual(0, b.z());
}

test "v3 dot+mag+unit" {
    const a = V3.init(0, 1, 0);
    const b = V3.init(1, 0, 0);

    try std.testing.expectEqual(0, a.dot(b));
    try std.testing.expectEqual(1, a.dot(a));
    try std.testing.expectEqual(2, a.mul(2).dot(a));
    try std.testing.expectEqual(0.5, a.dot(V3.init(0.5, 0.5, 1)));

    const c = V3.init(4.5, -1.2, 3.3);

    try std.testing.expectEqual(32.58, c.dot(c));
    try std.testing.expectApproxEqRel(5.7078, c.mag(), 0.0001);
    try std.testing.expectApproxEqRel(1, c.unit().mag(), 0.0001);
    try std.testing.expectApproxEqRel(1, a.add(b).unit().mag(), 0.0001);
}
