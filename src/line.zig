const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const sgl = sokol.gl;

// Using a collection of static fields
// This struct is never instantiated
const state = struct {
    var pass_action: sg.PassAction = .{};
    var x1: f32 = 0;
    var x2: f32 = 0;
    var y1: f32 = 0;
    var y2: f32 = 0;
    var pip: sgl.Pipeline = .{};
};

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

    // state starting points
    state.x2 = 5.0;
    state.y2 = 5.0;
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

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
