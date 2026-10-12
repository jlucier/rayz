const std = @import("std");
const vec = @import("./vec.zig");
const ecs = @import("./ecs.zig");

const Ray = vec.Ray;
const V3 = vec.V3;

pub const Hittable = struct {
    bbox: AABB,
    ptr: *const anyopaque,
    hit: *const fn (
        ptr: *const anyopaque,
        ray: *const Ray,
        hit_out: *Hit,
        t_min: f64,
        t_max: f64,
    ) bool,
};

pub const HittableList = std.array_list.Managed(Hittable);

pub const Hit = struct {
    point: V3 = .{},
    normal: V3 = .{},
    t: f64 = 0,
    u: f64 = 0,
    v: f64 = 0,
    material: ecs.MaterialHandle = .{},
    front_face: bool = false,

    pub fn computeFront(self: *Hit, ray: *const Ray) void {
        // ray is hitting front if it points against normal dir, otherwise back face
        self.front_face = self.normal.dot(ray.dir) < 0;
        if (!self.front_face) {
            self.normal = self.normal.mul(-1);
        }
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

    pub fn diagonal(self: *const AABB) V3 {
        return self.high.sub(self.low);
    }

    pub fn longestAxis(self: *const AABB) u8 {
        return self.diagonal().amax();
    }

    pub fn center(self: *const AABB) V3 {
        return self.diagonal().div(2).add(self.low);
    }

    pub fn surfaceArea(self: *const AABB) f64 {
        const d = self.diagonal();
        return d.x * d.y + d.y * d.z + d.x * d.z;
    }

    pub fn diagonalLen(self: *const AABB) f64 {
        return self.diagonal().mag();
    }

    pub fn hit(self: *const AABB, ray: *const Ray, t_min: f64, t_max: f64) bool {
        // solve ray equation for t at the low and high ends of the boundaries per axis
        // p(t) = q + dt
        // x - q = dt
        const t0s = self.low.sub(ray.origin).vmul(ray.inv_dir);
        const t1s = self.high.sub(ray.origin).vmul(ray.inv_dir);
        var t0 = t_min;
        var t1 = t_max;
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
    start_index: usize = 0,
    end_index: usize = 0,
    left: ?*BVH = null,
    right: ?*BVH = null,
    hit_checks: usize = 0,

    const SahSplit = struct {
        ax: u8 = 0,
        cost: f64 = 0,
        thresh: f64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) BVH {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *const BVH) void {
        if (self.left) |c| {
            c.deinit();
            self.allocator.destroy(c);
        }
        if (self.right) |c| {
            c.deinit();
            self.allocator.destroy(c);
        }
    }

    /// Surface Area Heuristic implementation to split volumes on longest axis
    fn sahFindSplit(self: *const BVH, hittables: []const Hittable) SahSplit {
        const n_axes: u8 = 3;
        const n_steps: usize = 12;

        var costs: [n_axes * n_steps]SahSplit = undefined;

        for (&costs, 0..) |*c, i| {
            c.ax = @intCast(i / n_steps);
            c.cost = std.math.inf(f64);

            const i_f: f64 = @floatFromInt(i % n_steps);
            const step = self.bbox.diagonal().at(c.ax) / n_steps;

            c.thresh = self.bbox.low.at(c.ax) + step * (i_f + 1);

            var a = AABB{};
            var b = AABB{};
            var count_a: usize = 0;
            var count_b: usize = 0;

            for (hittables) |h| {
                if (h.bbox.center().at(c.ax) < c.thresh) {
                    a = AABB.enclose(a, h.bbox);
                    count_a += 1;
                } else {
                    b = AABB.enclose(b, h.bbox);
                    count_b += 1;
                }
            }
            if (count_a > 0 and count_b > 0) {
                const ca: f64 = @floatFromInt(count_a);
                const cb: f64 = @floatFromInt(count_b);
                costs[i].cost = ca * a.surfaceArea() + cb * b.surfaceArea();
            }
        }

        var min_cost = &costs[0];
        for (&costs) |*c| {
            if (c.cost < min_cost.cost) {
                min_cost = c;
            }
        }

        return min_cost.*;
    }

    fn hittableLess(ctx: SahSplit, a: Hittable, b: Hittable) bool {
        return a.bbox.center().at(ctx.ax) < b.bbox.center().at(ctx.ax);
    }

    pub fn build(self: *BVH, hittables: *HittableList, start_index: usize, end_index: usize) !void {
        const object_count = end_index - start_index;
        std.debug.assert(object_count > 0);

        // enclose all bboxes
        for (hittables.items[start_index..end_index]) |*h| {
            self.bbox = AABB.enclose(self.bbox, h.bbox);
        }

        if (object_count <= 2) {
            // I myself will own these and will not subdivide
            self.start_index = start_index;
            self.end_index = end_index;
            return;
        }

        // subdivide
        const split = self.sahFindSplit(hittables.items[start_index..end_index]);
        std.mem.sort(
            Hittable,
            hittables.items[start_index..end_index],
            split,
            hittableLess,
        );

        // find the point where the centers cross thresh
        var thresh_i = start_index + 1;
        for (hittables.items[start_index + 1 .. end_index], start_index + 1..) |h, i| {
            if (h.bbox.center().at(split.ax) >= split.thresh) {
                thresh_i = i;
                break;
            }
        }

        self.left = try self.allocator.create(BVH);
        self.right = try self.allocator.create(BVH);
        self.left.?.* = BVH.init(self.allocator);
        self.right.?.* = BVH.init(self.allocator);

        try self.left.?.build(hittables, start_index, thresh_i);
        try self.right.?.build(hittables, thresh_i, end_index);
    }

    pub fn print(self: *const BVH, d: usize) !void {
        const prefix = try self.allocator.alloc(u8, d);
        var i: usize = 0;
        while (i < d) : (i += 1) {
            prefix[i] = ' ';
        }

        std.debug.print("{s}{d} Node ({} - {d} - {d:.4} - {d})\n", .{
            prefix,
            d,
            self.left != null,
            self.end_index - self.start_index,
            self.bbox.diagonalLen(),
            self.hit_checks,
        });

        if (self.left != null) {
            try self.left.?.print(d + 1);
            try self.right.?.print(d + 1);
        }
    }

    pub fn findHit(
        self: *const BVH,
        hit: *Hit,
        hittables: *const HittableList,
        ray: *const Ray,
        t_min: f64,
        t_max: f64,
    ) bool {
        // self.hit_checks += 1;
        if (!self.bbox.hit(ray, t_min, t_max)) {
            return false;
        }

        var maybe_hit = false;

        if (self.left != null) {
            // have children, check them
            maybe_hit = self.left.?.findHit(hit, hittables, ray, t_min, t_max);
            maybe_hit |= self.right.?.findHit(
                hit,
                hittables,
                ray,
                t_min,
                if (maybe_hit) hit.t else t_max,
            );
            return maybe_hit;
        }

        // no children, check hittables
        for (hittables.items[self.start_index..self.end_index]) |*h| {
            const maxt = if (maybe_hit) hit.t else t_max;

            if (h.hit(h.ptr, ray, hit, t_min, maxt)) {
                maybe_hit = true;
            }
        }
        return maybe_hit;
    }
};

const DummyHittable = struct {
    return_hit: bool = false,

    pub fn hit(ptr: *const anyopaque, _: *const Ray, ho: *Hit, _: f64, _: f64) bool {
        const self: *const DummyHittable = @ptrCast(@alignCast(ptr));
        if (self.return_hit) {
            ho.* = Hit{
                .point = V3{},
                .normal = V3{},
                .t = 0,
                .front_face = true,
                .material = .{ .idx = 0 },
            };
            return true;
        }
        return false;
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
    const r1 = Ray.init(V3.of(-1), V3.ones(), 0);
    const r2 = Ray.init(V3.of(-1), V3.of(-1), 0);
    const r3 = Ray.init(
        V3.of(-1),
        V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
        0,
    );

    try std.testing.expect(box.hit(&r1, 0, 10));
    try std.testing.expect(!box.hit(&r2, 0, 10));
    try std.testing.expect(box.hit(&r3, 0, 10));
}

test "bbox hit 2" {
    const box = AABB.init(
        .{ .x = -1000, .y = -2000, .z = -1000 },
        .{ .x = 1000, .y = 2, .z = 1000 },
    );
    const r1 = Ray.init(
        vec.V3{ .x = 13, .y = 2, .z = 3 },
        vec.V3{ .x = -9.6, .y = -1.5, .z = -2.3 },
        0.6,
    );

    try std.testing.expect(box.hit(&r1, 0, 10));
}

test "bvh hit" {
    var bvh = BVH.init(std.testing.allocator);
    defer bvh.deinit();

    const dh = DummyHittable{ .return_hit = true };
    var hl = HittableList.init(std.testing.allocator);
    defer hl.deinit();
    try hl.append(.{
        .ptr = &dh,
        .hit = DummyHittable.hit,
        .bbox = AABB.init(V3.of(0), V3.ones()),
    });
    try bvh.build(&hl, 0, hl.items.len);

    const r1 = Ray.init(V3.of(-1), V3.ones(), 0);
    const r2 = Ray.init(V3.of(-1), V3.of(-1), 0);
    const r3 = Ray.init(
        V3.of(-1),
        V3{ .x = 0.5, .y = 0.5, .z = 0.5 },
        0,
    );

    var hit: Hit = .{};
    try std.testing.expect(bvh.findHit(&hit, &hl, &r1, 0, 10));
    try std.testing.expect(!bvh.findHit(&hit, &hl, &r2, 0, 10));
    try std.testing.expect(bvh.findHit(&hit, &hl, &r3, 0, 10));
}
