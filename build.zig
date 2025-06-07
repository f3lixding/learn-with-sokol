const std = @import("std");
const Build = std.Build;

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

    const src_dir = std.fs.cwd().openDir("src", .{ .iterate = true }) catch unreachable;
    var walker = src_dir.walk(b.allocator) catch unreachable;
    defer walker.deinit();
    while (walker.next() catch unreachable) |file| {
        if (std.mem.eql(u8, ".zig", std.fs.path.extension(file.path))) {
            const name = std.fs.path.stem(file.basename);
            const path = b.path(b.fmt("src/{s}", .{file.path}));
            if (std.mem.startsWith(u8, file.path, "shaders/") or std.mem.eql(u8, name, "math")) {
                continue;
            }
            build_bin(b, .{
                .name = name,
                .path = path,
            }, sokol_dep, target, optimize, no_bin);
        }
    }
}

/// This also constructs the run step for said bin
pub fn build_bin(
    b: *Build,
    bin: Bin,
    sd: *Build.Dependency,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    no_bin: bool,
) void {
    const bin_to_add = b.addExecutable(.{
        .name = bin.name,
        .target = target,
        .optimize = optimize,
        .root_source_file = bin.path,
    });
    bin_to_add.root_module.addImport("sokol", sd.module("sokol"));
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
