const std = @import("std");
const Image = @import("./image.zig").Image;
const V3 = @import("./vec.zig").V3;

pub fn main() !void {
    var im = try Image.initEmpty(std.heap.page_allocator, 256, 256);
    defer im.deinit();

    var i: usize = 0;
    while (i < im.h) : (i += 1) {
        var j: usize = 0;
        while (j < im.w) : (j += 1) {
            var r: f64 = @floatFromInt(i);
            r /= @floatFromInt(im.h - 1);
            var g: f64 = @floatFromInt(j);
            g /= @floatFromInt(im.w - 1);
            im.at(i, j).* = V3.init(r, g, 0.25);
        }
    }
    const f = try std.fs.cwd().createFile("test.ppm", .{
        .read = false,
        .truncate = true,
    });
    defer f.close();
    try im.writePPM(f);
    std.debug.print("Rayz\n", .{});
}
