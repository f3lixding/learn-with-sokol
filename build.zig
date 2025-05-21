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
            build_bin(b, .{
                .name = name,
                .path = path,
            }, sokol_dep, target, optimize);
        }
    }
}

/// This also constructs the run step for said bin
pub fn build_bin(b: *Build, bin: Bin, sd: *Build.Dependency, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const bin_to_add = b.addExecutable(.{
        .name = bin.name,
        .target = target,
        .optimize = optimize,
        .root_source_file = bin.path,
    });
    bin_to_add.root_module.addImport("sokol", sd.module("sokol"));
    const selective_install = b.addInstallArtifact(bin_to_add, .{});
    const run = b.addRunArtifact(bin_to_add);

    b.installArtifact(bin_to_add);

    b.step(b.fmt("run-{s}", .{bin.name}), b.fmt("run {s}", .{bin.name})).dependOn(&run.step);
    b.step(b.fmt("build-{s}", .{bin.name}), b.fmt("build {s}", .{bin.name})).dependOn(&selective_install.step);
}
