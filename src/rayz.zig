const std = @import("std");
const renderer = @import("./renderer.zig");
const geom = @import("./geom.zig");

const Tracer = renderer.Tracer;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const img_w = try std.fmt.parseUnsigned(usize, args.next().?, 10);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tracer = try Tracer.init(arena.allocator(), img_w, 16.0 / 9.0);

    const spheres = [_]geom.Sphere{
        .{ .center = geom.V3.init(0, 0, -1), .radius = 0.5 },
        .{ .center = geom.V3.init(0, -100.5, -1), .radius = 100 },
    };
    for (&spheres) |*s| {
        try tracer.addObject(.{ .ptr = s, .hit = geom.Sphere.hit });
    }

    tracer.render();

    if (args.next()) |out_fname| {
        const f = try std.fs.cwd().createFile(out_fname, .{ .read = false, .truncate = true });
        defer f.close();
        try tracer.img.writePPM(f);
    } else {
        try tracer.img.writePPM(std.io.getStdOut());
    }
}
