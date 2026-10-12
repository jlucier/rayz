const std = @import("std");
const renderer = @import("./renderer.zig");
const vec = @import("./vec.zig");
const geom = @import("./geom.zig");
const mat = @import("./material.zig");
const ecs = @import("./ecs.zig");

const Tracer = renderer.Tracer;
const V3 = vec.V3;
const Sphere = geom.Sphere;

const Params = struct {
    img_w: usize = 0,
    seed: u64 = 0,
    samples: usize = 10,
    scene: u8 = 0,
    out_file: ?[]const u8 = null,
};

fn processArgs(io: std.Io, args: []const []const u8) !Params {
    var params = Params{};

    const named_args: [3][]const u8 = .{
        "--seed=",
        "--samples=",
        "--scene=",
    };

    outer: for (args[1..]) |a| {
        for (named_args, 0..) |prefix, i| {
            if (a.len >= prefix.len and std.mem.eql(u8, prefix, a[0..prefix.len])) {
                const part = a[prefix.len..];
                switch (i) {
                    0 => {
                        params.seed = try std.fmt.parseUnsigned(u64, part, 10);
                    },
                    1 => {
                        params.samples = try std.fmt.parseUnsigned(usize, part, 10);
                    },
                    2 => {
                        params.scene = try std.fmt.parseUnsigned(u8, part, 10);
                    },
                    else => unreachable,
                }
                continue :outer;
            }
        }

        // positional = img_w or file
        if (std.fmt.parseUnsigned(usize, a, 10)) |v| {
            params.img_w = v;
        } else |_| {
            params.out_file = a;
        }
    }

    if (params.seed == 0) {
        // initialize seed randomly
        io.random(std.mem.asBytes(&params.seed));
    }

    return params;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const params = try processArgs(init.io, args);

    var tracer = switch (params.scene) {
        0 => try randomBouncing(init.io, arena, &params),
        1 => try penultimateScene(init.io, arena, &params),
        2 => try checkeredSpheres(init.io, arena, &params),
        else => unreachable,
    };

    const st = std.Io.Clock.Timestamp.now(init.io, .awake);

    const rays_traced: f64 = @floatFromInt(try tracer.render());

    var durr: f64 = @floatFromInt(st.untilNow(init.io).raw.toNanoseconds());
    durr /= std.time.ns_per_s;

    std.debug.print("Finished render ({d:.2}s): {d:.2} rps and {d:.2} us per ray\n", .{
        durr,
        rays_traced / durr,
        std.time.us_per_s * durr / rays_traced,
    });

    var buf: [1024]u8 = undefined;
    var opt_f: ?std.Io.File = null;
    defer if (opt_f) |f| f.close(init.io);

    var w: std.Io.File.Writer = if (params.out_file) |out_fname| blk: {
        opt_f = try std.Io.Dir.cwd().createFile(init.io, out_fname, .{ .read = false, .truncate = true });
        break :blk opt_f.?.writer(init.io, &buf);
    } else std.Io.File.stdout().writerStreaming(init.io, &buf);

    try tracer.img.writePpm(&w.interface);
    try w.flush();
}

fn checkeredSpheres(io: std.Io, allocator: std.mem.Allocator, params: *const Params) !Tracer {
    var tracer = try Tracer.init(io, allocator, .{
        .img_w = params.img_w,
        .seed = params.seed,
        .samples_per_px = params.samples,
        .defocus_angle = 0.0,
    });

    const checker = try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
        .texture = try tracer.pool.addAndReturnHandle(mat.Texture{ .checker = .{
            .scale = 0.32,
            .even = try tracer.pool.addAndReturnHandle(
                mat.Texture{
                    .solid = .{ .color = .{ .x = 0.2, .y = 0.3, .z = 0.1 } },
                },
            ),
            .odd = try tracer.pool.addAndReturnHandle(
                mat.Texture{ .solid = .{ .color = V3.of(0.9) } },
            ),
        } }),
    } });
    _ = try tracer.pool.add(Sphere.stationary(.{ .x = 0, .y = -10, .z = 0 }, 10, checker));
    _ = try tracer.pool.add(Sphere.stationary(.{ .x = 0, .y = 10, .z = 0 }, 10, checker));
    return tracer;
}

fn randomBouncing(io: std.Io, allocator: std.mem.Allocator, params: *const Params) !Tracer {
    var tracer = try Tracer.init(io, allocator, .{
        .img_w = params.img_w,
        .seed = params.seed,
        .samples_per_px = params.samples,
    });
    // ground
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = -1000, .z = 0 },
        1000,
        try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
            .texture = try tracer.pool.addAndReturnHandle(mat.Texture{ .checker = .{
                .scale = 0.32,
                .even = try tracer.pool.addAndReturnHandle(
                    mat.Texture{
                        .solid = .{ .color = .{ .x = 0.2, .y = 0.3, .z = 0.1 } },
                    },
                ),
                .odd = try tracer.pool.addAndReturnHandle(
                    mat.Texture{ .solid = .{ .color = V3.of(0.9) } },
                ),
            } }),
        } }),
    ));

    // main 3
    try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.addAndReturnHandle(mat.Material{ .dielectric = .{
            .refractive_index = 1.5,
        } }),
    ));
    try tracer.pool.add(Sphere.stationary(
        .{ .x = -4, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
            .texture = try tracer.pool.addAndReturnHandle(mat.Texture{ .solid = .{
                .color = V3{ .x = 0.4, .y = 0.2, .z = 0.1 },
            } }),
        } }),
    ));
    try tracer.pool.add(Sphere.stationary(
        .{ .x = 4, .y = 1, .z = 0 },
        1.0,
        try tracer.pool.addAndReturnHandle(mat.Material{ .metallic = .{
            .texture = try tracer.pool.addAndReturnHandle(
                mat.Texture{
                    .solid = .{
                        .color = V3{ .x = 0.7, .y = 0.6, .z = 0.5 },
                    },
                },
            ),
        } }),
    ));

    // randoms

    var a: isize = -11;
    var rng = std.Random.DefaultPrng.init(tracer.seed);
    const rand = rng.random();
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

            var sphere_ray = vec.Ray.init(center, .{}, 0);
            var m: ?ecs.MaterialHandle = null;

            if (rand_mat < 0.8) {
                m = try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
                    .texture = try tracer.pool.addAndReturnHandle(
                        mat.Texture{
                            .solid = .{
                                .color = V3.random(rand, 0, 1.0).vmul(V3.random(rand, 0, 1.0)),
                            },
                        },
                    ),
                } });
                // moving from center up in y by [0,0.5] over the time window
                sphere_ray.dir = V3.yHat().mul(rand.float(f64) * 0.5);
            } else if (rand_mat < 0.95) {
                m = try tracer.pool.addAndReturnHandle(mat.Material{ .metallic = .{
                    .fuzz = rand.float(f64) * 0.5,
                    .texture = try tracer.pool.addAndReturnHandle(
                        mat.Texture{ .solid = .{
                            .color = V3.random(rand, 0.5, 1.0),
                        } },
                    ),
                } });
            } else {
                // glass
                m = try tracer.pool.addAndReturnHandle(mat.Material{ .dielectric = .{
                    .refractive_index = 1.5,
                } });
            }

            _ = try tracer.pool.add(Sphere{
                .center = sphere_ray,
                .radius = 0.2,
                .material = m.?,
            });
        }
    }
    return tracer;
}

fn penultimateScene(io: std.Io, allocator: std.mem.Allocator, params: *const Params) !Tracer {
    var tracer = try Tracer.init(io, allocator, .{
        .img_w = params.img_w,
        .focus_dist = 3.4,
        .defocus_angle = 10,
        .look_from = .{ .x = -2, .y = 2, .z = 1 },
        .look_at = .{ .x = 0, .y = 0, .z = -1 },
        .seed = params.seed,
        .samples_per_px = params.samples,
    });

    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = 0, .z = -1.2 },
        0.5,
        try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
            .texture = try tracer.pool.addAndReturnHandle(mat.Texture{
                .solid = .{ .color = .{ .x = 0.1, .y = 0.2, .z = 0.5 } },
            }),
        } }),
    ));
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 0, .y = -100.5, .z = -1 },
        100,
        try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
            .texture = try tracer.pool.addAndReturnHandle(mat.Texture{
                .solid = .{ .color = .{ .x = 0.8, .y = 0.8, .z = 0.0 } },
            }),
        } }),
    ));

    // left outer
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = -1, .y = 0, .z = -1 },
        0.5,
        try tracer.pool.addAndReturnHandle(mat.Material{ .dielectric = .{
            .refractive_index = 1.5,
        } }),
    ));

    // left inner bubble
    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = -1, .y = 0, .z = -1 },
        0.4,
        try tracer.pool.addAndReturnHandle(mat.Material{ .dielectric = .{
            .refractive_index = 1.0 / 1.5,
        } }),
    ));

    _ = try tracer.pool.add(Sphere.stationary(
        .{ .x = 1, .y = 0, .z = -1 },
        0.5,
        try tracer.pool.addAndReturnHandle(mat.Material{ .diffuse = .{
            .texture = try tracer.pool.addAndReturnHandle(mat.Texture{
                .solid = .{
                    .color = .{ .x = 0.8, .y = 0.6, .z = 0.2 },
                },
            }),
        } }),
    ));
    return tracer;
}
