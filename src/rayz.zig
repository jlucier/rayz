const std = @import("std");
const renderer = @import("./renderer.zig");
const V3 = @import("./vec.zig").V3;
const geom = @import("./geom.zig");
const mat = @import("./material.zig");

const Tracer = renderer.Tracer;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const img_w = try std.fmt.parseUnsigned(usize, args.next().?, 10);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tracer = try Tracer.init(arena.allocator(), img_w);

    const R = @cos(std.math.pi / 4.0);
    const spheres = [_]geom.Sphere{
        .{ .center = V3.init(-R, 0, -1), .radius = R, .material = .{
            .mat_type = .Diffuse,
            .albedo = V3.init(0, 0, 1),
        } },
        .{ .center = V3.init(R, 0, -1), .radius = R, .material = .{
            .mat_type = .Diffuse,
            .albedo = V3.init(1, 0, 0),
        } },
        // .{
        //     .center = V3.init(0, 0, -1.2),
        //     .radius = 0.5,
        //     .material = .{
        //         .mat_type = .Diffuse,
        //         .albedo = V3.init(0.1, 0.2, 0.5),
        //     },
        // },
        // .{
        //     .center = V3.init(0, -100.5, -1),
        //     .radius = 100,
        //     .material = .{
        //         .mat_type = .Diffuse,
        //         .albedo = V3.init(0.8, 0.8, 0.0),
        //     },
        // },
        // // left outer
        // .{
        //     .center = V3.init(-1, 0, -1),
        //     .radius = 0.5,
        //     .material = .{
        //         .mat_type = .Dielectric,
        //         .refractive_index = 1.5,
        //     },
        // },
        // // left inner bubble
        // .{
        //     .center = V3.init(-1, 0, -1),
        //     .radius = 0.4,
        //     .material = .{
        //         .mat_type = .Dielectric,
        //         .refractive_index = 1.0 / 1.5,
        //     },
        // },
        // .{
        //     .center = V3.init(1, 0, -1),
        //     .radius = 0.5,
        //     .material = .{
        //         .mat_type = .Metallic,
        //         .albedo = V3.init(0.8, 0.6, 0.2),
        //         .fuzz = 1.0,
        //     },
        // },
    };

    for (&spheres) |*s| {
        try tracer.addObject(.{ .ptr = s, .hit = geom.Sphere.hit });
    }

    const st = try std.time.Instant.now();

    const rays_traced: f64 = @floatFromInt(tracer.render());

    var durr: f64 = @floatFromInt(std.time.Instant.since(try std.time.Instant.now(), st));
    durr /= std.time.ns_per_s;
    std.debug.print("Finished render: {d:.2} rps and {d:.2} us per ray\n", .{
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
