const InvocationResponse = @This();
const std = @import("std");
const allocPrintZ = std.fmt.allocPrintZ;
const Allocator = std.mem.Allocator;

allocator: Allocator = undefined,
arg_error_type_escaped: ?[:0]const u8 = null,
arg_error_message_escaped: ?[:0]const u8 = null,

//
// The output of the function which is sent to the lambda caller.
//
payload: ?[:0]const u8 = null,

//
// The MIME type of the payload.
// This is always set to 'application/json' in unsuccessful invocations.
//
content_type: ?[:0]const u8 = null,

//
// Flag to distinguish if the contents are for successful or unsuccessful invocations.
//
success: bool = false,

fn initWithDefault(allocator: Allocator) InvocationResponse {
    return InvocationResponse{
        .allocator = allocator,
    };
}

pub fn deinit(self: *InvocationResponse) void {
    if (self.payload) |payload| self.allocator.free(payload);
    if (self.content_type) |content_type| self.allocator.free(content_type);
    if (self.arg_error_type_escaped) |arg_error_type_escaped| self.allocator.free(arg_error_type_escaped);
    if (self.arg_error_message_escaped) |arg_error_message_escaped| self.allocator.free(arg_error_message_escaped);
    self.* = undefined;
}

//
// Create a successful invocation response with the given payload and content-type.
//
pub fn success(allocator: Allocator, arg_payload: [:0]const u8, arg_content_type: [:0]const u8) !InvocationResponse {
    var self: InvocationResponse = InvocationResponse.initWithDefault(allocator);
    if (arg_payload.len > 0) {
        self.payload = try allocPrintZ(allocator, "{s}", .{arg_payload});
    }
    if (arg_content_type.len > 0) {
        self.content_type = try allocPrintZ(allocator, "{s}", .{arg_content_type});
    }
    self.success = true;
    return self;
}

//
// Create a failure response with the given error message and error type.
// The content-type is always set to application/json in this case.
//
pub fn failure(allocator: Allocator, arg_error_message: [:0]const u8, arg_error_type: [:0]const u8) !InvocationResponse {
    var self: InvocationResponse = InvocationResponse.initWithDefault(allocator);
    self.content_type = try allocPrintZ(allocator, "{s}", .{"application/json"});
    self.success = false;
    if (arg_error_message.len > 0) {
        self.arg_error_message_escaped = try jsonEscape(allocator, arg_error_message);
        if (arg_error_type.len > 0) {
            self.arg_error_type_escaped = try jsonEscape(allocator, arg_error_type);
            if ((self.arg_error_message_escaped.?.len > 0) and (self.arg_error_type_escaped.?.len > 0)) {
                self.payload = try allocPrintZ(allocator, "{{\"errorMessage\":\"{s}\",\"errorType\":\"{s}\",\"stackTrace\":[]}}", .{ self.arg_error_message_escaped.?, self.arg_error_type_escaped.? });
            }
        }
    }
    return self;
}
//
// Get the MIME type of the payload.
//
pub fn getContentType(self: *InvocationResponse) ?[:0]const u8 {
    return self.content_type;
}

//
// Get the payload string. The string is assumed to be UTF-8 encoded.
//
pub fn getPayload(self: *InvocationResponse) ?[:0]const u8 {
    return self.payload;
}

//
// Returns true if the payload and content-type are set. Returns false if the error message and error types are set.
//
pub fn isSuccess(self: *InvocationResponse) bool {
    return self.success;
}

fn jsonEscape(allocator: Allocator, text: [:0]const u8) ![:0]const u8 {
    if (text.len == 0) {
        return text;
    }

    const last_non_printable_character: u8 = 31;
    // compute needed size for out
    var out_size: usize = 0;
    for (text) |char| {
        if ((char > last_non_printable_character) and (char != '\"') and (char != '\\')) {
            out_size += 1;
        } else {
            out_size += 1;
            switch (char) {
                '\\', '"', 8, 12, '\n', '\r', '\t' => { // \b = 8, \f = 12
                    out_size += 1;
                }, // escape character \ + ch
                else => {
                    out_size += 5;
                }, // print as unicode codepoint uxxxx
            }
        }
    }

    const out: [:0]u8 = try allocator.allocSentinel(u8, out_size, 0);
    var j: usize = 0;
    for (text) |char| {
        if ((char > last_non_printable_character) and (char != '\"') and (char != '\\')) {
            out[j] = char;
            j += 1;
        } else {
            out[j] = '\\';
            j += 1;
            switch (char) {
                '\\' => {
                    out[j] = '\\';
                    j += 1;
                },
                '"' => {
                    out[j] = '"';
                    j += 1;
                },
                8 => {
                    out[j] = 'b';
                    j += 1;
                },
                12 => {
                    out[j] = 'f';
                    j += 1;
                },
                '\n' => {
                    out[j] = 'n';
                    j += 1;
                },
                '\r' => {
                    out[j] = 'r';
                    j += 1;
                },
                '\t' => {
                    out[j] = 't';
                    j += 1;
                },
                else => {
                    const buffer: [:0]const u8 = try allocPrintZ(allocator, "u{x:0>4}", .{char});
                    defer allocator.free(buffer);
                    for (buffer) |byte| {
                        out[j] = byte;
                        j += 1;
                    }
                },
            }
        }
    }
    return out;
}

test "InvocationResponset success" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    var ir = try InvocationResponse.success(test_allocator, "", "");
    defer ir.deinit();
    try expect(ir.isSuccess());
    try expect(ir.getContentType() == null);
    try expect(ir.getPayload() == null);
    var ir1 = try InvocationResponse.success(test_allocator, "hello", "text");
    defer ir1.deinit();
    try expect(ir1.isSuccess());
    try expect(eql(u8, ir1.getContentType().?, "text"));
    try expect(eql(u8, ir1.getPayload().?, "hello"));
}

test "InvocationResponset failure" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    var ir = try InvocationResponse.failure(test_allocator, "", "");
    defer ir.deinit();
    try expect(!ir.isSuccess());
    try expect(eql(u8, ir.getContentType().?, "application/json"));
    try expect(ir.getPayload() == null);
    var ir1 = try InvocationResponse.failure(test_allocator, "Error", "Error Type");
    defer ir1.deinit();
    try expect(!ir1.isSuccess());
    try expect(eql(u8, ir1.getContentType().?, "application/json"));
    try expect(eql(u8, ir1.getPayload().?[0..65], "{\"errorMessage\":\"Error\",\"errorType\":\"Error Type\",\"stackTrace\":[]}"));
}

test "InvocationResponset jsonEscape" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const input = "{\"emoji\": \"😉\"}";
    const expected = "{\\\"emoji\\\": \\\"😉\\\"}";
    const str = try jsonEscape(test_allocator, input);
    defer test_allocator.free(str);
    try expect(eql(u8, str, expected));
}
