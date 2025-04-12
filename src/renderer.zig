const std = @import("std");
const vec = @import("./vec.zig");
const image = @import("./image.zig");
const hitmod = @import("./hit.zig");
const mat = @import("./material.zig");
const Camera = @import("./camera.zig").Camera;
const MemPool = @import("./mem.zig").MemPool;

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;
const Hittable = hitmod.Hittable;
const HittableList = hitmod.HittableList;
const BVH = hitmod.BVH;

const ASPECT_RATIO = 16.0 / 9.0;

pub const Tracer = struct {
    allocator: std.mem.Allocator,
    camera: Camera,
    img: image.Image,
    rng: std.Random.DefaultPrng,
    max_bounces: usize = 50,
    samples_per_px: usize = 10,
    hittables: HittableList,
    bvh: BVH,
    pool: MemPool,

    pub fn init(
        allocator: std.mem.Allocator,
        img_w: usize,
        vfov: f64,
        focus_dist: f64,
        defocus_angle: f64,
        look_from: V3,
        look_at: V3,
        vup: V3,
    ) !Tracer {
        const fimg_w: f64 = @floatFromInt(img_w);
        const height: usize = @intFromFloat(fimg_w / ASPECT_RATIO);

        return .{
            .allocator = allocator,
            .camera = Camera.init(
                vfov,
                focus_dist,
                defocus_angle,
                look_from,
                look_at,
                vup,
                height,
                img_w,
            ),
            .img = try image.Image.initEmpty(allocator, height, img_w),
            .rng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            }),
            .hittables = HittableList.init(allocator),
            .bvh = BVH.init(allocator),
            .pool = MemPool.init(allocator),
        };
    }

    pub fn deinit(self: *const Tracer) void {
        self.bvh.deinit();
        self.img.deinit();
        self.hittables.deinit();
    }

    pub fn render(self: *Tracer) !usize {
        var rays: usize = 0;
        var j: usize = 0;

        self.hittables.clearRetainingCapacity();
        try self.pool.initHittables(&self.hittables);
        try self.bvh.build(&self.hittables, 0, self.hittables.items.len);

        while (j < self.img.h) : (j += 1) {
            var i: usize = 0;
            const fj: f64 = @floatFromInt(j);
            const fh: f64 = @floatFromInt(self.img.h);
            std.debug.print("\rProgress: {d:.2}%", .{fj / fh * 100});
            while (i < self.img.w) : (i += 1) {
                var r: usize = 0;
                var acc_color = V3{};
                while (r < self.samples_per_px) : (r += 1) {
                    const ray = self.camera.getRay(i, j, self.rng.random());
                    rays += 1;
                    acc_color = acc_color.add(self.bounceRay(&ray, self.max_bounces));
                }

                self.img.pixels[j * self.img.w + i] = //
                    acc_color.div(@floatFromInt(self.samples_per_px));
            }
        }
        std.debug.print("\rProgress: {d:.2}%", .{100.0});
        std.debug.print("\n", .{});
        return rays;
    }

    fn bounceRay(self: *Tracer, ray: *const Ray, depth: usize) V3 {
        if (depth == 0)
            return V3{};

        if (self.bvh.findHit(&self.hittables, ray, 1e-10, std.math.inf(f64))) |hit| {
            // bounce light
            var ret = V3{};
            const m = self.pool.materials.items[hit.material];
            const param = mat.ScatterParam{
                .random = self.rng.random(),
                .ray = ray,
                .hit = &hit,
                .textures = self.pool.textures.items,
            };
            if (m.scatter(param)) |res| {
                ret = self.bounceRay(&res.ray, depth - 1).vmul(res.attenuation);
            }
            return ret;
        }

        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y + 1.0);
        return V3.ones().mul(1.0 - t).add(V3{ .x = 0.5, .y = 0.7, .z = 1.0 }).mul(t);
    }
};

test "get ray" {
    const cam = Camera.init(
        90,
        V3{ .x = -2, .y = 2, .z = 1 }, // look_from
        V3{ .x = 0, .y = 0, .z = -1 }, // look_at
        V3.y_hat(), // vup
        225,
        400,
    );

    const r1 = cam.getRay(0, 0, null);
    const r2 = cam.getRay(112, 199, null);

    try std.testing.expectApproxEqRel(-0.935834, r1.dir.x, 1e-5);
    try std.testing.expectApproxEqRel(0.815856, r1.dir.y, 1e-5);
    try std.testing.expectApproxEqRel(-7.75169, r1.dir.z, 1e-5);

    try std.testing.expectApproxEqRel(-0.998817, r2.dir.x, 1e-5);
    try std.testing.expectApproxEqRel(-4.18732, r2.dir.y, 1e-5);
    try std.testing.expectApproxEqRel(-2.8115, r2.dir.z, 1e-5);
}
