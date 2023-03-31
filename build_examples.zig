const std = @import("std");
const Build = if (@hasDecl(std, "Build")) std.Build else std.build.Builder;
const OptimizeMode = if (@hasDecl(Build, "standardOptimizeOption")) std.builtin.OptimizeMode else std.builtin.Mode;
const CompileStep = if (@hasDecl(Build, "standardOptimizeOption")) std.build.CompileStep else std.build.LibExeObjStep;
const InstallArtifactStep = std.build.InstallArtifactStep;
const RunStep = std.build.RunStep;
const allocPrint = std.fmt.allocPrint;
const CrossTarget = std.zig.CrossTarget;
const builtin = @import("builtin");

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = if (@hasDecl(Build, "standardOptimizeOption")) b.standardOptimizeOption(.{}) else b.standardReleaseOptions();
    if (target.cpu_arch != null) {
        makeExample(b, optimize, target, "hello_world", "examples/hello_world.zig");
        makeExample(b, optimize, target, "echo_bin", "examples/echo_bin.zig");
        makeExample(b, optimize, target, "echo_failure", "examples/echo_failure.zig");
        makeExample(b, optimize, target, "pass_arg", "examples/pass_arg.zig");
    } else {
        makeLocalExample(b, optimize, target, "hello_world", "examples/hello_world.zig");
        makeLocalExample(b, optimize, target, "echo_bin", "examples/echo_bin.zig");
        makeLocalExample(b, optimize, target, "echo_failure", "examples/echo_failure.zig");
        makeLocalExample(b, optimize, target, "pass_arg", "examples/pass_arg.zig");
    }
}

fn makeLocalExample(b: *Build, optimize: OptimizeMode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) void {
    // adding aws_lambda_runtime
    const aws_module = @import("build.zig").getBuildModule(b);
    defer if (!@hasDecl(std, "Build")) {
        b.allocator.free(aws_module.dependencies.?);
    };

    var example: *CompileStep = undefined;
    if (@hasDecl(Build, "standardOptimizeOption")) {
        example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = example_path },
            .optimize = optimize,
            .target = target,
        });
        example.addModule("aws", aws_module);
    } else {
        example = b.addExecutable(example_name, example_path);
        example.setBuildMode(b.standardReleaseOptions());
        example.setTarget(target);
        example.addPackage(aws_module);
    }
    example.linkLibC();
    example.linkSystemLibrary("curl");
    b.installArtifact(example);
}

fn makeExample(b: *Build, optimize: OptimizeMode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) void {
    // adding aws_lambda_runtime
    const aws_module = @import("build.zig").getBuildModule(b);
    defer if (!@hasDecl(std, "Build")) {
        b.allocator.free(aws_module.dependencies.?);
    };

    var example: *CompileStep = undefined;

    if (@hasDecl(Build, "standardOptimizeOption")) {
        example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = example_path },
            .optimize = optimize,
            .target = target,
        });
        example.addModule("aws", aws_module);
        if (optimize == .ReleaseSmall) {
            example.strip = true;
        }
    } else {
        example = b.addExecutable(example_name, example_path);
        example.setBuildMode(b.standardReleaseOptions());
        example.setTarget(target);
        example.addPackage(aws_module);
    }

    example.linkLibC();
    example.addIncludePath(getPath("/deps/include/"));
    addStaticLib(b, example, "libbrotlicommon.a");
    addStaticLib(b, example, "libbrotlidec.a");
    addStaticLib(b, example, "libcrypto.a");
    addStaticLib(b, example, "libssl.a");
    addStaticLib(b, example, "libz.a");
    addStaticLib(b, example, "libnghttp2.a");
    addStaticLib(b, example, "libcurl.a");

    packageBinary(b, example);
}

fn thisDir() []const u8 {
    return comptime blk: {
        const src = @src();
        const root_dir = std.fs.path.dirname(src.file) orelse ".";
        break :blk root_dir;
    };
}

// from https://zig.news/xq/cool-zig-patterns-paths-in-build-scripts-4p59
fn getPath(comptime path: [:0]const u8) [:0]const u8 {
    return comptime blk: {
        break :blk thisDir() ++ path;
    };
}

fn addStaticLib(b: *Build, compileStep: *CompileStep, staticLibName: [:0]const u8) void {
    if (compileStep.target.cpu_arch.?.isAARCH64()) {
        compileStep.addObjectFile(allocPrint(b.allocator, "{s}/deps/{s}/{s}", .{ thisDir(), "lib_aarch64", staticLibName }) catch unreachable);
    } else {
        compileStep.addObjectFile(allocPrint(b.allocator, "{s}/deps/{s}/{s}", .{ thisDir(), "lib_x86_64", staticLibName }) catch unreachable);
    }
}

fn dirExists(path: [:0]const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn packageBinary(b: *Build, example: *CompileStep) void {
    if (!dirExists(getPath("/runtime"))) {
        std.fs.cwd().makeDir(getPath("/runtime")) catch unreachable;
    }
    var run_packager: *RunStep = undefined;
    const package_path = allocPrint(b.allocator, "../zig-out/bin/{s}", .{example.name}) catch unreachable;

    if (builtin.os.tag != .windows) {
        const packager_script = "../packaging/packager";
        run_packager = b.addSystemCommand(&[_][]const u8{ packager_script, package_path });
    } else {
        const packager_script = "../packaging/packager.ps1";
        run_packager = b.addSystemCommand(&[_][]const u8{ "powershell", packager_script, package_path });
    }
    run_packager.cwd = getPath("/runtime");
    run_packager.step.dependOn(&InstallArtifactStep.create(b, example).step);
    b.default_step.dependOn(&run_packager.step);
}
