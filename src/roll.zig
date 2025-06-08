const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const math = @import("math.zig");
const shd = @import("shaders/roll.glsl.zig");

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind_grid: sg.Bindings = .{};
    var bind_cube: sg.Bindings = .{};
    var pip_grid: sg.Pipeline = .{};
    var pip_cube: sg.Pipeline = .{};
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // fullscreen quad for grid background
    state.bind_grid.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            -1.0, -1.0, 0.0, 1.0,
            1.0,  -1.0, 0.0, 1.0,
            1.0,  1.0,  0.0, 1.0,
            -1.0, 1.0,  0.0, 1.0,
        }),
    });

    state.bind_grid.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });

    // grid pipeline
    state.pip_grid = sg.makePipeline(.{
        .shader = sg.makeShader(shd.gridShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_grid_position].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .ALWAYS,
            .write_enabled = false,
        },
    });

    // framebuffer clear color
    state.pass_action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 } };
}

export fn frame() void {
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });

    // draw grid background
    sg.applyPipeline(state.pip_grid);
    sg.applyBindings(state.bind_grid);
    sg.draw(0, 6, 1);

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
        .width = 100,
        .height = 100,
        .sample_count = 4,
        .window_title = "roll.zig",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
