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

    var spheres = std.ArrayList(Sphere).init(allocator);

    // ground
    try spheres.append(Sphere.stationary(
        .{ .x = 0, .y = -1000, .z = 0 },
        1000,
        .{
            .mat_type = .Diffuse,
            .albedo = V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
        },
    ));

    // main 3
    try spheres.append(Sphere.stationary(
        .{ .x = 0, .y = 1, .z = 0 },
        1.0,
        .{
            .mat_type = .Dielectric,
            .refractive_index = 1.5,
        },
    ));
    try spheres.append(Sphere.stationary(
        .{ .x = -4, .y = 1, .z = 0 },
        1.0,
        .{
            .mat_type = .Diffuse,
            .albedo = V3{ .x = 0.4, .y = 0.2, .z = 0.1 },
        },
    ));
    try spheres.append(Sphere.stationary(
        .{ .x = 4, .y = 1, .z = 0 },
        1.0,
        .{
            .mat_type = .Metallic,
            .albedo = V3{ .x = 0.7, .y = 0.6, .z = 0.5 },
        },
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
                m.albedo = V3.random(rand, 0, 1.0).vmul(V3.random(rand, 0, 1.0));
                // moving from center up in y by [0,0.5] over the time window
                sphere_ray.dir = V3.y_hat().mul(rand.float(f64) * 0.5);
            } else if (rand_mat < 0.95) {
                m.mat_type = .Metallic;
                m.albedo = V3.random(rand, 0.5, 1.0);
                m.fuzz = rand.float(f64) * 0.5;
            } else {
                // glass
                m.mat_type = .Dielectric;
                m.refractive_index = 1.5;
            }

            try spheres.append(.{ .center = sphere_ray, .radius = 0.2, .material = m });
        }
    }

    for (spheres.items) |*s| {
        try tracer.addObject(.{
            .ptr = s,
            .hit = geom.Sphere.hit,
            .bbox = s.boundingBox(),
        });
    }

    try tracer.bvh.print(0);

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

pub fn penultimate_scene(allocator: std.mem.Allocator, img_w: usize) void {
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

    const spheres = [_]geom.Sphere{
        .{
            .center = V3{ .x = 0, .y = 0, .z = -1.2 },
            .radius = 0.5,
            .material = .{
                .mat_type = .Diffuse,
                .albedo = V3{ .x = 0.1, .y = 0.2, .z = 0.5 },
            },
        },
        .{
            .center = V3{ .x = 0, .y = -100.5, .z = -1 },
            .radius = 100,
            .material = .{
                .mat_type = .Diffuse,
                .albedo = V3{ .x = 0.8, .y = 0.8, .z = 0.0 },
            },
        },
        // left outer
        .{
            .center = V3{ .x = -1, .y = 0, .z = -1 },
            .radius = 0.5,
            .material = .{
                .mat_type = .Dielectric,
                .refractive_index = 1.5,
            },
        },
        // left inner bubble
        .{
            .center = V3{ .x = -1, .y = 0, .z = -1 },
            .radius = 0.4,
            .material = .{
                .mat_type = .Dielectric,
                .refractive_index = 1.0 / 1.5,
            },
        },
        .{
            .center = V3{ .x = 1, .y = 0, .z = -1 },
            .radius = 0.5,
            .material = .{
                .mat_type = .Metallic,
                .albedo = V3{ .x = 0.8, .y = 0.6, .z = 0.2 },
                .fuzz = 1.0,
            },
        },
    };

    for (&spheres) |*s| {
        try tracer.addObject(.{ .ptr = s, .hit = geom.Sphere.hit });
    }
}
