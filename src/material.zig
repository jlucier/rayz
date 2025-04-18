const std = @import("std");
const vec = @import("./vec.zig");
const hitmod = @import("./hit.zig");
const ecs = @import("./ecs.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;

// Tex

pub const TextureValueParam = struct {
    u: f64,
    v: f64,
    point: V3,
    textures: []const Texture,
};

pub const SolidTexture = struct {
    color: V3,

    pub fn value(self: *const SolidTexture, _: TextureValueParam) V3 {
        return self.color;
    }
};

pub const CheckerTexture = struct {
    scale: f64,
    even: ecs.TextureHandle,
    odd: ecs.TextureHandle,

    pub fn value(self: *const CheckerTexture, args: TextureValueParam) V3 {
        const x: i64 = @intFromFloat(@floor(args.point.x / self.scale));
        const y: i64 = @intFromFloat(@floor(args.point.y / self.scale));
        const z: i64 = @intFromFloat(@floor(args.point.z / self.scale));
        const t = if (@mod(x + y + z, 2) == 0) &self.even else &self.odd;
        return t.get(args.textures).value(args);
    }
};

pub const Texture = union(enum) {
    checker: CheckerTexture,
    solid: SolidTexture,

    pub fn value(self: *const Texture, args: TextureValueParam) V3 {
        return switch (self.*) {
            .checker => self.checker.value(args),
            .solid => self.solid.value(args),
        };
    }
};

// Mat

pub const ScatterParam = struct {
    random: std.Random,
    ray: *const Ray,
    hit: *const Hit,
    textures: []const Texture,
};

pub const ScatterResult = struct {
    ray: Ray,
    attenuation: V3,
};

pub const DiffuseScatterMethod = enum {
    UNIT_SPHERE,
    UNIT_SPHERE_SURFACE,
    HEMISPHERE,
};

pub const DiffuseMaterial = struct {
    method: DiffuseScatterMethod = .HEMISPHERE,
    texture: ecs.TextureHandle,

    pub fn scatter(self: *const DiffuseMaterial, args: ScatterParam) ?ScatterResult {
        var target = switch (self.method) {
            .UNIT_SPHERE => args.hit.point.add(args.hit.normal).add(
                randomInUnitSphere(args.random),
            ),
            .UNIT_SPHERE_SURFACE => args.hit.point.add(args.hit.normal).add(randomUnit(args.random)),
            .HEMISPHERE => args.hit.point.add(randomInHemisphere(args.random, args.hit.normal)),
        };
        if (target.nearZero())
            target = args.hit.normal;

        return .{
            .ray = .{
                .origin = args.hit.point,
                .dir = target.sub(args.hit.point),
                .time = args.ray.time,
            },
            .attenuation = self.texture.get(args.textures).value(.{
                .u = args.hit.u,
                .v = args.hit.v,
                .point = args.hit.point,
                .textures = args.textures,
            }),
        };
    }
};

pub const MetallicMaterial = struct {
    fuzz: f64 = 0,
    texture: ecs.TextureHandle,

    pub fn scatter(self: *const MetallicMaterial, args: ScatterParam) ?ScatterResult {
        var reflection_dir = reflect(args.ray, args.hit).unit();
        if (self.fuzz > 0) {
            reflection_dir = reflection_dir.add(
                randomUnit(args.random).mul(@min(self.fuzz, 1)),
            );
        }

        if (reflection_dir.dot(args.hit.normal) <= 0)
            return null;
        return .{
            .ray = .{
                .origin = args.hit.point,
                .dir = reflection_dir,
                .time = args.ray.time,
            },
            .attenuation = self.texture.get(args.textures).value(.{
                .u = args.hit.u,
                .v = args.hit.v,
                .point = args.hit.point,
                .textures = args.textures,
            }),
        };
    }
};

pub const DielectricMaterial = struct {
    refractive_index: f64 = 1.0,

    pub fn scatter(self: *const DielectricMaterial, args: ScatterParam) ScatterResult {
        const eta = if (args.hit.front_face) 1 / self.refractive_index else self.refractive_index;
        const unit_dir = args.ray.dir.unit();

        const cos_theta = unit_dir.mul(-1).dot(args.hit.normal);
        const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        var dir = V3{};
        if (eta * sin_theta > 1.0 or reflectance(cos_theta, eta) > args.random.float(f64)) {
            dir = reflect(args.ray, args.hit);
        } else {
            // refract
            dir = refract(unit_dir, args.hit.normal, eta);
        }
        return .{
            .ray = .{
                .origin = args.hit.point,
                .dir = dir,
                .time = args.ray.time,
            },
            .attenuation = V3.ones(),
        };
    }
};

pub const Material = union(enum) {
    diffuse: DiffuseMaterial,
    metallic: MetallicMaterial,
    dielectric: DielectricMaterial,

    pub fn scatter(
        self: *const Material,
        args: ScatterParam,
    ) ?ScatterResult {
        return switch (self.*) {
            .diffuse => self.diffuse.scatter(args),
            .metallic => self.metallic.scatter(args),
            .dielectric => self.dielectric.scatter(args),
        };
    }
};

fn reflectance(cos: f64, ri: f64) f64 {
    var r0 = (1 - ri) / (1 + ri);
    r0 *= r0;
    return r0 + (1 - r0) * std.math.pow(f64, 1 - cos, 5);
}

fn reflect(ray: *const Ray, hit: *const Hit) V3 {
    return ray.dir.sub(hit.normal.mul(2 * ray.dir.dot(hit.normal)));
}

fn refract(unit_dir: V3, norm: V3, eta: f64) V3 {
    const cos_theta = unit_dir.mul(-1).dot(norm);
    const perp_comp = norm.mul(cos_theta).add(unit_dir).mul(eta);
    const parallel_comp = norm.mul(-@sqrt(1 - perp_comp.dot(perp_comp)));
    return perp_comp.add(parallel_comp);
}

fn randomInUnitSphere(random: std.Random) V3 {
    while (true) {
        const v = V3.random(random, -1, 1);
        if (v.mag() <= 1)
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
        (V3{ .x = -0.3125, .y = -0.3125, .z = -1 }).unit(),
        V3{ .x = -0.558127, .y = -0.558127, .z = 0.613994 },
        1.0 / 1.5,
    );

    try std.testing.expectApproxEqRel(0.144881, a.x, 0.0001);
    try std.testing.expectApproxEqRel(0.144881, a.y, 0.0001);
    try std.testing.expectApproxEqRel(-0.978784, a.z, 0.0001);
}
