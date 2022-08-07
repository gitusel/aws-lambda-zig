const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;
const Version = std.builtin.Version;
const Os = std.Target.Os;

const aws_lambda_zig_version = Version{ .major = 0, .minor = 0, .patch = 0 };

pub fn getBuildPkg(b: *Builder) Pkg {
    return Pkg{
        .name = "aws",
        .source = .{ .path = thisDir() ++ "/src/aws.zig" },
        .dependencies = b.allocator.dupe(Pkg, &[_]Pkg{getBuildOptionsPkg(b)}) catch null,
    };
}

fn getBuildOptionsPkg(b: *Builder) Pkg {
    const build_options_step = std.build.OptionsStep.create(b);
    build_options_step.addOption(Version, "aws_lambda_zig_version", aws_lambda_zig_version);
    return build_options_step.getPackage("build_options");
}

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib_tests = b.addTest("src/aws.zig");
    lib_tests.setBuildMode(mode);
    lib_tests.setTarget(target);
    lib_tests.linkLibC();
    lib_tests.linkSystemLibrary("curl");
    lib_tests.addPackage(getBuildOptionsPkg(b));

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&lib_tests.step);

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

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
