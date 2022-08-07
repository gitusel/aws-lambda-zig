const std = @import("std");
const aws_lambda_zig_version = @import("build_options").aws_lambda_zig_version;

pub fn getVersionMajor() u32 {
    return aws_lambda_zig_version.major;
}

pub fn getVersionMinor() u32 {
    return aws_lambda_zig_version.minor;
}

pub fn getVersionPatch() u32 {
    return aws_lambda_zig_version.patch;
}

pub fn getVersion() [:0]const u8 {
    return std.fmt.comptimePrint("\"{d}.{d}.{d}\"", .{ aws_lambda_zig_version.major, aws_lambda_zig_version.minor, aws_lambda_zig_version.patch });
}

test "version getVersion" {
    const expect = std.testing.expect;
    try expect(getVersionMajor() >= 0);
    try expect(getVersionMinor() >= 0);
    try expect(getVersionPatch() >= 0);
    try expect(getVersion().len >= 0);
}
