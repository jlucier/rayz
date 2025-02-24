const std = @import("std");

pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

pub fn clamp(comptime T: type, x: T, low: T, high: T) T {
    return min(T, max(T, x, low), high);
}

test "min" {
    try std.testing.expectEqual(min(u8, 1, 2), 1);
    try std.testing.expectEqual(min(f16, 10.0, -0.5), -0.5);
}

test "max" {
    try std.testing.expectEqual(max(u8, 1, 2), 2);
    try std.testing.expectEqual(max(f16, 10.0, -0.5), 10.0);
}

test "clamp" {
    try std.testing.expectEqual(clamp(u8, 100, 1, 10), 10);
    try std.testing.expectEqual(clamp(usize, 5, 1, 10), 5);

    try std.testing.expectEqual(clamp(f32, 0.01, 0.0, 1.0), 0.01);
    try std.testing.expectEqual(clamp(f32, -2.999, -1.0, 0), -1.0);
    try std.testing.expectEqual(clamp(f32, 2.999, -1.0, 0), 0);
}
