const std = @import("std");

pub const V3 = struct {
    v: [3]f64 = .{ 0, 0, 0 },

    pub fn init(x_: f64, y_: f64, z_: f64) V3 {
        return .{ .v = .{ x_, y_, z_ } };
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

    pub fn add(self: *const V3, o: *const V3) V3 {
        return .{ .v = .{
            self.x() + o.x(),
            self.y() + o.y(),
            self.z() + o.z(),
        } };
    }

    pub fn mag(self: *const V3) f64 {
        return @sqrt(self.x() * self.x() +
            self.y() * self.y() +
            self.z() * self.z());
    }
};

pub const Ray = struct {
    origin: V3,
    dir: V3,
};
