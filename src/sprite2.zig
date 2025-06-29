// This is a simplified version of sprite.zig
// It strips away the portion that has to do with the rendering of the cube.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const zigimg = @import("zigimg");

const shd = @import("shaders/sprite2.glsl.zig");

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "sprite_two";

const FrameMetadata = struct {
    name: []const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

const SpriteFrame = struct {
    u_min: f32,
    v_min: f32,
    u_max: f32,
    v_max: f32,
};

const Vertex = struct {
    x: f32,
    y: f32,
    color: u32,
    u: f32,
    v: f32,
};

const state = struct {
    var x: f32 = 0.0;
    var y: f32 = 0.0;
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pass_action: sg.PassAction = .{};
    const sprite_frames = [_]SpriteFrame{
        .{ .u_min = 0.0, .v_min = 0.0, .u_max = 1.0, .v_max = 1.0 },
        .{ .u_min = 0.0, .v_min = 0.5, .u_max = 0.5, .v_max = 1.0 },
        .{ .u_min = 0.5, .v_min = 0.5, .u_max = 1.0, .v_max = 1.0 },
        .{ .u_min = 0.5, .v_min = 0.0, .u_max = 1.0, .v_max = 1.0 },
    };
    // How often the sprite cycles happens
    const frame_threshold: usize = 10;
    // Current sprite frame, used to index [sprite_frames]
    var current_sframe: usize = 0;
    var frame_counter: usize = 0;
};

fn updateVertexUVs(sprite_frame: SpriteFrame) void {
    // This represents the four corners of a sprite
    const vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = -1.0, .y = -1.0, .color = 0xFF0000FF, .u = sprite_frame.u_min, .v = sprite_frame.v_min },
        .{ .x = -1.0, .y =  1.0, .color = 0xFF0000FF, .u = sprite_frame.u_min, .v = sprite_frame.v_max },
        .{ .x =  1.0, .y =  1.0, .color = 0xFF0000FF, .u = sprite_frame.u_max, .v = sprite_frame.v_max },
        .{ .x =  1.0, .y = -1.0, .color = 0xFF0000FF, .u = sprite_frame.u_max, .v = sprite_frame.v_min },
        // zig fmt: on
    };
    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(&vertices));
}

fn initSpriteFrames(allocator: Allocator, sprite_frames: *[]FrameMetadata) !void {
    // read metadata
    const metadata_file = try std.fs.cwd().openFile("assets/googly_eyes.json", .{});
    var contents = std.ArrayList(u8).init(allocator);
    defer contents.deinit();
    var buffer: [1024]u8 = undefined;
    while (true) {
        const size = try metadata_file.read(&buffer);
        try contents.appendSlice(buffer[0..size]);
        if (size == 0) {
            break;
        }
    }

    const slice = try contents.toOwnedSlice();
    defer allocator.free(slice);
    // deserialize from json
    const parsed = try std.json.parseFromSlice([]FrameMetadata, allocator, slice, .{});
    defer parsed.deinit();
    const frame_mds = parsed.value;
    var copy_dst = std.ArrayList(FrameMetadata).init(allocator);
    for (frame_mds) |frame_md| {
        try copy_dst.append(.{
            .name = try allocator.dupe(u8, frame_md.name),
            .x = frame_md.x,
            .y = frame_md.y,
            .width = frame_md.width,
            .height = frame_md.height,
        });
    }
    sprite_frames.* = try copy_dst.toOwnedSlice();
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var image = zigimg.Image.fromFilePath(allocator, "assets/googly_eyes.png") catch unreachable;
    defer image.deinit();

    var sprite_frames: []FrameMetadata = undefined;
    initSpriteFrames(allocator, &sprite_frames) catch unreachable;
    std.debug.print("Number of frames: {d}\n", .{sprite_frames.len});
    for (sprite_frames) |sprite_frame| {
        const name = sprite_frame.name;
        const height = sprite_frame.height;
        std.debug.print("name: {s}, height: {d}\n", .{name, height});
    }

    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true},
        .size = 4 * @sizeOf(Vertex),
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0, 1, 2, 0, 2, 3,
        }),
    });

    state.bind.images[shd.IMG_tex] = sg.makeImage(.{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data = init: {
            var data = sg.ImageData{};
            data.subimage[0][0] = sg.asRange(image.pixels.rgba32);
            break :init data;
        },
    });

    state.bind.samplers[shd.SMP_smp] = sg.makeSampler(.{});

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.spritetwoShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_spritetwo_pos].format = .FLOAT2;
            l.attrs[shd.ATTR_spritetwo_color0].format = .UBYTE4N;
            l.attrs[shd.ATTR_spritetwo_uv0].format = .FLOAT2;
            break :init l;
        },
        .index_type = .UINT16, 
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1 },
    };
}

export fn frame() void {
    updateVertexUVs(state.sprite_frames[state.current_sframe]);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
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
        .width = WINDOW_HEIGHT,
        .height = WINDOW_HEIGHT,
        .sample_count = SAMPLE_COUNT,
        .icon = .{ .sokol_default = true },
        .window_title = WINDOW_TITLE.ptr,
        .logger = .{ .func = slog.func },
    });
}
