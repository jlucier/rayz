const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("rayz", .{
        .root_source_file = b.path("src/rayz.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "rayz",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "Run all project tests");
    const test_sources = [_][]const u8{
        "src/geom.zig",
        "src/hit.zig",
        "src/material.zig",
        "src/renderer.zig",
        "src/utils.zig",
        "src/vec.zig",
    };
    for (test_sources, 0..) |source, i| {
        const test_module = b.addModule(b.fmt("rayz_test_{d}", .{i}), .{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
        });
        const test_exe = b.addTest(.{ .root_module = test_module });
        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }
}
