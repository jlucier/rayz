const std = @import("std");

pub fn clamp(comptime T: type, x: T, low: T, high: T) T {
    return @min(@max(x, low), high);
}

test "clamp" {
    try std.testing.expectEqual(clamp(u8, 100, 1, 10), 10);
    try std.testing.expectEqual(clamp(usize, 5, 1, 10), 5);

    try std.testing.expectEqual(clamp(f32, 0.01, 0.0, 1.0), 0.01);
    try std.testing.expectEqual(clamp(f32, -2.999, -1.0, 0), -1.0);
    try std.testing.expectEqual(clamp(f32, 2.999, -1.0, 0), 0);
}
