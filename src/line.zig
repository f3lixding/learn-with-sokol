const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const sgl = sokol.gl;
const math = std.math;

const per_frame_speed: f64 = 1;
const max_segments: usize = 10; // Number of segments in the lightning bolt
const jitter_amount: f32 = 0.1; // How much each segment can deviate
const segment_length: f32 = 0.8; // Length of each segment
const regen_interval: f32 = 0.2; // Time between lightning regenerations
const change_thres: f32 = 0.75;

const Direction = enum { FOR, BACK };

const Segment = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const BranchSegment = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
};

// Using a collection of static fields
// This struct is never instantiated
const state = struct {
    var pass_action: sg.PassAction = .{};
    var segments: [max_segments + 1]Segment = undefined;
    var branch_segments: [max_segments + 1]BranchSegment = undefined;
    var dir: Direction = .FOR;
    var seed: u64 = 0;
    var time_since_regen: f32 = 0;
    var total_length: f32 = 5.0; // Total length of the lightning
    var rotation_angle: f32 = 0;
};

fn branch_by_percentage(
    perc: f32,
    last_point: struct { x: f32, y: f32 },
    cur_point: struct { x: f32, y: f32 },
) BranchSegment {
    const slope: f32 = (cur_point.y - last_point.y) / (cur_point.x - last_point.x);
    const root_x = perc * (cur_point.x - last_point.x);
    const root_y = slope * (root_x - last_point.x) + last_point.y;
    const base_angle = 0; // Pointing upward
    const jitter = (random_float() * 10 - 1) * jitter_amount;
    const angle = base_angle + jitter;
    const seg_len = state.total_length / max_segments * random_float() * 0.2;
    const tip_x = root_x + seg_len * @sin(angle);
    const tip_y = root_y + seg_len * @cos(angle);
    return .{
        .x1 = root_x,
        .y1 = root_y,
        .x2 = tip_x,
        .y2 = tip_y,
    };
}

// Simple random number generator
fn random_float() f32 {
    state.seed = state.seed *% 6364136223846793005 +% 1;
    const value = (state.seed >> 33) ^ state.seed;
    return @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(std.math.maxInt(u64)));
}

fn init_lightning() void {
    // We want to introduce a random chance as to when the lightning will be changed
    if (random_float() < change_thres) {
        return;
    }
    // Start at origin
    state.segments[0] = .{};

    // Generate a jagged path for the lightning
    var i: usize = 1;
    while (i <= max_segments) : (i += 1) {
        // Calculate base direction (straight line)
        const base_angle = 0; // Pointing upward

        // Add randomness to the angle
        const jitter = (random_float() * 2 - 1) * jitter_amount;
        const angle = base_angle + jitter;

        // Calculate new point
        const seg_len = state.total_length / max_segments * random_float();
        state.segments[i].x = state.segments[i - 1].x + seg_len * @sin(angle);
        state.segments[i].y = state.segments[i - 1].y + seg_len * @cos(angle);

        // Calculate branche max_segments
        state.branch_segments[i] = branch_by_percentage(
            random_float(),
            .{ .x = state.segments[i - 1].x, .y = state.segments[i - 1].y },
            .{ .x = state.segments[i].x, .y = state.segments[i].y },
        );
    }
}

// This function updates the lightning state
fn tick(dt: f64) void {
    // Update time since last regeneration
    state.time_since_regen += @floatCast(dt);

    // Regenerate lightning if needed
    if (state.time_since_regen >= regen_interval) {
        init_lightning();
        state.time_since_regen = 0;
    }

    // Determine rotation direction
    const multiplier: f64 = if (state.dir == .BACK) -1 else 1;

    // Calculate rotation angle for this frame
    const degree_to_be_moved = dt * per_frame_speed * 60;
    const radians = multiplier * degree_to_be_moved * (math.pi / 180.0);

    // Update total rotation angle
    state.rotation_angle += @floatCast(radians);
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    sgl.setup(.{ .logger = .{ .func = slog.func } });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0 },
    };

    // Initialize random number generator with current time
    state.seed = @intCast(std.time.milliTimestamp());

    // Initialize the lightning bolt
    init_lightning();
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const dt = sapp.frameDuration();
    tick(dt); // We don't use the input parameter

    sgl.defaults();
    sgl.beginLines();

    // Draw lightning bolt as a series of connected line segments
    // Use a bright blue color for the lightning
    sgl.c3f(0.3, 0.3, 1.0);

    // Calculate rotation matrix
    const cos_theta = @as(f32, @floatCast(math.cos(state.rotation_angle)));
    const sin_theta = @as(f32, @floatCast(math.sin(state.rotation_angle)));

    // Draw each segment of the lightning with rotation applied
    var i: usize = 0;
    while (i < max_segments) : (i += 1) {
        // Get original points
        const x1 = state.segments[i].x;
        const y1 = state.segments[i].y;
        const x2 = state.segments[i + 1].x;
        const y2 = state.segments[i + 1].y;

        // Apply rotation to both points
        const rotated_x1 = x1 * cos_theta - y1 * sin_theta;
        const rotated_y1 = x1 * sin_theta + y1 * cos_theta;
        const rotated_x2 = x2 * cos_theta - y2 * sin_theta;
        const rotated_y2 = x2 * sin_theta + y2 * cos_theta;

        // Draw the rotated line segment
        sgl.v2f(rotated_x1, rotated_y1);
        sgl.v2f(rotated_x2, rotated_y2);

        // Get branch points
        const bx1 = state.branch_segments[i].x1;
        const by1 = state.branch_segments[i].y1;
        const bx2 = state.branch_segments[i + 1].x2;
        const by2 = state.branch_segments[i + 1].y2;

        // Branches
        const r_bx1 = bx1 * cos_theta - by1 * sin_theta;
        const r_by1 = bx1 * sin_theta + by1 * cos_theta;
        const r_bx2 = bx2 * cos_theta - by2 * sin_theta;
        const r_by2 = bx2 * sin_theta + by2 * cos_theta;
        sgl.v2f(r_bx1, r_by1);
        sgl.v2f(r_bx2, r_by2);
    }

    sgl.end();
    sgl.draw();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

export fn handle_event(event: [*c]const sapp.Event) void {
    const event_type = &event.*.type;
    if (event_type.* == .KEY_DOWN) {
        state.dir = switch (state.dir) {
            .FOR => .BACK,
            .BACK => .FOR,
        };
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = handle_event,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "line.zig",
        .logger = .{ .func = slog.func },
    });
}
