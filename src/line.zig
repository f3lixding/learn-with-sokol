const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const sgl = sokol.gl;
const math = std.math;
const shd = @import("shaders/line.glsl.zig");
const mat4 = @import("math.zig").Mat4;
const vec3 = @import("math.zig").Vec3;

const per_frame_speed: f64 = 1;
const max_segments: usize = 10; // Number of segments in the lightning bolt
const jitter_amount: f32 = 0.1; // How much each segment can deviate
const segment_length: f32 = 0.8; // Length of each segment
const regen_interval: f32 = 0.2; // Time between lightning regenerations
const change_thres: f32 = 0.75;
const branch_thres: f32 = 0.5;

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
    var branch_segment_len: usize = 0;
    var bind: sg.Bindings = .{};
    var dir: Direction = .FOR;
    var seed: u64 = 0;
    var time_since_regen: f32 = 0;
    var total_length: f32 = 5.0; // Total length of the lightning
    var rotation_angle: f32 = 0;
    var rolling_angle: f32 = 0;
    var pip: sg.Pipeline = .{};
};

fn branch_by_percentage(
    perc: f32,
    last_point: struct { x: f32, y: f32 },
    cur_point: struct { x: f32, y: f32 },
) BranchSegment {
    // Calculate the branch root position by interpolating between the two points
    const root_x = last_point.x + perc * (cur_point.x - last_point.x);
    const root_y = last_point.y + perc * (cur_point.y - last_point.y);

    // Calculate the direction of the main segment
    const main_angle = math.atan2(cur_point.y - last_point.y, cur_point.x - last_point.x);

    // Branch at an angle relative to the main segment (45-90 degrees off)
    const branch_angle_offset = (random_float() * 0.5 + 0.25) * math.pi; // 45-90 degrees
    const branch_direction: f32 = if (random_float() > 0.5) 1.0 else -1.0; // Left or right
    const branch_angle = main_angle + branch_direction * branch_angle_offset;

    // Make branch length proportional to segment length but shorter
    const segment_len = math.sqrt(math.pow(f32, cur_point.x - last_point.x, 2) + math.pow(f32, cur_point.y - last_point.y, 2));
    const branch_len = segment_len * (0.3 + random_float() * 0.4); // 30-70% of segment length

    const tip_x = root_x + branch_len * @cos(branch_angle);
    const tip_y = root_y + branch_len * @sin(branch_angle);

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
    state.branch_segment_len = 0;

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

        if (random_float() > branch_thres) {
            // Calculate branche max_segments
            state.branch_segments[state.branch_segment_len] = branch_by_percentage(
                random_float(),
                .{ .x = state.segments[i - 1].x, .y = state.segments[i - 1].y },
                .{ .x = state.segments[i].x, .y = state.segments[i].y },
            );
            state.branch_segment_len += 1;
        }
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

    // Calculate rolling based on orbital distance
    // Cube circumference = 4 units (assuming unit cube), orbital radius = 12.5
    // Rolling angle = orbital_distance / cube_radius
    const cube_radius = 1.0; // Half the cube size
    const orbital_radius = 12.5; // From get_params function
    const orbital_distance = radians * orbital_radius;
    state.rolling_angle += @floatCast(orbital_distance / cube_radius);
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

    // cube vertex buffer
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            // positions        colors
            -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,
            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,

            -1.0, -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  1.0,  1.0,  0.0, 1.0, 0.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 1.0, 0.0, 1.0,

            -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 0.0, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.0, 1.0, 1.0,

            1.0,  -1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.5, 0.0, 1.0,
            1.0,  -1.0, 1.0,  1.0, 0.5, 0.0, 1.0,

            -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,

            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
            -1.0, 1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
        }),
    });

    // cube index buffer
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{
            0,  1,  2,  0,  2,  3,
            6,  5,  4,  7,  6,  4,
            8,  9,  10, 8,  10, 11,
            14, 13, 12, 15, 14, 12,
            16, 17, 18, 16, 18, 19,
            22, 21, 20, 23, 22, 20,
        }),
    });

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.shapeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_shape_position].format = .FLOAT3;
            l.attrs[shd.ATTR_shape_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
    });

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

    // Calculate uniform transformation
    // The output of which is a mvp matrix
    // MVP = Projection * View * Model
    const shape_vs_params = get_params(state.rotation_angle, state.rolling_angle);

    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_shape_vs_params, sg.asRange(&shape_vs_params));
    // Draw cube with 36 indices (6 faces * 2 triangles * 3 vertices each)
    sg.draw(0, 36, 1);

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
    }

    sgl.c3f(1.0, 0.0, 0.0);
    i = 0;
    while (i < state.branch_segment_len) : (i += 1) {
        // Get branch points
        const bx1 = state.branch_segments[i].x1;
        const by1 = state.branch_segments[i].y1;
        const bx2 = state.branch_segments[i].x2;
        const by2 = state.branch_segments[i].y2;

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

fn get_params(angle: f64, rolling_angle: f32) shd.ShapeVsParams {
    // Create projection matrix (perspective)
    const proj = mat4.persp(90.0, sapp.widthf() / sapp.heightf(), 0.01, 100.0);

    // Create view matrix (camera looking at origin from positive Z)
    const view = mat4.lookat(.{ .x = 0.0, .y = 0.0, .z = 25.0 }, vec3.zero(), vec3.up());

    // Combine projection and view matrices
    const view_proj = mat4.mul(proj, view);

    // Create model matrix with translation, orbital rotation, and rolling rotation
    // Calculate world space equivalent of 0.5 in normalized device coordinates
    // With camera at Z=25 and 90° FOV, visible width at Z=0 is ~50 units
    // So 0.5 in NDC = 0.5 * 25 = 12.5 world units
    const ndc_to_world_scale: f32 = 25.0; // Half the visible width at Z=0
    const translation_distance = 0.5 * ndc_to_world_scale; // 12.5 world units
    const translation_matrix = mat4.translate(vec3.new(0.0, translation_distance, 0.0));

    // Rolling rotation around Z-axis (around the imaginary rod to center)
    const rolling_matrix = mat4.rotate(rolling_angle * 180.0 / math.pi, vec3.new(0.0, 1.0, 0.0));

    // Combine translation and rolling: first translate, then apply rolling
    const translated_and_rolled = mat4.mul(rolling_matrix, translation_matrix);

    // Then rotate around the origin (Z-axis) by the given angle (convert from f64 to f32)
    // This creates orbital motion with rolling
    const orbital_rotation_matrix = mat4.rotate(@floatCast(angle * 180.0 / math.pi), vec3.new(0.0, 0.0, 1.0));

    // Combine orbital rotation with the translated and rolled cube
    const model = mat4.mul(orbital_rotation_matrix, translated_and_rolled);

    // Create final MVP matrix: MVP = Projection * View * Model
    const mvp = mat4.mul(view_proj, model);

    return shd.ShapeVsParams{ .mvp = mvp };
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
