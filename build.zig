const std = @import("std");
const Build = if (@hasDecl(std, "Build")) std.Build else std.build.Builder;
const Module = if (@hasDecl(std, "Build")) std.Build.Module else std.build.Pkg;
const Version = std.builtin.Version;
const Os = std.Target.Os;
const CompileStep = if (@hasDecl(Build, "standardOptimizeOption")) Build.CompileStep else std.build.LibExeObjStep;
const aws_lambda_zig_version = Version{ .major = 0, .minor = 0, .patch = 0 };

pub fn getBuildModule(b: *Build) if (@hasDecl(std, "Build")) *Module else Module {
    if (@hasDecl(std, "Build")) {
        return b.createModule(.{
            .source_file = .{ .path = getFullPath("/src/aws.zig") },
            .dependencies = &.{
                .{ .name = "build_options", .module = getBuildOptionsModule(b) },
            },
        });
    } else {
        return Module{
            .name = "aws",
            .source = .{ .path = getFullPath("/src/aws.zig") },
            .dependencies = b.allocator.dupe(Module, &[1]Module{getBuildOptionsModule(b)}) catch null,
        };
    }
}

fn getBuildOptionsModule(b: *Build) if (@hasDecl(std, "Build")) *Module else Module {
    const build_options_step = if (@hasDecl(std, "Build")) Build.OptionsStep.create(b) else std.build.OptionsStep.create(b);
    build_options_step.addOption(Version, "aws_lambda_zig_version", aws_lambda_zig_version);
    return if (@hasDecl(std, "Build")) build_options_step.createModule() else build_options_step.getPackage("build_options");
}

pub fn build(b: *Build) void {
    // Standard optimize options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});

    var lib_tests: *CompileStep = undefined;
    if (@hasDecl(Build, "standardOptimizeOption")) {
        lib_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/aws.zig" },
            .target = target,
            .optimize = b.standardOptimizeOption(.{}),
        });
        lib_tests.addModule("build_options", getBuildOptionsModule(b));
    } else {
        lib_tests = b.addTest("src/aws.zig");
        lib_tests.setBuildMode(b.standardReleaseOptions());
        lib_tests.setTarget(target);
        lib_tests.addPackage(getBuildOptionsModule(b));
    }

    lib_tests.linkLibC();
    lib_tests.linkSystemLibrary("curl");

    const test_step = b.step("test", "Run library tests");

    if (@hasDecl(Build, "addRunArtifact")) {
        test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    } else {
        test_step.dependOn(&lib_tests.step);
    }

    // from https://zig.news/squeek502/code-coverage-for-zig-1dk1
    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    if (coverage) {
        lib_tests.setExecCmd(&[_]?[]const u8{
            "kcov",
            "--include-pattern=/src/",
            "kcov-output", // output dir for kcov
            null, // to get zig to use the --test-cmd-bin flag
        });
    }
}

// from https://zig.news/xq/cool-zig-patterns-paths-in-build-scripts-4p59
fn getFullPath(comptime path: [:0]const u8) [:0]const u8 {
    return comptime blk: {
        const this_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk this_dir ++ path;
    };
}
