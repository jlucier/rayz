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
        random: std.Random,
        hit: *const Hit,
    ) ScatterResult {
        var target = switch (self.method) {
            .UNIT_SPHERE => hit.point.add(hit.normal).add(randomInUnitSphere(random)),
            .UNIT_SPHERE_SURFACE => hit.point.add(hit.normal).add(randomUnit(random)),
            .HEMISPHERE => hit.point.add(randomInHemisphere(random, hit.normal)),
        };
        // TODO add near zero detection
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

        const cos_theta = unit_dir.mul(-1).dot(hit.normal);
        // const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        var dir = V3{};
        // if (eta * sin_theta > 1.0) {
        //     dir = reflect(ray, hit);
        // } else {
        // refract
        // TODO this is clearly kinda busted
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
