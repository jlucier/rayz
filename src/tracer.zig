const V3 = @import("./geom.zig").V3;

pub const Hit = struct {
    point: V3,
    normal: V3,
    t: f64,
};

pub const Ray = struct {
    origin: V3,
    dir: V3,

    pub fn at(self: *const Ray, t: f64) V3 {
        return self.origin.add(self.dir.mul(t));
    }
};

pub const RayTracer = struct {};
