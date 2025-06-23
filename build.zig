const std = @import("std");
const Build = std.Build;
const Entry = std.fs.Dir.Walker.Entry;

const Bin = struct {
    name: []const u8,
    path: Build.LazyPath,
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const src_dir = std.fs.cwd().openDir("src", .{ .iterate = true }) catch unreachable;
    var walker = src_dir.walk(b.allocator) catch unreachable;
    var shader_dir = src_dir.openDir("shaders", .{}) catch unreachable;
    defer walker.deinit();
    while (walker.next() catch unreachable) |file| {
        if (std.mem.eql(u8, ".zig", std.fs.path.extension(file.path))) {
            const name = std.fs.path.stem(file.basename);
            const path = b.path(b.fmt("src/{s}", .{file.path}));
            if (std.mem.startsWith(u8, file.path, "shaders/") or std.mem.eql(u8, name, "math")) {
                continue;
            }
            build_bin(
                b,
                .{
                    .name = name,
                    .path = path,
                },
                sokol_dep,
                zigimg_dep,
                target,
                optimize,
                &shader_dir,
                no_bin,
            );
        }
    }
}

/// This also constructs the run step for said bin
pub fn build_bin(
    b: *Build,
    bin: Bin,
    sd: *Build.Dependency,
    imgd: *Build.Dependency,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shader_dir: *std.fs.Dir,
    no_bin: bool,
) void {
    const bin_to_add = b.addExecutable(.{
        .name = bin.name,
        .target = target,
        .optimize = optimize,
        .root_source_file = bin.path,
    });

    // We should build the generated shader file either way
    // But we would only do it if the zig file is out of date
    const bin_name = bin.name;
    if (shader_dir.statFile(b.fmt("{s}.glsl", .{bin_name}))) |gl_stat| {
        const zig_file_out_of_date = date: {
            if (shader_dir.statFile(b.fmt("{s}.glsl.zig", .{bin_name}))) |zig_stat| {
                const gl_last_mod = gl_stat.mtime;
                const zig_last_mod = zig_stat.mtime;
                break :date gl_last_mod > zig_last_mod;
            } else |_| {
                break :date true;
            }
        };

        if (zig_file_out_of_date) {
            const run_command = run_sokol_shdc(b, bin_name);
            bin_to_add.step.dependOn(&run_command.step);
        }
    } else |_| {
        // ignore, assume file does not exist
    }

    bin_to_add.root_module.addImport("sokol", sd.module("sokol"));
    bin_to_add.root_module.addImport("zigimg", imgd.module("zigimg"));
    const selective_install = b.addInstallArtifact(bin_to_add, .{});
    const run = b.addRunArtifact(bin_to_add);

    // Overall installs
    if (no_bin) {
        b.getInstallStep().dependOn(&bin_to_add.step);
    } else {
        b.installArtifact(bin_to_add);
    }

    b.step(
        b.fmt("run-{s}", .{bin.name}),
        b.fmt("run {s}", .{bin.name}),
    ).dependOn(&run.step);
    const build_step = b.step(
        b.fmt("build-{s}", .{bin.name}),
        b.fmt("build {s}", .{bin.name}),
    );
    if (no_bin) {
        // Note that *Compile step is enough to run check
        // (You don't need install for checking)
        build_step.dependOn(&bin_to_add.step);
    } else {
        build_step.dependOn(&selective_install.step);
    }
}

pub fn run_sokol_shdc(
    b: *Build,
    name: []const u8,
) *Build.Step.Run {
    const sokol_shdc = b.addSystemCommand(&.{
        "sokol-shdc",
        "-i",
        b.fmt("src/shaders/{s}.glsl", .{name}),
        "-o",
        b.fmt("src/shaders/{s}.glsl.zig", .{name}),
        "-l",
        "glsl410:glsl300es:hlsl5:metal_macos:wgsl",
        "-f",
        "sokol_zig",
    });

    return sokol_shdc;
}
