const std = @import("std");
const assert = std.debug.assert;

pub fn Outcome(comptime TResult: anytype, comptime TFailure: anytype, comptime TResultDeinit: [:0]const u8, comptime TFailureDeinit: [:0]const u8) type {
    const ResultTag = enum {
        s,
        f,
    };
    const Result = union(ResultTag) { s: TResult, f: TFailure };
    return struct {
        success: bool = false,
        res: Result = undefined,

        const Self = @This();

        fn destructor(self: *Self) void {
            switch (self.res) {
                ResultTag.s => if (TResultDeinit.len > 0) {
                    @call(.{}, @field(self.res.s, TResultDeinit), .{});
                },
                ResultTag.f => if (TFailureDeinit.len > 0) {
                    @call(.{}, @field(self.res.f, TFailureDeinit), .{});
                },
            }
        }

        pub fn deinit(self: *Self) void {
            self.destructor();
            self.success = false;
            self.res = undefined;
            self.* = undefined;
        }

        pub fn init(types: anytype, args: anytype) Self {
            // Only one arg either TResult, *TResult, TFailure, *TFailure, Outcome, *Outcome
            if ((types.len != args.len) or types.len > 1) {
                @compileError("no matching constructor for initialization of " ++ @typeName(Self));
            }
            if (@typeInfo(@TypeOf(types)) != .Struct) {
                @compileError("Expected tuple or struct argument, found " ++ @typeName(@TypeOf(types)));
            }
            if (@typeInfo(@TypeOf(args)) != .Struct) {
                @compileError("Expected tuple or struct argument, found " ++ @typeName(@TypeOf(args)));
            }

            // only one arg in this case
            const arg_0_type = types.@"0";
            if (arg_0_type == TResult) {
                return Self{
                    .success = true,
                    .res = Result{ .s = args[0] },
                };
            } else if (arg_0_type == *TResult) {
                return Self{
                    .success = true,
                    .res = Result{ .s = args[0].* },
                };
            } else if (arg_0_type == TFailure) {
                return Self{
                    .success = false,
                    .res = Result{ .f = args[0] },
                };
            } else if (arg_0_type == *TFailure) {
                return Self{
                    .success = false,
                    .res = Result{ .f = args[0].* },
                };
            }

            // passing Outcome struct - we must pass pointer
            if (comptime std.mem.eql(u8, @typeName(*Self), @typeName(arg_0_type))) { // if error pass the pointer as type

                // arg[0].* is Outcome
                if (args[0].*.isSuccess()) {
                    return Self{
                        .success = true,
                        .res = Result{ .s = args[0].*.getResult() },
                    };
                } else {
                    return Self{
                        .success = false,
                        .res = Result{ .f = args[0].*.getFailure() },
                    };
                }
            }

            @compileError("no matching constructor for initialization of " ++ @typeName(Self));
        }

        pub fn isSuccess(self: *Self) bool {
            return self.success;
        }

        pub fn getResult(self: *Self) TResult {
            assert(self.success);
            return self.res.s;
        }

        pub fn getFailure(self: *Self) TFailure {
            assert(!self.success);
            return self.res.f;
        }
    };
}

test "Outcome <TResult, TFailure> - isSuccess" {
    const Stringi32Outcome = Outcome([:0]const u8, i32, "", "");
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    var s = Stringi32Outcome.init(.{[:0]const u8}, .{"Success"});
    defer s.deinit();
    var s1 = Stringi32Outcome.init(.{*Stringi32Outcome}, .{&s});
    defer s1.deinit();
    try expect(s.isSuccess());
    try expect(s1.isSuccess());
    try expect(eql(u8, s.getResult(), "Success"));
    try expect(eql(u8, s1.getResult(), "Success"));
}

test "Outcome <TResult, TFailure> - isFailure" {
    const Stringi32Outcome = Outcome([:0]const u8, i32, "", "");
    const expect = std.testing.expect;
    var f = Stringi32Outcome.init(.{i32}, .{42});
    defer f.deinit();
    var f1 = Stringi32Outcome.init(.{*Stringi32Outcome}, .{&f});
    defer f1.deinit();
    try expect(!f.isSuccess());
    try expect(!f1.isSuccess());
    try expect(f.getFailure() == 42);
    try expect(f1.getFailure() == 42);
}

test "Outcome <TResult, TFailure> - calling child destructor" {
    const expect = std.testing.expect;
    const S = struct {
        i: i32 = 0,
        const Self = @This();
        fn destruct(self: *Self) void {
            // self is a mandatory arg due to @call
            self.i = -1;
            self.* = undefined;
        }

        fn hello(self: *Self) i32 {
            return self.i;
        }
    };
    const SBoolOutcome = Outcome(S, bool, "destruct", "");
    var s = SBoolOutcome.init(.{S}, .{S{ .i = 1 }});
    try expect(s.isSuccess());
    var result: S = s.getResult();
    try expect(result.hello() == 1);
    s.deinit();
    try expect(!s.isSuccess()); // default value false when reinitialized.
    var f = SBoolOutcome.init(.{bool}, .{true});
    defer f.deinit();
    try expect(!f.isSuccess());
}
