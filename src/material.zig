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

pub const Material = struct {
    ptr: *const anyopaque,
    scatter: *const fn (
        ptr: *const anyopaque,
        random: std.Random,
        ray: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult,
};

pub const Diffuse = struct {
    pub const ScatterMethod = enum {
        UNIT_SPHERE,
        UNIT_SPHERE_SURFACE,
        HEMISPHERE,
    };

    albedo: V3 = V3.of(0.5),
    method: ScatterMethod = .HEMISPHERE,

    pub fn scatter(
        ptr: *const anyopaque,
        random: std.Random,
        _: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult {
        const self: *const Diffuse = @ptrCast(@alignCast(ptr));
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
};

pub const Metallic = struct {
    albedo: V3 = V3.of(0.8),
    pub fn scatter(
        ptr: *const anyopaque,
        _: std.Random,
        ray: *const Ray,
        hit: *const Hit,
    ) ?ScatterResult {
        const self: *const Metallic = @ptrCast(@alignCast(ptr));
        const reflection_dir = ray.dir.sub(hit.normal.mul(2 * ray.dir.dot(hit.normal)));
        if (reflection_dir.dot(hit.normal) <= 0)
            return null;
        return .{
            .ray = .{ .origin = hit.point, .dir = reflection_dir },
            .attenuation = self.albedo,
        };
    }
};
