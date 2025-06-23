const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const math = @import("math.zig");
const shd = @import("shaders/roll.glsl.zig");
const mat4 = @import("math.zig").Mat4;
const vec3 = @import("math.zig").Vec3;

const assert = std.debug.assert;

const RollDir = enum {
    // + about x
    up,
    // - about x
    down,
    // - about y
    left,
    // + about y
    right,
};

const CubeState = struct {
    roll_state: ?struct { dir: RollDir, target: f32 } = null,
    // roll (about x)
    phi: f32 = 0.0,
    // pitch (about y)
    theta: f32 = 0.0,
    // yaw (about z)
    psi: f32 = 0.0,
    // the position where the cube belongs
    pos: struct { x: f32, y: f32 } = .{ .x = 0.0, .y = 0.0 },

    pub fn set_roll_dir(self: *@This(), dir: RollDir) void {
        if (self.roll_state == null) {
            // Need to normalize the target angle here so it's easier to compare after
            // As is the comparison would fail for when the number wraps around
            self.rolling_dir = .{ .dir = dir, .target = blk: switch (dir) {
                .up => break :blk self.phi +% 90.0,
                .down => break :blk self.phi -% 90.0,
                .left => break :blk self.theta -% 90.0,
                .right => break :blk self.theta +% 90.0,
            } };
        }
    }

    pub fn frame(self: *@This(), angle: f32) void {
        if (self.roll_state) |*roll_state| {
            switch (roll_state.dir) {
                .up => {
                    const new_angle = self.phi +% angle;
                    if (new_angle >= roll_state.target) {
                        self.phi = roll_state.target;
                        roll_state = null;
                    } else {
                        self.phi = new_angle;
                    }
                },
                .down => {
                    const new_angle = self.phi -% angle;
                    if (new_angle <= roll_state.target) {
                        self.phi = roll_state.target;
                        roll_state = null;
                    } else {
                        self.phi = new_angle;
                    }
                },
                .left => {},
                .right => {},
            }
        }
    }
};

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind_grid: sg.Bindings = .{};
    var bind_cube: sg.Bindings = .{};
    var pip_grid: sg.Pipeline = .{};
    var pip_cube: sg.Pipeline = .{};
    var cube_state: CubeState = .{};
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

    // vertex buffers for cube
    state.bind_cube.vertex_buffers[0] = sg.makeBuffer(.{
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

    state.bind_grid.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });

    state.bind_cube.index_buffer = sg.makeBuffer(.{
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

    // cube Pipeline
    state.pip_cube = sg.makePipeline(.{
        .shader = sg.makeShader(shd.cubeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_cube_position].format = .FLOAT3;
            l.attrs[shd.ATTR_cube_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
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

    // draw cube
    const cube_vs_params = get_params(.{ 0, 0 });
    sg.applyPipeline(state.pip_cube);
    sg.applyBindings(state.bind_cube);
    sg.applyUniforms(shd.UB_cube_vs_params, sg.asRange(&cube_vs_params));
    sg.draw(0, 36, 1);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

fn get_params(pos: struct { u32, u32 }) shd.CubeVsParams {
    // We would need to first validate this
    const x, const y = pos;
    _ = x;
    _ = y;
    const proj = mat4.persp(90.0, sapp.widthf() / sapp.heightf(), 0.01, 100.0);
    const view = mat4.lookat(.{ .x = 0.0, .y = 0.0, .z = 25.0 }, vec3.zero(), vec3.up());
    const view_proj = mat4.mul(proj, view);
    return shd.CubeVsParams{ .mvp = view_proj };
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
