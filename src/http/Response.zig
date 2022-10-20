const Response = @This();
const std = @import("std");
const ArrayList = std.ArrayList;
const allocPrintZ = std.fmt.allocPrintZ;
const Allocator = std.mem.Allocator;
const Kvs = @import("Kvs.zig");
const Logging = @import("../logging/Logging.zig");
const Outcome = @import("../lambda_runtime/Outcome.zig").Outcome;
const ResponseCode = @import("ResponseCode.zig").ResponseCode;
const StringBoolOutcome = Outcome([:0]const u8, bool, "", "");

allocator: Allocator = undefined,
logging: Logging = undefined,
MIN_CAPACITY: usize = 0, // c-string type for Zig so empty string is of size 0 + null character
response_code: ResponseCode = undefined,
content_type: ?[:0]const u8 = null,
body: [:0]u8 = undefined,
headers: Kvs = undefined,

pub fn init(allocator: Allocator, logging: Logging) !Response {
    var self = Response{
        .allocator = allocator,
    };
    errdefer self.deinit();
    self.headers = Kvs.init(self.allocator);
    self.body = try self.allocator.allocSentinel(u8, self.MIN_CAPACITY, 0);
    self.logging = logging;
    return self;
}

pub fn deinit(self: *Response) void {
    self.headers.deinit();
    self.allocator.free(self.body);
    if (self.content_type) |content_type| self.allocator.free(content_type);
    self.* = undefined;
}

pub fn setResponseCode(self: *Response, response_code: ResponseCode) void {
    self.response_code = response_code;
}

pub fn getResponseCode(self: *const Response) ResponseCode {
    return self.response_code;
}

pub fn setContentType(self: *Response, content_type: [:0]const u8) !void {
    if (content_type.len > 0) {
        self.content_type = try allocPrintZ(self.allocator, "{s}", .{content_type});
    }
}

pub fn getContentType(self: *Response) ?[:0]const u8 {
    return self.content_type;
}

pub fn hasHeader(self: *Response, header: [:0]const u8) bool {
    return self.headers.contains(header);
}

pub fn addHeader(self: *Response, header: []const u8, value: []const u8) !void {
    try self.headers.set(header, value);
}

pub fn getHeader(self: *Response, header: [:0]const u8) StringBoolOutcome {
    var outcome: StringBoolOutcome = undefined;
    if (self.headers.contains(header)) {
        outcome = StringBoolOutcome.init(.{[:0]const u8}, .{self.headers.get(header).?});
    } else {
        outcome = StringBoolOutcome.init(.{bool}, .{false});
    }
    return outcome;
}

pub fn getBody(self: *const Response) ?[:0]const u8 {
    return self.body;
}

pub fn appendBody(self: *Response, text: []const u8) !void {
    const body: [:0]u8 = try std.mem.concatWithSentinel(self.allocator, u8, &[_][]const u8{ self.body, text }, 0);
    self.allocator.free(self.body);
    self.body = body;
}

test "Response init/deinit" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    var r = try Response.init(test_allocator, l);
    defer r.deinit();
    try expect(r.body.len == r.MIN_CAPACITY);
}

test "Response set/getResponseCode" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    var res = try Response.init(test_allocator, l);
    defer res.deinit();

    res.setResponseCode(ResponseCode.ACCEPTED);
    try expect(res.getResponseCode() == ResponseCode.ACCEPTED);
}

test "Response set/getContentType" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_allocator = std.testing.allocator;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    var res = try Response.init(test_allocator, l);
    defer res.deinit();

    try res.setContentType("application/json");
    try expect(eql(u8, res.getContentType().?, "application/json"));
}

test "Response append/getBody" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_allocator = std.testing.allocator;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    var res = try Response.init(test_allocator, l);
    defer res.deinit();

    try res.appendBody("BODY BODY BODY");

    try expect(eql(u8, res.getBody().?, "BODY BODY BODY"));
}

test "Response add/has/getHeader" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    var l = Logging.init(test_allocator);
    defer l.deinit();
    var res = try Response.init(test_allocator, l);
    defer res.deinit();

    try res.addHeader("HEADER", "VALUE");

    try expect(res.hasHeader("header"));
    try expect(res.hasHeader("noheader") == false);

    var t = res.getHeader("HEADER");
    try expect(t.isSuccess());
    t = res.getHeader("noheader");
    try expect(!t.isSuccess());
}
