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

    pub fn toSpriteFrame(self: @This(), image_u: usize, image_v: usize) SpriteFrame {
        // Need to first normalize this
        const image_u_float: f32 = @floatFromInt(image_u);
        const image_v_float: f32 = @floatFromInt(image_v);
        const x_float: f32 = @floatFromInt(self.x);
        const y_float: f32 = @floatFromInt(self.y);
        const width_float: f32 = @floatFromInt(self.width);
        const height_float: f32 = @floatFromInt(self.height);

        const u_min: f32 = x_float / image_u_float;
        const v_min: f32 = y_float / image_v_float;
        const u_max: f32 = (x_float + width_float) / image_u_float;
        const v_max: f32 = (y_float + height_float) / image_v_float;

        return .{
            .u_min = u_min,
            .v_min = v_min,
            .u_max = u_max,
            .v_max = v_max,
        };
    }
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator: Allocator = undefined;
    var x: f32 = 0.0;
    var y: f32 = 0.0;
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pass_action: sg.PassAction = .{};
    var sprite_frames: []SpriteFrame = undefined;
    // How often the sprite cycles happens
    const frame_threshold: u64 = 5;
    // Current sprite frame, used to index [sprite_frames]
    var current_sframe: usize = 0;
    var last_switched_frame: u64 = 0;

    pub fn deinit() void {
        state.allocator.free(sprite_frames);
        _ = state.gpa.deinit();
    }

    pub fn updateFrames() void {
        const current_frame = sapp.frameCount();
        const diff = current_frame - state.last_switched_frame;
        const total_sframes: u64 = @intCast(state.sprite_frames.len);
        if (diff >= state.frame_threshold) {
            state.last_switched_frame = current_frame;
            state.current_sframe = (state.current_sframe + 1) % total_sframes;
        }
    }
};

fn updateVertexUVs(sprite_frame: SpriteFrame) void {
    // This represents the four corners of a sprite
    const vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = -1.0, .y = -1.0, .color = 0xFFFFFFFF, .u = sprite_frame.u_min, .v = sprite_frame.v_min },
        .{ .x = -1.0, .y =  1.0, .color = 0xFFFFFFFF, .u = sprite_frame.u_min, .v = sprite_frame.v_max },
        .{ .x =  1.0, .y =  1.0, .color = 0xFFFFFFFF, .u = sprite_frame.u_max, .v = sprite_frame.v_max },
        .{ .x =  1.0, .y = -1.0, .color = 0xFFFFFFFF, .u = sprite_frame.u_max, .v = sprite_frame.v_min },
        // zig fmt: on
    };
    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(&vertices));
}

fn initSpriteFrames(allocator: Allocator, sprite_frames: *[]FrameMetadata) !void {
    // read metadata
    const metadata_file = try std.fs.cwd().openFile("assets/captain.json", .{});
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

fn getSpriteFramesFromMetadata(allocator: Allocator, metadata: []FrameMetadata, width: usize, height: usize) ![]SpriteFrame {
    var res = std.ArrayList(SpriteFrame).init(allocator);
    for (metadata) |data| {
        try res.append(data.toSpriteFrame(width, height));
    }
    
    return try res.toOwnedSlice();
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const allocator = state.gpa.allocator();
    var image = zigimg.Image.fromFilePath(allocator, "assets/captain.png") catch unreachable;
    defer image.deinit();
    state.allocator = allocator;

    var sprite_frames: []FrameMetadata = undefined;
    defer {
        for (sprite_frames) |sprite_frame| {
            allocator.free(sprite_frame.name);
        }
        allocator.free(sprite_frames);
    }

    initSpriteFrames(allocator, &sprite_frames) catch unreachable;

    // convert metadata to actual sprite frames and populate state with it
    state.sprite_frames = getSpriteFramesFromMetadata(allocator, sprite_frames, image.width, image.height) catch unreachable;

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
    state.updateFrames();
    updateVertexUVs(state.sprite_frames[state.current_sframe]);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.deinit();
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
