const std = @import("std");
const vec = @import("./vec.zig");
const ecs = @import("./ecs.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

pub const Hittable = struct {
    bbox: AABB,
    ptr: *const anyopaque,
    hit: *const fn (ptr: *const anyopaque, ray: *const Ray, tmin: f64, tmax: f64) ?Hit,
};

pub const HittableList = std.ArrayList(Hittable);

pub const Hit = struct {
    point: V3,
    normal: V3,
    t: f64,
    u: f64 = 0,
    v: f64 = 0,
    front_face: bool,
    material: ecs.MaterialHandle,

    pub fn init(
        ray: *const Ray,
        point: V3,
        normal: V3,
        t: f64,
        material: ecs.MaterialHandle,
    ) Hit {
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

    pub fn longestAxis(self: *const AABB) u8 {
        return self.high.sub(self.low).amax();
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

        var t0 = tmin;
        var t1 = tmax;
        const axes = [_]u8{ 0, 1, 2 };

        // reduce all the solutions to the highest min and lowest max -- tightest range
        // (also factor in the provided time range for the hit)
        for (axes) |ax| {
            const v0 = t0s.at(ax);
            const v1 = t1s.at(ax);

            if (v0 < v1) {
                t0 = @max(v0, t0);
                t1 = @min(v1, t1);
            } else {
                t0 = @max(v1, t0);
                t1 = @min(v0, t1);
            }
        }

        // hit if the range is valid
        return t1 > t0;
    }
};

pub const BVH = struct {
    allocator: std.mem.Allocator,
    bbox: AABB = .{},
    starti: usize = 0,
    endi: usize = 0,
    left: ?*BVH = null,
    right: ?*BVH = null,

    pub fn init(allocator: std.mem.Allocator) BVH {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *const BVH) void {
        for (self.children) |opt_c| {
            if (opt_c) |c| {
                c.deinit();
                self.allocator.destroy(c);
            }
        }
    }

    const SortCtx = struct {
        split_axis: u8,
    };

    fn hittableLess(ctx: SortCtx, a: Hittable, b: Hittable) bool {
        return a.bbox.low.at(ctx.split_axis) < b.bbox.low.at(ctx.split_axis);
    }

    pub fn build(self: *BVH, hittables: *HittableList, si: usize, ei: usize) !void {
        const nobjs = ei - si;
        std.debug.assert(nobjs > 0);

        // enclose all bboxes
        for (hittables.items[si..ei]) |*h| {
            self.bbox = AABB.enclose(self.bbox, h.bbox);
        }

        if (nobjs <= 2) {
            // I myself will own these and will not subdivide
            self.starti = si;
            self.endi = ei;
        } else {
            // subdivide
            std.mem.sort(
                Hittable,
                hittables.items[si..ei],
                SortCtx{ .split_axis = self.bbox.longestAxis() },
                hittableLess,
            );

            self.left = try self.allocator.create(BVH);
            self.right = try self.allocator.create(BVH);
            self.left.?.* = BVH.init(self.allocator);
            self.right.?.* = BVH.init(self.allocator);

            const mid = nobjs / 2 + si;
            try self.left.?.build(hittables, si, mid);
            try self.right.?.build(hittables, mid, ei);
        }
    }

    pub fn print(self: *const BVH, d: usize) !void {
        const prefix = try self.allocator.alloc(u8, d);
        var i: usize = 0;
        while (i < d) : (i += 1) {
            prefix[i] = ' ';
        }

        std.debug.print("{s}Node ({} - {d})\n", .{
            prefix,
            self.left != null,
            self.endi - self.starti,
        });
        if (self.left != null) {
            try self.left.?.print(d + 1);
            try self.right.?.print(d + 1);
        }
    }

    pub fn findHit(
        self: *const BVH,
        hittables: *const HittableList,
        ray: *const Ray,
        tmin: f64,
        tmax: f64,
    ) ?Hit {
        if (!self.bbox.hit(ray, tmin, tmax)) {
            return null;
        }

        // might hit something
        var maybe_hit: ?Hit = null;

        if (self.left != null) {
            // have children, check them
            maybe_hit = self.left.?.findHit(hittables, ray, tmin, tmax);

            const maxt = if (maybe_hit) |h| h.t else tmax;

            if (self.right.?.findHit(hittables, ray, tmin, maxt)) |new_hit| {
                maybe_hit = new_hit;
            }
            return maybe_hit;
        }

        // no children, check hittables
        for (hittables.items[self.starti..self.endi]) |*h| {
            const maxt = if (maybe_hit) |ht| ht.t else tmax;

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
                .material = .{ .idx = 0 },
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

test "bbox hit 2" {
    const box = AABB.init(
        .{ .x = -1000, .y = -2000, .z = -1000 },
        .{ .x = 1000, .y = 2, .z = 1000 },
    );
    const r1 = Ray{
        .origin = vec.V3{ .x = 13, .y = 2, .z = 3 },
        .dir = vec.V3{ .x = -9.6, .y = -1.5, .z = -2.3 },
        .time = 0.6,
    };

    try std.testing.expect(box.hit(&r1, 0, 10));
}

// test "bvh memory management" {
//     const alloc = std.testing.allocator;
//
//     var inner = try alloc.create(BVH);
//     inner.allocator = alloc;
//     inner.children = .{ null, null };
//     inner.hittables = std.ArrayList(Hittable).init(alloc);
//
//     const h = DummyHittable{};
//     try inner.hittables.append(.{
//         .ptr = &h,
//         .hit = DummyHittable.hit,
//         .bbox = .{},
//     });
//
//     var bvh = BVH.init(alloc);
//     defer bvh.deinit();
//
//     bvh.left = inner;
// }

// test "bvh hit" {
//     var bvh = BVH.init(std.testing.allocator);
//     defer bvh.deinit();
//
//     const d = DummyHittable{ .return_hit = true };
//     try bvh.addHittable(.{
//         .ptr = &d,
//         .hit = DummyHittable.hit,
//         .bbox = AABB.init(V3.of(0), V3.ones()),
//     });
//
//     const r1 = Ray{
//         .origin = V3.of(-1),
//         .dir = V3.ones(),
//     };
//     const r2 = Ray{
//         .origin = V3.of(-1),
//         .dir = V3.of(-1),
//     };
//     const r3 = Ray{
//         .origin = V3.of(-1),
//         .dir = V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
//     };
//
//     try std.testing.expect(bvh.findHit(&r1, 0, 10) != null);
//     try std.testing.expect(bvh.findHit(&r2, 0, 10) == null);
//     try std.testing.expect(bvh.findHit(&r3, 0, 10) != null);
// }
