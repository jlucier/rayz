const std = @import("std");
const vec = @import("./vec.zig");
const hitmod = @import("./hit.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;

pub const ScatterResult = struct {
    ray: Ray,
    attenuation: V3,
};

pub const MaterialType = enum {
    Diffuse,
    Metallic,
    Dielectric,
};

pub const DiffuseScatterMethod = enum {
    UNIT_SPHERE,
    UNIT_SPHERE_SURFACE,
    HEMISPHERE,
};

pub const Material = struct {
    mat_type: MaterialType,

    // metallic + diffuse
    albedo: V3 = V3.of(0.5),
    // diffuse only
    method: DiffuseScatterMethod = .HEMISPHERE,
    // metallic only
    fuzz: f64 = 0,
    // dielectric only
    refractive_index: f64 = 1.0,

    pub fn scatter(
        self: *const Material,
        random: std.Random,
        ray: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult {
        return switch (self.mat_type) {
            .Diffuse => self.scatterDiffuse(random, hit),
            .Metallic => self.scatterMetallic(random, ray, hit),
            .Dielectric => self.scatterDielectric(ray, hit),
        };
    }

    pub fn scatterDiffuse(
        self: *const Material,
        _: std.Random,
        hit: *const Hit,
    ) ScatterResult {
        // var target = switch (self.method) {
        //     .UNIT_SPHERE => hit.point.add(hit.normal).add(randomInUnitSphere(random)),
        //     .UNIT_SPHERE_SURFACE => hit.point.add(hit.normal).add(randomUnit(random)),
        //     .HEMISPHERE => hit.point.add(randomInHemisphere(random, hit.normal)),
        // };
        // if (target.nearZero())
        //     target = hit.normal;

        const target = hit.normal;
        return .{
            .ray = .{ .origin = hit.point, .dir = target.sub(hit.point) },
            .attenuation = self.albedo,
        };
    }

    pub fn scatterMetallic(
        self: *const Material,
        random: std.Random,
        ray: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult {
        const reflection_dir = reflect(ray, hit);
        if (reflection_dir.dot(hit.normal) <= 0)
            return null;
        return .{
            .ray = .{
                .origin = hit.point,
                .dir = if (self.fuzz <= 0) reflection_dir else //
                reflection_dir.add(randomInUnitSphere(random).mul(@max(self.fuzz, 1))),
            },
            .attenuation = self.albedo,
        };
    }
    pub fn scatterDielectric(
        self: *const Material,
        ray: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult {
        const eta = if (hit.front_face) 1 / self.refractive_index else self.refractive_index;
        const unit_dir = ray.dir.unit();

        // std.debug.print("hit: {}\nray: {}\n\n", .{ hit.point, ray.dir });
        const cos_theta = unit_dir.mul(-1).dot(hit.normal);
        // const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        var dir = V3{};
        // if (eta * sin_theta > 1.0) {
        //     dir = reflect(ray, hit);
        // } else {
        // refract
        const perp_comp = hit.normal.mul(cos_theta).add(unit_dir).mul(eta);
        const parallel_comp = hit.normal.mul(-@sqrt(1 - perp_comp.dot(perp_comp)));
        dir = perp_comp.add(parallel_comp);
        // }
        return .{
            .ray = .{
                .origin = hit.point,
                .dir = dir,
            },
            .attenuation = V3.ones(),
        };
    }
};

fn reflect(ray: *const Ray, hit: *const Hit) V3 {
    return ray.dir.sub(hit.normal.mul(2 * ray.dir.dot(hit.normal)));
}

fn refract(ray_dir: V3, norm: V3, eta: f64) V3 {
    const unit_dir = ray_dir.unit();
    const cos_theta = unit_dir.mul(-1).dot(norm);
    const perp_comp = norm.mul(cos_theta).add(unit_dir).mul(eta);
    const parallel_comp = norm.mul(-@sqrt(1 - perp_comp.dot(perp_comp)));
    // std.debug.print("ud: {}\n-ud: {}\ncos: {d}\nperp: {}\nparallel: {}\n", .{
    //     unit_dir,
    //     norm,
    //     cos_theta,
    //     perp_comp,
    //     parallel_comp,
    // });
    return perp_comp.add(parallel_comp);
}

fn randomInUnitSphere(random: std.Random) V3 {
    while (true) {
        const v = V3.random(random, -1, 1);
        if (v.mag() < 1)
            return v;
    }
}

fn randomUnit(random: std.Random) V3 {
    return randomInUnitSphere(random).unit();
}

fn randomInHemisphere(random: std.Random, norm: V3) V3 {
    const r = randomInUnitSphere(random);
    return if (r.dot(norm) > 0) r else r.mul(-1);
}

test "refract" {
    const a = refract(
        V3.init(-0.3125, -0.3125, -1),
        V3.init(-0.558127, -0.558127, 0.613994),
        1.0 / 1.5,
    );

    // cos: 0.242536
    // perp: {-0.280798, -0.280798, -0.510496}
    // parllel: {0.425679, 0.425679, -0.468289}

    try std.testing.expectApproxEqRel(0.144881, a.x(), 0.0001);
    try std.testing.expectApproxEqRel(0.144881, a.y(), 0.0001);
    try std.testing.expectApproxEqRel(-0.978784, a.z(), 0.0001);

    // hit: {0.168564, -0.168564, -1.63951}
    // ray: {-0.144881, 0.144881, -0.978784}
    // res: {-0.521243, 0.521243, -0.67573}

}
