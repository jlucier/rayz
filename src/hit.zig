const std = @import("std");
const vec = @import("./vec.zig");
const mat = @import("./material.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

pub const Hittable = struct {
    bbox: AABB,
    ptr: *const anyopaque,
    hit: *const fn (ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit,
};

pub const Hit = struct {
    point: V3,
    normal: V3,
    t: f64,
    front_face: bool,
    material: mat.Material,

    pub fn init(ray: *const Ray, point: V3, normal: V3, t: f64, material: mat.Material) Hit {
        // ray is hitting front if it points against normal dir, otherwise back face
        const front_face = normal.dot(ray.dir) < 0;
        return .{
            .point = point,
            .normal = if (front_face) normal else normal.mul(-1),
            .t = t,
            .front_face = front_face,
            .material = material,
        };
    }
};

pub const AABB = struct {
    low: V3 = V3.of(std.math.inf(f64)),
    high: V3 = V3.of(-std.math.inf(f64)),

    pub fn init(a: V3, b: V3) AABB {
        return .{
            .low = a.vmin(b),
            .high = a.vmax(b),
        };
    }

    pub fn enclose(a: AABB, b: AABB) AABB {
        return .{
            .low = a.low.vmin(b.low),
            .high = a.high.vmax(b.high),
        };
    }

    pub fn center(self: *const AABB) V3 {
        return self.high.sub(self.low).add(self.high);
    }

    pub fn hit(self: *const AABB, ray: *const Ray, tmin: f64, tmax: f64) bool {
        // solve ray equation for t at the low and high ends of the boundaries per axis
        // p(t) = q + dt
        // x - q = dt
        const t0s = self.low.sub(ray.origin).vdiv(ray.dir);
        const t1s = self.high.sub(ray.origin).vdiv(ray.dir);

        // std.debug.print("hit check:\n{}\n{}\n", .{ t0s, t1s });

        // reduce all the solutions to the highest min and lowest max -- tightest range
        // (also factor in the provided time range for the hit)
        const t0 = @max(t0s.x, t0s.y, t0s.z, tmin);
        const t1 = @min(t1s.x, t1s.y, t1s.z, tmax);

        // hit if the range is valid
        return t1 > t0;
    }
};

pub const BVH = struct {
    allocator: std.mem.Allocator,
    bbox: AABB = .{},
    children: [2]?*BVH = .{ null, null },
    hittables: std.ArrayList(Hittable),
    split_axis: u8 = 0,
    max_children: usize = 10,

    pub fn init(allocator: std.mem.Allocator, axis: u8) BVH {
        return .{
            .allocator = allocator,
            .hittables = std.ArrayList(Hittable).init(allocator),
            .split_axis = axis,
        };
    }

    pub fn deinit(self: *const BVH) void {
        for (self.children) |opt_c| {
            if (opt_c) |c| {
                c.deinit();
                self.allocator.destroy(c);
            }
        }

        self.hittables.deinit();
    }

    const SortCtx = struct {
        split_axis: u8,
    };

    fn hittableLess(ctx: SortCtx, a: Hittable, b: Hittable) bool {
        const av = switch (ctx.split_axis) {
            0 => a.bbox.low.x,
            1 => a.bbox.low.y,
            2 => a.bbox.low.z,
            else => unreachable,
        };
        const bv = switch (ctx.split_axis) {
            0 => b.bbox.low.x,
            1 => b.bbox.low.y,
            2 => b.bbox.low.z,
            else => unreachable,
        };

        return av < bv;
    }

    pub fn addHittable(self: *BVH, obj: Hittable) !void {
        // update bbox to include this node (always needed)
        self.bbox = AABB.enclose(self.bbox, obj.bbox);

        if (self.children[0] != null) {
            // has children, add to child nearest the object
            const oc = obj.bbox.center();
            const d0 = self.children[0].?.bbox.center().sub(oc).mag();
            const d1 = self.children[1].?.bbox.center().sub(oc).mag();

            try self.children[if (d0 < d1) 0 else 1].?.addHittable(obj);
            return;
        } else if (self.hittables.items.len + 1 <= self.max_children) {
            // add and exit
            try self.hittables.append(obj);
            return;
        }

        // subdivide

        std.mem.sort(
            Hittable,
            self.hittables.items,
            SortCtx{ .split_axis = self.split_axis },
            hittableLess,
        );

        const next_axis = (self.split_axis + 1) % 3;
        self.children[0] = try self.allocator.create(BVH);
        self.children[1] = try self.allocator.create(BVH);
        self.children[0].?.* = BVH.init(self.allocator, next_axis);
        self.children[1].?.* = BVH.init(self.allocator, next_axis);
        const mid = self.hittables.items.len / 2;

        for (self.hittables.items, 0..) |*h, i| {
            const node = self.children[i / mid].?;
            try node.addHittable(h.*);
        }

        self.hittables.clearAndFree();
    }

    pub fn findHit(self: *const BVH, ray: *const Ray, tmin: f64, tmax: f64) ?Hit {
        if (!self.bbox.hit(ray, tmin, tmax)) {
            return null;
        }

        // might hit something
        var maybe_hit: ?Hit = null;

        if (self.children[0]) |c0| {
            // have children, check them
            maybe_hit = c0.findHit(ray, tmin, tmax);

            const maxt = if (maybe_hit) |h| h.t else std.math.inf(f64);

            if (self.children[1].?.findHit(ray, tmin, maxt)) |new_hit| {
                maybe_hit = new_hit;
            }
            return maybe_hit;
        }

        // no children, check hittables
        for (self.hittables.items) |*h| {
            const maxt = if (maybe_hit) |ht| ht.t else std.math.inf(f64);

            if (h.hit(h.ptr, ray, tmin, maxt)) |new_hit| {
                maybe_hit = new_hit;
            }
        }
        return maybe_hit;
    }
};

const DummyHittable = struct {
    return_hit: bool = false,

    pub fn hit(ptr: *const anyopaque, _: *const Ray, _: f64, _: f64) ?Hit {
        const self: *const DummyHittable = @ptrCast(@alignCast(ptr));
        if (self.return_hit) {
            return .{
                .point = V3{},
                .normal = V3{},
                .t = 0,
                .front_face = true,
                .material = .{ .mat_type = .Dielectric },
            };
        }
        return null;
    }
};

test "enclose bbox" {
    const super = AABB.enclose(
        AABB.init(V3.of(1), V3.of(-1)),
        AABB.init(V3.of(0), V3.of(2)),
    );

    try std.testing.expect(super.low.close(V3.of(-1)));
    try std.testing.expect(super.high.close(V3.of(2)));
}

test "bbox hit" {
    const box = AABB.init(V3.of(0), V3.ones());
    const r1 = Ray{
        .origin = V3.of(-1),
        .dir = V3.ones(),
    };
    const r2 = Ray{
        .origin = V3.of(-1),
        .dir = V3.of(-1),
    };
    const r3 = Ray{
        .origin = V3.of(-1),
        .dir = V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
    };

    try std.testing.expect(box.hit(&r1, 0, 10));
    try std.testing.expect(!box.hit(&r2, 0, 10));
    try std.testing.expect(box.hit(&r3, 0, 10));
}

test "bvh memory management" {
    const alloc = std.testing.allocator;

    var inner = try alloc.create(BVH);
    inner.allocator = alloc;
    inner.children = .{ null, null };
    inner.hittables = std.ArrayList(Hittable).init(alloc);

    const h = DummyHittable{};
    try inner.hittables.append(.{
        .ptr = &h,
        .hit = DummyHittable.hit,
        .bbox = .{},
    });

    var bvh = BVH.init(alloc, 0);
    defer bvh.deinit();

    bvh.children[0] = inner;
}

test "bvh hit" {
    var bvh = BVH.init(std.testing.allocator, 0);
    defer bvh.deinit();

    const d = DummyHittable{ .return_hit = true };
    try bvh.addHittable(.{
        .ptr = &d,
        .hit = DummyHittable.hit,
        .bbox = AABB.init(V3.of(0), V3.ones()),
    });

    const r1 = Ray{
        .origin = V3.of(-1),
        .dir = V3.ones(),
    };
    const r2 = Ray{
        .origin = V3.of(-1),
        .dir = V3.of(-1),
    };
    const r3 = Ray{
        .origin = V3.of(-1),
        .dir = V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
    };

    try std.testing.expect(bvh.findHit(&r1, 0, 10) != null);
    try std.testing.expect(bvh.findHit(&r2, 0, 10) == null);
    try std.testing.expect(bvh.findHit(&r3, 0, 10) != null);
}
