const std = @import("std");
const mat = @import("./material.zig");
const geom = @import("./geom.zig");
const hit = @import("./hit.zig");

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

    pub fn add(self: *MemPool, obj: anytype) !usize {
        const t = @TypeOf(obj);
        var l = switch (t) {
            mat.Texture => &self.textures,
            mat.Material => &self.materials,
            geom.Sphere => &self.spheres,
            else => @compileError(@typeName(t)),
        };
        try l.append(obj);
        return l.items.len - 1;
    }

    pub fn addMaterialWithTexture(
        self: *MemPool,
        material: mat.Material,
        texture: mat.Texture,
    ) !usize {
        var copy = material;
        copy.texture = try self.add(texture);
        return try self.add(copy);
    }
};
