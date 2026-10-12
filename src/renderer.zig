const std = @import("std");
const vec = @import("./vec.zig");
const image = @import("./image.zig");
const hitmod = @import("./hit.zig");
const mat = @import("./material.zig");
const Camera = @import("./camera.zig").Camera;
const MemPool = @import("./ecs.zig").MemPool;

const V3 = vec.V3;
const Ray = vec.Ray;
const Hit = hitmod.Hit;
const Hittable = hitmod.Hittable;
const HittableList = hitmod.HittableList;
const BVH = hitmod.BVH;

const aspect_ratio = 16.0 / 9.0;

pub const Tracer = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    camera: Camera,
    img: image.Image,
    max_bounces: usize = 50,
    samples_per_px: usize = 10,
    hittables: HittableList,
    bvh: BVH,
    pool: MemPool,
    seed: u64,

    pub const Options = struct {
        img_w: usize,
        seed: u64,
        max_bounces: usize = 50,
        samples_per_px: usize = 10,
        vfov: f64 = 20,
        focus_dist: f64 = 10,
        defocus_angle: f64 = 0.6,
        look_from: V3 = .{ .x = 13, .y = 2, .z = 3 },
        look_at: V3 = .{},
        vup: V3 = V3.yHat(),
    };

    pub fn init(io: std.Io, allocator: std.mem.Allocator, opts: Options) !Tracer {
        const image_width_f: f64 = @floatFromInt(opts.img_w);
        const height: usize = @intFromFloat(image_width_f / aspect_ratio);

        return .{
            .io = io,
            .allocator = allocator,
            .camera = Camera.init(
                opts.vfov,
                opts.focus_dist,
                opts.defocus_angle,
                opts.look_from,
                opts.look_at,
                opts.vup,
                height,
                opts.img_w,
            ),
            .img = try image.Image.initEmpty(allocator, height, opts.img_w),
            .hittables = HittableList.init(allocator),
            .bvh = BVH.init(allocator),
            .pool = MemPool.init(allocator),
            .seed = opts.seed,
            .samples_per_px = opts.samples_per_px,
        };
    }

    pub fn deinit(self: *const Tracer) void {
        self.bvh.deinit();
        self.img.deinit();
        self.hittables.deinit();
    }

    const Worker = struct {
        thread: std.Thread,
        start: usize,
        end: usize,
        rays: usize = 0,
        done_pixels: usize = 0,
    };

    pub fn render(self: *Tracer) !usize {
        self.hittables.clearRetainingCapacity();
        try self.pool.initHittables(&self.hittables);
        try self.bvh.build(&self.hittables, 0, self.hittables.items.len);

        const min_rows_per_thread: f64 = 10;
        const image_height_f: f64 = @floatFromInt(self.img.h);
        const row_chunk_count: usize = @intFromFloat(
            @ceil(image_height_f / min_rows_per_thread),
        );
        const worker_count = @min(row_chunk_count, try std.Thread.getCpuCount());
        const worker_count_f: f64 = @floatFromInt(worker_count);
        const rows_per_thread: usize = @intFromFloat(@ceil(image_height_f / worker_count_f));

        const workers: []Worker = try self.allocator.alloc(Worker, worker_count);
        defer self.allocator.free(workers);

        for (workers, 0..) |*w, i| {
            w.done_pixels = 0;
            w.rays = 0;
            w.start = i * rows_per_thread;
            w.end = @min(self.img.h, (i + 1) * rows_per_thread);
            w.thread = try std.Thread.spawn(.{}, Tracer.threadRender, .{ self, w });
        }

        const tot = self.img.w * self.img.h;
        while (true) {
            var done: usize = 0;
            for (workers) |*w| {
                done += w.done_pixels;
            }
            const ft: f32 = @floatFromInt(tot);
            const fd: f32 = @floatFromInt(done);
            std.debug.print("\rProgress: {d:.2}%", .{fd / ft * 100});

            if (done == tot) {
                std.debug.print("\n", .{});
                break;
            }
            try self.io.sleep(.fromMilliseconds(50), .awake);
        }

        var rays: usize = 0;
        for (workers) |w| {
            w.thread.join();
            rays += w.rays;
        }

        return rays;
    }

    fn threadRender(self: *Tracer, w: *Worker) void {
        const ss: u64 = @intCast(w.start);
        const es: u64 = @intCast(w.end);
        var rng = std.Random.DefaultPrng.init(self.seed + es - ss);

        for (w.start..w.end) |j| {
            for (0..self.img.w) |i| {
                var r: usize = 0;
                var acc_color = V3{};
                while (r < self.samples_per_px) : (r += 1) {
                    const ray = self.camera.getRay(i, j, rng.random());
                    w.rays += 1;
                    acc_color = acc_color.add(self.bounceRay(&ray, &rng, self.max_bounces));
                }

                self.img.pixels[j * self.img.w + i] = //
                    acc_color.div(@floatFromInt(self.samples_per_px));

                w.done_pixels += 1;
            }
        }
    }

    fn bounceRay(
        self: *const Tracer,
        ray: *const Ray,
        rng: *std.Random.DefaultPrng,
        depth: usize,
    ) V3 {
        if (depth == 0)
            return V3{};

        var hit = Hit{};
        var scat = mat.ScatterParam{
            .random = rng.random(),
            .ray = ray,
            .hit = &hit,
            .textures = self.pool.textures.items,
        };

        if (self.bvh.findHit(&hit, &self.hittables, ray, 1e-10, std.math.inf(f64))) {
            // bounce light
            var ret = V3{};
            const m = hit.material.get(self.pool.materials.items);
            if (m.scatter(&scat)) |res| {
                ret = self.bounceRay(&res.ray, rng, depth - 1).vmul(res.attenuation);
            }
            return ret;
        }

        // miss, background gradient
        const t: f64 = 0.5 * (ray.dir.unit().y + 1.0);
        return V3.ones().mul(1.0 - t).add((V3{ .x = 0.5, .y = 0.7, .z = 1.0 }).mul(t));
    }
};

test "get ray" {
    const look_from = V3{ .x = -2, .y = 2, .z = 1 };
    const look_at = V3{ .x = 0, .y = 0, .z = -1 };

    const cam = Camera.init(
        90,
        look_from.sub(look_at).mag(),
        0,
        look_from,
        look_at,
        V3.yHat(), // vup
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
