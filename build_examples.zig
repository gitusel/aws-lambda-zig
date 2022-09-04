const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const RunStep = std.build.RunStep;
const Step = std.build.Step;
const Mode = std.builtin.Mode;
const allocPrint = std.fmt.allocPrint;
const CrossTarget = std.zig.CrossTarget;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    if (target.cpu_arch != null) {
        var examples: []*LibExeObjStep = &.{
            makeExample(b, mode, target, "hello_world", "examples/hello_world.zig"),
            makeExample(b, mode, target, "echo_bin", "examples/echo_bin.zig"),
            makeExample(b, mode, target, "echo_failure", "examples/echo_failure.zig"),
            makeExample(b, mode, target, "pass_arg", "examples/pass_arg.zig"),
        };
        for (examples) |example| {
            example.install();
            const pack_example = packageBinary(b, example.name);
            pack_example.step.dependOn(&example.step);
            b.default_step.dependOn(&pack_example.step);
        }
    } else {
        makeLocalExample(b, mode, target, "hello_world", "examples/hello_world.zig");
        makeLocalExample(b, mode, target, "echo_bin", "examples/echo_bin.zig");
        makeLocalExample(b, mode, target, "echo_failure", "examples/echo_failure.zig");
        makeLocalExample(b, mode, target, "pass_arg", "examples/pass_arg.zig");
    }
}

fn makeLocalExample(b: *Builder, mode: Mode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) void {
    // adding aws_lambda_runtime
    const aws_pkg = @import("build.zig").getBuildPkg(b);
    defer b.allocator.free(aws_pkg.dependencies.?);

    const example = b.addExecutable(example_name, example_path);
    example.setTarget(target);
    example.setBuildMode(mode);
    example.addPackage(aws_pkg);
    example.linkLibC();
    example.linkSystemLibrary("curl");
    example.install();
}

fn makeExample(b: *Builder, mode: Mode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) *LibExeObjStep {
    // adding aws_lambda_runtime
    const aws_pkg = @import("build.zig").getBuildPkg(b);
    defer b.allocator.free(aws_pkg.dependencies.?);

    const example = b.addExecutable(example_name, example_path);
    example.setTarget(target);
    example.setBuildMode(mode);
    example.addPackage(aws_pkg);
    example.linkLibC();
    example.addIncludePath(getFullPath("/deps/include/"));
    addStaticLib(example, "libbrotlicommon.a");
    addStaticLib(example, "libbrotlidec.a");
    addStaticLib(example, "libcrypto.a");
    addStaticLib(example, "libssl.a");
    addStaticLib(example, "libz.a");
    addStaticLib(example, "libnghttp2.a");
    addStaticLib(example, "libcurl.a");

    if (mode == .ReleaseSmall) {
        example.strip = true;
    }
    return example;
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

// from https://zig.news/xq/cool-zig-patterns-paths-in-build-scripts-4p59
fn getFullPath(comptime path: [:0]const u8) [:0]const u8 {
    return comptime thisDir() ++ path;
}

fn addStaticLib(libExeObjStep: *LibExeObjStep, staticLibName: [:0]const u8) void {
    if (libExeObjStep.target.cpu_arch.?.isAARCH64()) {
        libExeObjStep.addObjectFile(allocPrint(libExeObjStep.builder.allocator, "{s}/deps/{s}/{s}", .{ comptime thisDir(), "lib_aarch64", staticLibName }) catch unreachable);
    } else {
        libExeObjStep.addObjectFile(allocPrint(libExeObjStep.builder.allocator, "{s}/deps/{s}/{s}", .{ comptime thisDir(), "lib_x86_64", staticLibName }) catch unreachable);
    }
}

fn dirExists(path: [:0]const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

fn packageBinary(b: *Builder, package_name: []const u8) *RunStep {
    if (!dirExists(getFullPath("/runtime"))) {
        std.fs.makeDirAbsolute(getFullPath("/runtime")) catch unreachable;
    }
    const package_path = allocPrint(b.allocator, "{s}/zig-out/bin/{s}", .{ comptime thisDir(), package_name }) catch unreachable;
    var run_pakager: *RunStep = undefined;

    if (builtin.os.tag != .windows) {
        const packager_script = getFullPath("/packaging/packager");
        run_pakager = b.addSystemCommand(&[_][]const u8{ packager_script, package_path });
    } else {
        const packager_script = getFullPath("/packaging/packager.ps1");
        run_pakager = b.addSystemCommand(&[_][]const u8{ "powershell", packager_script, package_path });
    }
    run_pakager.cwd = getFullPath("/runtime");
    return run_pakager;
}
