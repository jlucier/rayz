const std = @import("std");
const mat = @import("./material.zig");
const geom = @import("./geom.zig");
const hit = @import("./hit.zig");

pub fn Handle(comptime T: type) type {
    return struct {
        idx: usize,

        const Self = @This();

        pub fn get(self: *const Self, storage: []const T) *const T {
            // TODO add index safety
            return &storage[self.idx];
        }
    };
}

pub const TextureHandle = Handle(mat.Texture);
pub const MaterialHandle = Handle(mat.Material);

pub const MemPool = struct {
    allocator: std.mem.Allocator,
    spheres: std.ArrayList(geom.Sphere),
    materials: std.ArrayList(mat.Material),
    textures: std.ArrayList(mat.Texture),

    pub fn init(allocator: std.mem.Allocator) MemPool {
        return .{
            .allocator = allocator,
            .spheres = std.ArrayList(geom.Sphere).init(allocator),
            .materials = std.ArrayList(mat.Material).init(allocator),
            .textures = std.ArrayList(mat.Texture).init(allocator),
        };
    }

    pub fn deinit(self: *const MemPool) void {
        self.spheres.deinit();
        self.materials.deinit();
        self.textures.deinit();
    }

    pub fn initHittables(self: *const MemPool, hittables: *hit.HittableList) !void {
        for (self.spheres.items) |*s| {
            try hittables.append(.{
                .ptr = s,
                .hit = geom.Sphere.hit,
                .bbox = s.boundingBox(),
            });
        }
    }

    pub fn add(self: *MemPool, obj: anytype) !void {
        _ = try self.addAndReturnHandle(obj);
    }

    pub fn addAndReturnHandle(self: *MemPool, obj: anytype) !Handle(@TypeOf(obj)) {
        const t = @TypeOf(obj);
        var l = switch (t) {
            geom.Sphere => &self.spheres,
            mat.Texture => &self.textures,
            mat.Material => &self.materials,
            else => @compileError(@typeName(t)),
        };
        try l.append(obj);
        return .{
            .idx = l.items.len - 1,
        };
    }
};
