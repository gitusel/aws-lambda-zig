const std = @import("std");
const Build = if (@hasDecl(std, "Build")) std.Build else std.build.Builder;
const OptimizeMode = if (@hasDecl(Build, "standardOptimizeOption")) std.builtin.OptimizeMode else std.builtin.Mode;
const CompileStep = if (@hasDecl(Build, "standardOptimizeOption")) std.build.CompileStep else std.build.LibExeObjStep;
const RunStep = std.build.RunStep;
const allocPrint = std.fmt.allocPrint;
const CrossTarget = std.zig.CrossTarget;
const builtin = @import("builtin");

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = if (@hasDecl(Build, "standardOptimizeOption")) b.standardOptimizeOption(.{}) else b.standardReleaseOptions();
    if (target.cpu_arch != null) {
        var examples: []*CompileStep = &[_]*CompileStep{
            makeExample(b, optimize, target, "hello_world", "examples/hello_world.zig"),
            makeExample(b, optimize, target, "echo_bin", "examples/echo_bin.zig"),
            makeExample(b, optimize, target, "echo_failure", "examples/echo_failure.zig"),
            makeExample(b, optimize, target, "pass_arg", "examples/pass_arg.zig"),
        };
        for (examples) |example| {
            example.install();
            const pack_example = packageBinary(b, example.name);
            pack_example.step.dependOn(&example.step);
            b.default_step.dependOn(&pack_example.step);
        }
    } else {
        makeLocalExample(b, optimize, target, "hello_world", "examples/hello_world.zig");
        makeLocalExample(b, optimize, target, "echo_bin", "examples/echo_bin.zig");
        makeLocalExample(b, optimize, target, "echo_failure", "examples/echo_failure.zig");
        makeLocalExample(b, optimize, target, "pass_arg", "examples/pass_arg.zig");
    }
}

fn makeLocalExample(b: *Build, optimize: OptimizeMode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) void {
    // adding aws_lambda_runtime
    const aws_pkg = @import("build.zig").getBuildPkg(b);
    defer b.allocator.free(aws_pkg.dependencies.?);

    var example: *CompileStep = undefined;
    if (@hasDecl(Build, "standardOptimizeOption")) {
        example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = example_path },
            .optimize = optimize,
            .target = target,
        });
    } else {
        example = b.addExecutable(example_name, example_path);
        example.setBuildMode(b.standardReleaseOptions());
        example.setTarget(target);
    }

    example.addPackage(aws_pkg);
    example.linkLibC();
    example.linkSystemLibrary("curl");
    example.install();
}

fn makeExample(b: *Build, optimize: OptimizeMode, target: CrossTarget, example_name: [:0]const u8, example_path: [:0]const u8) *CompileStep {
    // adding aws_lambda_runtime
    const aws_pkg = @import("build.zig").getBuildPkg(b);
    defer b.allocator.free(aws_pkg.dependencies.?);

    var example: *CompileStep = undefined;

    if (@hasDecl(Build, "standardOptimizeOption")) {
        example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = example_path },
            .optimize = optimize,
            .target = target,
        });
        if (optimize == .ReleaseSmall) {
            example.strip = true;
        }
    } else {
        example = b.addExecutable(example_name, example_path);
        example.setBuildMode(b.standardReleaseOptions());
        example.setTarget(target);
    }

    example.addPackage(aws_pkg);
    example.linkLibC();
    example.addIncludePath(getPath("/deps/include/"));
    addStaticLib(example, "libbrotlicommon.a");
    addStaticLib(example, "libbrotlidec.a");
    addStaticLib(example, "libcrypto.a");
    addStaticLib(example, "libssl.a");
    addStaticLib(example, "libz.a");
    addStaticLib(example, "libnghttp2.a");
    addStaticLib(example, "libcurl.a");

    return example;
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

fn addStaticLib(compileStep: *CompileStep, staticLibName: [:0]const u8) void {
    if (compileStep.target.cpu_arch.?.isAARCH64()) {
        compileStep.addObjectFile(allocPrint(compileStep.builder.allocator, "{s}/deps/{s}/{s}", .{ thisDir(), "lib_aarch64", staticLibName }) catch unreachable);
    } else {
        compileStep.addObjectFile(allocPrint(compileStep.builder.allocator, "{s}/deps/{s}/{s}", .{ thisDir(), "lib_x86_64", staticLibName }) catch unreachable);
    }
}

fn dirExists(path: [:0]const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn packageBinary(b: *Build, package_name: []const u8) *RunStep {
    if (!dirExists(getPath("/runtime"))) {
        std.fs.cwd().makeDir(getPath("/runtime")) catch unreachable;
    }
    const package_path = allocPrint(b.allocator, "../zig-out/bin/{s}", .{package_name}) catch unreachable;
    var run_pakager: *RunStep = undefined;

    if (builtin.os.tag != .windows) {
        const packager_script = "../packaging/packager";
        run_pakager = b.addSystemCommand(&[_][]const u8{ packager_script, package_path });
    } else {
        const packager_script = "../packaging/packager.ps1";
        run_pakager = b.addSystemCommand(&[_][]const u8{ "powershell", packager_script, package_path });
    }
    run_pakager.cwd = getPath("/runtime");
    return run_pakager;
}
