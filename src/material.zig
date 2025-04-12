const std = @import("std");
const vec = @import("./vec.zig");
const hitmod = @import("./hit.zig");

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;

// Tex

pub const TextureValueParam = struct {
    u: f64,
    v: f64,
    point: V3,
};

pub const Texture = struct {
    ptr: *const anyopaque,
    valueFn: *const fn (ptr: *const anyopaque, args: TextureValueParam) V3,

    pub fn init(allocator: std.mem.Allocator, obj: anytype) !Texture {
        const ptr = try allocator.create(@TypeOf(obj));
        ptr.* = obj;
        return .{
            .ptr = ptr,
            .valueFn = @TypeOf(obj).value,
        };
    }

    pub fn value(self: *const Texture, args: TextureValueParam) V3 {
        return self.valueFn(self.ptr, args);
    }
};

pub const SolidTexture = struct {
    color: V3,

    pub fn value(ptr: *const anyopaque, _: TextureValueParam) V3 {
        const self: *const SolidTexture = @ptrCast(@alignCast(ptr));
        return self.color;
    }
};

pub const CheckerTexture = struct {
    scale: f64,
    even: Texture,
    odd: Texture,

    pub fn value(ptr: *const anyopaque, args: TextureValueParam) V3 {
        const self: *const CheckerTexture = @ptrCast(@alignCast(ptr));
        const x: i64 = @intFromFloat(@floor(args.point.x / self.scale));
        const y: i64 = @intFromFloat(@floor(args.point.y / self.scale));
        const z: i64 = @intFromFloat(@floor(args.point.z / self.scale));
        const t = if (@mod(x + y + z, 2) == 0) &self.even else &self.odd;
        return t.value(args);
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
    // diffuse only
    method: DiffuseScatterMethod = .HEMISPHERE,
    // metallic only
    fuzz: f64 = 0,
    // dielectric only
    refractive_index: f64 = 1.0,
    // metallic + diffuse
    texture: usize = 0,

    pub fn scatter(
        self: *const Material,
        args: ScatterParam,
    ) ?ScatterResult {
        return switch (self.mat_type) {
            .Diffuse => self.scatterDiffuse(args),
            .Metallic => self.scatterMetallic(args),
            .Dielectric => self.scatterDielectric(args),
        };
    }

    pub fn scatterDiffuse(self: *const Material, args: ScatterParam) ScatterResult {
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
            .attenuation = self.attenuation(args),
        };
    }

    pub fn scatterMetallic(self: *const Material, args: ScatterParam) ?ScatterResult {
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
            .attenuation = self.attenuation(args),
        };
    }
    pub fn scatterDielectric(self: *const Material, args: ScatterParam) ?ScatterResult {
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

    fn attenuation(self: *const Material, args: ScatterParam) V3 {
        return args.textures[self.texture].value(.{
            .u = args.hit.u,
            .v = args.hit.v,
            .point = args.hit.point,
        });
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
