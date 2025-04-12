const std = @import("std");
const renderer = @import("./renderer.zig");
const vec = @import("./vec.zig");
const geom = @import("./geom.zig");
const mat = @import("./material.zig");

const Tracer = renderer.Tracer;
const V3 = vec.V3;
const Sphere = geom.Sphere;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const img_w = try std.fmt.parseUnsigned(usize, args.next().?, 10);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tracer = try randomBouncing(allocator, img_w);

    const st = try std.time.Instant.now();

    const rays_traced: f64 = @floatFromInt(try tracer.render());

    var durr: f64 = @floatFromInt(std.time.Instant.since(try std.time.Instant.now(), st));
    durr /= std.time.ns_per_s;
    std.debug.print("Finished render ({d:.2}s): {d:.2} rps and {d:.2} us per ray\n", .{
        durr,
        rays_traced / durr,
        std.time.us_per_s * durr / rays_traced,
    });

    if (args.next()) |out_fname| {
        const f = try std.fs.cwd().createFile(out_fname, .{ .read = false, .truncate = true });
        defer f.close();
        try tracer.img.writePPM(f);
    } else {
        try tracer.img.writePPM(std.io.getStdOut());
    }
}

fn randomBouncing(allocator: std.mem.Allocator, img_w: usize) !Tracer {
    var tracer = try Tracer.init(
        allocator,
        img_w,
        20.0, // vfov
        10.0, // focal dist
        0.6, // defocus angle
        V3{ .x = 13, .y = 2, .z = 3 }, // look_from
        V3{}, // look_at
        V3.y_hat(), // vup
    );
    // ground
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = -1000, .z = 0 },
        1000,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Diffuse },
            .{ .tex_type = .SOLID, .color = V3{ .x = 0.5, .y = 0.5, .z = 0.5 } },
        ),
    ));

    // main 3
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.add(mat.Material{
            .mat_type = .Dielectric,
            .refractive_index = 1.5,
        }),
    ));
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = -4, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Diffuse },
            .{ .tex_type = .SOLID, .color = V3{ .x = 0.4, .y = 0.2, .z = 0.1 } },
        ),
    ));
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 4, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Metallic },
            .{ .tex_type = .SOLID, .color = V3{ .x = 0.7, .y = 0.6, .z = 0.5 } },
        ),
    ));

    // randoms

    var a: isize = -11;
    const rand = tracer.rng.random();
    while (a < 11) : (a += 1) {
        var b: isize = -11;
        while (b < 11) : (b += 1) {
            const rand_mat = rand.float(f64);

            const fa: f64 = @floatFromInt(a);
            const fb: f64 = @floatFromInt(b);
            const center = V3{
                .x = fa + 0.9 * rand.float(f64),
                .y = 0.2,
                .z = fb + 0.9 * rand.float(f64),
            };

            if (center.sub(V3{ .x = 4, .y = 0.2, .z = 0 }).mag() <= 0.9)
                continue;

            var sphere_ray = vec.Ray{
                .origin = center,
                .dir = V3{},
            };
            var m = mat.Material{
                .mat_type = .Dielectric,
            };

            if (rand_mat < 0.8) {
                m.mat_type = .Diffuse;
                m.texture = try tracer.pool.add(mat.Texture{
                    .tex_type = .SOLID,
                    .color = V3.random(rand, 0, 1.0).vmul(V3.random(rand, 0, 1.0)),
                });
                // moving from center up in y by [0,0.5] over the time window
                sphere_ray.dir = V3.y_hat().mul(rand.float(f64) * 0.5);
            } else if (rand_mat < 0.95) {
                m.mat_type = .Metallic;
                m.texture = try tracer.pool.add(mat.Texture{
                    .tex_type = .SOLID,
                    .color = V3.random(rand, 0.5, 1.0),
                });
                m.fuzz = rand.float(f64) * 0.5;
            } else {
                // glass
                m.mat_type = .Dielectric;
                m.refractive_index = 1.5;
            }

            _ = try tracer.pool.add(Sphere{
                .center = sphere_ray,
                .radius = 0.2,
                .material = try tracer.pool.add(m),
            });
        }
    }
    return tracer;
}

pub fn penultimateScene(allocator: std.mem.Allocator, img_w: usize) !Tracer {
    var tracer = try Tracer.init(
        allocator,
        img_w,
        20.0, // vfov
        3.4, // focal dist
        10.0, // defocus angle
        V3{ .x = -2, .y = 2, .z = 1 }, // look_from
        V3{ .x = 0, .y = 0, .z = -1 }, // look_at
        V3.y_hat(), // vup
    );

    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = 0, .z = -1.2 },
        0.5,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Diffuse },
            .{ .tex_type = .SOLID, .color = .{ .x = 0.1, .y = 0.2, .z = 0.5 } },
        ),
    ));
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = -100.5, .z = -1 },
        100,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Diffuse },
            .{ .tex_type = .SOLID, .color = .{ .x = 0.8, .y = 0.8, .z = 0.0 } },
        ),
    ));

    // left outer
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = -1, .y = 0, .z = -1 },
        0.5,
        try tracer.pool.add(mat.Material{
            .mat_type = .Dielectric,
            .refractive_index = 1.5,
        }),
    ));

    // left inner bubble
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = -1, .y = 0, .z = -1 },
        0.4,
        try tracer.pool.add(mat.Material{
            .mat_type = .Dielectric,
            .refractive_index = 1.0 / 1.5,
        }),
    ));

    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 1, .y = 0, .z = -1 },
        0.5,
        try tracer.pool.addMaterialWithTexture(
            .{ .mat_type = .Metallic, .fuzz = 1.0 },
            .{
                .tex_type = .SOLID,
                .color = .{ .x = 0.8, .y = 0.6, .z = 0.2 },
            },
        ),
    ));
    return tracer;
}
