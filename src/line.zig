const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const sgl = sokol.gl;
const math = std.math;

const per_frame_speed: f64 = 1;

// Using a collection of static fields
// This struct is never instantiated
const state = struct {
    var pass_action: sg.PassAction = .{};
    var x1: f32 = 0;
    var x2: f32 = 0;
    var y1: f32 = 0;
    var y2: f32 = 5.0;
    var pip: sgl.Pipeline = .{};
};

// This function accepts a state
fn tick(input: anytype, dt: f64) void {
    // Calculate rotation angle for this frame
    const degree_to_be_moved = @as(f64, (dt * per_frame_speed * 60));
    const radians = -degree_to_be_moved * (math.pi / 180.0);

    const cos_theta = math.cos(radians);
    const sin_theta = math.sin(radians);

    // Get current position
    const x = input.x2;
    const y = input.y2;

    // Rotate around origin (0,0)
    input.x2 = @floatCast(x * cos_theta - y * sin_theta);
    input.y2 = @floatCast(x * sin_theta + y * cos_theta);
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
}

export fn frame() void {
    sg.beginPass(.{});

    const dt = sapp.frameDuration();
    tick(&state, dt);

    sgl.defaults();
    sgl.beginLines();
    sgl.c3f(0, 0, 1);
    sgl.v2f(state.x1, state.y1);
    sgl.v2f(state.x2, state.y2);
    sgl.end();
    sgl.draw();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "line.zig",
        .logger = .{ .func = slog.func },
    });
}
