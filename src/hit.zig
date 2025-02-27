const vec = @import("./vec.zig");
const mat = @import("./material.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

pub const Hittable = struct {
    ptr: *const anyopaque,
    hit: *const fn (ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit,
};

pub const Hit = struct {
    point: V3,
    normal: V3,
    t: f64,
    front_face: bool,
    material: mat.Material,

    pub fn init(ray: *const Ray, point: V3, normal: V3, t: f64, material: mat.Material) Hit {
        // ray is hitting front if it points against normal dir, otherwise back face
        const front_face = normal.dot(ray.dir) < 0;
        return .{
            .point = point,
            .normal = if (front_face) normal else normal.mul(-1),
            .t = t,
            .front_face = front_face,
            .material = material,
        };
    }
};
