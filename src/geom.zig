const std = @import("std");

pub const V3 = struct {
    v: [3]f64 = .{ 0, 0, 0 },

    pub fn init(x_: f64, y_: f64, z_: f64) V3 {
        return .{ .v = .{ x_, y_, z_ } };
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

pub const Sphere = struct {
    origin: V3,
    radius: f64,
};
