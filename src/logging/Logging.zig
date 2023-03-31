const Logging = @This();
const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");
const allocPrintZ = std.fmt.allocPrintZ;
const bufferedWriter = std.io.bufferedWriter;
const Level = std.log.Level;
const Allocator = std.mem.Allocator;
const ArgSetType = u32;
const max_format_args = @typeInfo(ArgSetType).Int.bits;
const max_stack_buffer_size: usize = 512;

allocator: Allocator = undefined,

pub fn init(allocator: Allocator) Logging {
    const self = Logging{
        .allocator = allocator,
    };
    return self;
}

pub fn deinit(self: *Logging) void {
    self.* = undefined;
}

fn getPrefix(level: Level) [:0]const u8 {
    switch (level) {
        .debug => return "[DEBUG]",
        .info => return "[INFO]",
        .warn => return "[WARNING]",
        .err => return "[ERROR]",
    }
}

pub fn log(self: *Logging, comptime level: Level, comptime tag: [:0]const u8, comptime fmt: [:0]const u8, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("Expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }
    const fields_info = args_type_info.Struct.fields;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    const args_text: [:0]const u8 = std.fmt.allocPrintZ(self.allocator, fmt, args) catch {
        std.io.getStdErr().writer().print("error occurred during log formatting!\n", .{}) catch unreachable;
        return;
    };
    defer self.allocator.free(args_text);

    const writer = std.io.getStdErr().writer();
    var buffered_writer = bufferedWriter(writer);
    var stdout_writer = buffered_writer.writer();

    stdout_writer.print(getPrefix(level) ++ " " ++ "[{d}]", .{@intCast(u64, std.time.milliTimestamp())}) catch unreachable;
    stdout_writer.print(" " ++ tag ++ " ", .{}) catch unreachable;

    // clamp arg text to max stack buffer size
    if (args_text.len > max_stack_buffer_size) {
        stdout_writer.writeAll(args_text[0..max_stack_buffer_size]) catch unreachable;
    } else {
        stdout_writer.writeAll(args_text) catch unreachable;
    }

    // /n
    stdout_writer.print("\n", .{}) catch unreachable;

    buffered_writer.flush() catch {
        std.io.getStdErr().writer().print("ERROR: could not write buffered log data to stdout\n", .{}) catch unreachable;
    };
}

pub fn logInfo(self: *Logging, comptime tag: [:0]const u8, comptime fmt: [:0]const u8, args: anytype) void {
    self.log(Level.info, tag, fmt, args);
}

pub fn logDebug(self: *Logging, comptime tag: [:0]const u8, comptime fmt: [:0]const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        self.log(Level.debug, tag, fmt, args);
    }
}

pub fn logError(self: *Logging, comptime tag: [:0]const u8, comptime fmt: [:0]const u8, args: anytype) void {
    self.log(Level.err, tag, fmt, args);
}

test "Logging getPrefix" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    try expect(eql(u8, getPrefix(Level.info), "[INFO]"));
    try expect(eql(u8, getPrefix(Level.debug), "[DEBUG]"));
    try expect(eql(u8, getPrefix(Level.warn), "[WARNING]"));
    try expect(eql(u8, getPrefix(Level.err), "[ERROR]"));
}

test "Logging log" {
    const test_allocator = std.testing.allocator;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    l.log(Level.info, "TAG", "MSG: {d} - {s} - {}", .{ 0, "ARG", .z });
}
