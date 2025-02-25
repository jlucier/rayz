const std = @import("std");
const renderer = @import("./renderer.zig");
const vec = @import("./vec.zig");
const geom = @import("./geom.zig");
const mat = @import("./material.zig");

const Tracer = renderer.Tracer;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const img_w = try std.fmt.parseUnsigned(usize, args.next().?, 10);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tracer = try Tracer.init(arena.allocator(), img_w, 16.0 / 9.0);

    const lambertian = mat.Diffuse{};
    const diffuse_mat = mat.Material{
        .ptr = &lambertian,
        .scatter = mat.Diffuse.scatter,
    };
    const spheres = [_]geom.Sphere{
        .{
            .center = vec.V3.init(0, 0, -1),
            .radius = 0.5,
            .material = diffuse_mat,
        },
        .{
            .center = vec.V3.init(0, -100.5, -1),
            .radius = 100,
            .material = diffuse_mat,
        },
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
