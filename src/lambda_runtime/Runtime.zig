const Runtime = @This();
const builtin = @import("builtin");
const std = @import("std");
const ArrayList = std.ArrayList;
const allocPrintZ = std.fmt.allocPrintZ;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Logging = @import("../logging/Logging.zig");
const Response = @import("../http/Response.zig");
const ResponseCode = @import("../http/ResponseCode.zig").ResponseCode;
const version = @import("version.zig");
const Pair = @import("Pair.zig");
const InvocationRequest = @import("InvocationRequest.zig");
const InvocationResponse = @import("InvocationResponse.zig");
const NoResult = @import("lambda_runtime.zig").NoResult;
const Outcome = @import("Outcome.zig").Outcome;
const StringBoolOutcome = Outcome([:0]const u8, bool, "", "");
const NextOutcome = Outcome(InvocationRequest, ResponseCode, "", "");
const PostOutcome = Outcome(NoResult, ResponseCode, "", "");

const cURL = @cImport({
    @cInclude("curl/curl.h");
    @cInclude("curl/curlver.h");
});

const LOG_TAG: [:0]const u8 = "LAMBDA_RUNTIME";
const REQUEST_ID_HEADER: [:0]const u8 = "lambda-runtime-aws-request-id";
const TRACE_ID_HEADER: [:0]const u8 = "lambda-runtime-trace-id";
const CLIENT_CONTEXT_HEADER: [:0]const u8 = "lambda-runtime-client-context";
const COGNITO_IDENTITY_HEADER: [:0]const u8 = "lambda-runtime-cognito-identity";
const FUNCTION_ARN_HEADER: [:0]const u8 = "lambda-runtime-invoked-function-arn";
const DEADLINE_MS_HEADER: [:0]const u8 = "lambda-runtime-deadline-ms";

const ULONG_MAX: u64 = std.math.maxInt(u64);

const EndPoints = enum(usize) {
    INIT_ERROR_ENDPOINT = 0,
    NEXT = 1,
    RESULT = 2,
};

const INIT_ERROR_ENDPOINT = "{s}/2018-06-01/runtime/init/error";
const NEXT_ENDPOINT = "{s}/2018-06-01/runtime/invocation/next";
const RESULT_ENDPOINT = "{s}/2018-06-01/runtime/invocation/";

allocator: Allocator = undefined,
strings: ArrayList([:0]const u8) = undefined,
responses: ArrayList(Response) = undefined,
logging: Logging = undefined,
user_agent_header: ?[:0]const u8 = null,
endpoints: [3][:0]const u8 = undefined,
curl_handle: ?*cURL.CURL = null,
next_outcomes: ArrayList(NextOutcome) = undefined,

pub fn deinit(self: *Runtime) void {
    // remove responses
    for (self.responses.items) |*item| {
        item.deinit();
    }
    self.responses.deinit();

    // remove next_outcomes
    for (self.next_outcomes.items) |*item| {
        item.deinit();
    }
    self.next_outcomes.deinit();

    // remove strings
    for (self.strings.items) |item| {
        self.allocator.free(item);
    }
    self.strings.deinit();
    if (self.curl_handle) |curl_handle| cURL.curl_easy_cleanup(curl_handle);

    self.logging.deinit();
    self.* = undefined;
}

pub fn init(allocator: Allocator) Runtime {
    const self = Runtime{
        .allocator = allocator,
        .logging = Logging.init(allocator),
        .strings = ArrayList([:0]const u8).init(allocator),
        .responses = ArrayList(Response).init(allocator),
        .next_outcomes = ArrayList(NextOutcome).init(allocator),
    };
    errdefer self.deinit();
    return self;
}

pub fn runHandler(self: *Runtime, handler: *const fn (InvocationRequest) anyerror!InvocationResponse) !void {
    self.logging.logInfo(LOG_TAG, "Initializing the Zig Lambda Runtime version {s}", .{version.getVersion()});

    var endpoint: [:0]const u8 = "http://";

    const endpoint_env_var: ?[]const u8 = std.os.getenv("AWS_LAMBDA_RUNTIME_API"); // using libC

    assert(endpoint_env_var != null); // AWS_LAMBDA_RUNTIME_API env variable must be defined

    if (endpoint_env_var.?.len > 0) {
        endpoint = allocPrintZ(self.allocator, "{s}{s}", .{ endpoint, endpoint_env_var.? }) catch {
            self.logging.logError(LOG_TAG, "Failed to setup endpoint. Exiting!", .{});
            return;
        };
        self.logging.logDebug(LOG_TAG, "LAMBDA_SERVER_ADDRESS defined in environment as: {s}", .{endpoint_env_var.?});
    } else {
        self.logging.logError(LOG_TAG, "LAMBDA_SERVER_ADDRESS not defined. Exiting!", .{});
        return;
    }
    defer self.allocator.free(endpoint);

    try self.configureRuntime(endpoint);

    var retries: usize = 0;
    const max_retries: usize = 3;

    while (retries < max_retries) {
        var next_outcome = try self.getNext();
        if (!next_outcome.isSuccess()) {
            if (next_outcome.getFailure() == ResponseCode.REQUEST_NOT_MADE) {
                retries += 1;
                continue;
            }
            self.logging.logInfo(LOG_TAG, "HTTP request was not successful. HTTP response code: {d}. Retrying...", .{@enumToInt(next_outcome.getFailure())});
            retries += 1;
            continue;
        }

        retries = 0; // infinite loop

        const req: InvocationRequest = next_outcome.getResult();
        self.logging.logInfo(LOG_TAG, "Invoking user handler", .{});
        var res: InvocationResponse = try handler(req);
        self.logging.logInfo(LOG_TAG, "Invoking user handler completed.", .{});

        if (res.isSuccess()) {
            var postOutcome: PostOutcome = try self.postSuccess(req.request_id.?, &res);
            if (!self.handlePostOutcome(&postOutcome, req.request_id.?)) {
                res.deinit();
                return; // TODO: implement a better retry strategy
            }
        } else {
            var postOutcome: PostOutcome = try self.postFailure(req.request_id.?, &res);
            if (!self.handlePostOutcome(&postOutcome, req.request_id.?)) {
                res.deinit();
                return; // TODO: implement a better retry strategy
            }
        }
        res.deinit();
    }

    if (retries == max_retries) {
        self.logging.logError(LOG_TAG, "Exhausted all retries. This is probably a bug in libcurl v{s} Exiting!", .{cURL.LIBCURL_VERSION});
    }
}

fn configureRuntime(self: *Runtime, endpoint: [:0]const u8) !void {
    try self.generateAndSaveUserAgent("AWS_Lambda_Zig/" ++ comptime version.getVersion());
    try self.generateAndSaveEndPoints(endpoint);
    self.curl_handle = cURL.curl_easy_init() orelse {
        self.logging.logError(LOG_TAG, "Failed to acquire curl easy handle for next.", .{});
        return error.CURLHandleInitFailed;
    };
}

//
// Ask lambda for an invocation.
//
fn getNext(self: *Runtime) !NextOutcome {
    // we can initialize response
    var resp: Response = try Response.init(self.allocator, self.logging);

    self.setCurlNextOptions();

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_WRITEDATA, &resp);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HEADERDATA, &resp);

    var headers: [*c]cURL.curl_slist = null;
    headers = cURL.curl_slist_append(headers, &self.user_agent_header.?.ptr[0]);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HTTPHEADER, headers);

    self.logging.logDebug(LOG_TAG, "Making request to {s}", .{self.endpoints[@enumToInt(EndPoints.NEXT)]});

    var curl_code: cURL.CURLcode = cURL.curl_easy_perform(self.curl_handle.?); // perform call

    self.logging.logDebug(LOG_TAG, "Completed request to {s}", .{self.endpoints[@enumToInt(EndPoints.NEXT)]});
    cURL.curl_slist_free_all(headers);

    if (curl_code != cURL.CURLE_OK) {
        self.logging.logDebug(LOG_TAG, "CURL returned error code {d} - {s}", .{ curl_code, cURL.curl_easy_strerror(curl_code) });
        self.logging.logError(LOG_TAG, "Failed to get next invocation. No Response from endpoint \"{s}\"", .{self.endpoints[@enumToInt(EndPoints.NEXT)]});

        var nOutcome = NextOutcome.init(.{ResponseCode}, .{ResponseCode.REQUEST_NOT_MADE});
        try self.next_outcomes.append(nOutcome);
        try self.responses.append(resp);
        return nOutcome;
    }

    {
        var resp_code: c_long = 0;
        _ = cURL.curl_easy_getinfo(self.curl_handle.?, cURL.CURLINFO_RESPONSE_CODE, &resp_code);
        resp.setResponseCode(@intToEnum(ResponseCode, resp_code));
    }

    {
        var content_type: [:0]const u8 = undefined;
        _ = cURL.curl_easy_getinfo(self.curl_handle.?, cURL.CURLINFO_CONTENT_TYPE, &content_type);
        try resp.setContentType(content_type); // resp.getcontent_type not used after.
    }

    if (!isSuccess(resp.getResponseCode())) {
        self.logging.logError(LOG_TAG, "Failed to get next invocation. Http Response code: {d}", .{@enumToInt(resp.getResponseCode())});
        var nOutcome: NextOutcome = NextOutcome.init(.{ResponseCode}, .{resp.getResponseCode()});
        try self.next_outcomes.append(nOutcome);
        try self.responses.append(resp);
        return nOutcome;
    }

    var out: StringBoolOutcome = resp.getHeader(REQUEST_ID_HEADER);
    if (!out.isSuccess()) {
        self.logging.logError(LOG_TAG, "Failed to find header {s} in response", .{REQUEST_ID_HEADER});
        var nOutcome: NextOutcome = NextOutcome.init(.{ResponseCode}, .{ResponseCode.REQUEST_NOT_MADE});
        try self.next_outcomes.append(nOutcome);
        try self.responses.append(resp);
        return nOutcome;
    }

    var req: InvocationRequest = InvocationRequest{ .payload = resp.getBody(), .request_id = out.getResult() };

    out = resp.getHeader(TRACE_ID_HEADER);
    if (out.isSuccess()) {
        req.xray_trace_id = out.getResult();
    }

    out = resp.getHeader(CLIENT_CONTEXT_HEADER);
    if (out.isSuccess()) {
        req.client_context = out.getResult();
    }

    out = resp.getHeader(COGNITO_IDENTITY_HEADER);
    if (out.isSuccess()) {
        req.cognito_identity = out.getResult();
    }

    out = resp.getHeader(FUNCTION_ARN_HEADER);
    if (out.isSuccess()) {
        req.function_arn = out.getResult();
    }

    out = resp.getHeader(DEADLINE_MS_HEADER);
    if (out.isSuccess()) {
        const deadline_string = out.getResult();
        const ms = std.fmt.parseUnsigned(u64, deadline_string, 10) catch 0;
        assert(ms > 0);
        assert(ms < ULONG_MAX);
        req.deadline += @intCast(i64, ms);
        self.logging.logInfo(LOG_TAG, "Received payload: {s}\nTime remaining: {d}", .{ req.payload.?, req.getTimeRemaining() });
    }

    var next_outcome: NextOutcome = NextOutcome.init(.{InvocationRequest}, .{req});
    try self.next_outcomes.append(next_outcome);
    try self.responses.append(resp);
    return next_outcome;
}

//
// Tells lambda that the function has succeeded.
//
fn postSuccess(self: *Runtime, request_id: [:0]const u8, handler_response: *InvocationResponse) !PostOutcome {
    const url: [:0]const u8 = try allocPrintZ(self.allocator, "{s}{s}/response", .{ self.endpoints[@enumToInt(EndPoints.RESULT)], request_id });
    try self.strings.append(url);
    return doPost(self, url, request_id, handler_response);
}

//
// Tells lambda that the function has failed.
//
fn postFailure(self: *Runtime, request_id: [:0]const u8, handler_response: *InvocationResponse) !PostOutcome {
    const url: [:0]const u8 = try allocPrintZ(self.allocator, "{s}{s}/error", .{ self.endpoints[@enumToInt(EndPoints.RESULT)], request_id });
    try self.strings.append(url);
    return doPost(self, url, request_id, handler_response);
}

fn handlePostOutcome(self: *Runtime, outcome: *PostOutcome, request_id: [:0]const u8) bool {
    if (outcome.isSuccess()) {
        return true;
    }
    if (outcome.getFailure() == ResponseCode.REQUEST_NOT_MADE) {
        self.logging.logError(LOG_TAG, "Failed to send HTTP request for invocation {s}.", .{request_id});
    } else {
        self.logging.logInfo(LOG_TAG, "HTTP Request for invocation {s} was not successful. HTTP response code: {d}.", .{ request_id, @enumToInt(outcome.getFailure()) });
    }
    return false;
}

fn generateAndSaveUserAgent(self: *Runtime, user_agent: [:0]const u8) !void {
    self.user_agent_header = try allocPrintZ(self.allocator, "User-Agent: {s}", .{user_agent});
    try self.strings.append(self.user_agent_header.?);
}

fn generateAndSaveEndPoints(self: *Runtime, endpoint: [:0]const u8) !void {
    self.endpoints[@enumToInt(EndPoints.INIT_ERROR_ENDPOINT)] = try allocPrintZ(self.allocator, "{s}/2018-06-01/runtime/init/error", .{endpoint});
    try self.strings.append(self.endpoints[@enumToInt(EndPoints.INIT_ERROR_ENDPOINT)]);
    self.endpoints[@enumToInt(EndPoints.NEXT)] = try allocPrintZ(self.allocator, "{s}/2018-06-01/runtime/invocation/next", .{endpoint});
    try self.strings.append(self.endpoints[@enumToInt(EndPoints.NEXT)]);
    self.endpoints[@enumToInt(EndPoints.RESULT)] = try allocPrintZ(self.allocator, "{s}/2018-06-01/runtime/invocation/", .{endpoint});
    try self.strings.append(self.endpoints[@enumToInt(EndPoints.RESULT)]);
}

// readData -> user_data is ctx Pair struct
fn readData(buffer: [*c]u8, size: usize, nItems: usize, user_data: ?*anyopaque) callconv(.C) usize {
    const limit: usize = size * nItems;
    var ctx: *Pair = @ptrCast(*Pair, @alignCast(@alignOf(Pair), user_data.?));

    if (ctx.first == null) {
        return 0; // nothing to read
    }

    var unread: usize = ctx.first.?.len - ctx.second;
    if (0 == unread) {
        return 0; // end of file/read
    }

    var typed_buffer: [*:0]u8 = @intToPtr([*:0]u8, @ptrToInt(buffer));

    if (unread <= limit) {
        var i: usize = 0 + ctx.second;
        var j: usize = 0;
        while (j < unread) : (j += 1) {
            typed_buffer[j] = ctx.first.?[i];
            i += 1;
        }
        ctx.second += unread;
        return unread;
    }

    var i: usize = 0 + ctx.second;
    var j: usize = 0;
    while (j < limit) : (j += 1) {
        typed_buffer[j] = ctx.first.?[i];
        i += 1;
    }
    ctx.second += limit;
    return limit;
}

// writeData -> user_data is Response struct pointer
fn writeData(ptr: [*c]u8, size: usize, nMemb: usize, user_data: ?*anyopaque) callconv(.C) usize {
    if (ptr == null) {
        return 0;
    }

    var resp: *Response = @ptrCast(*Response, @alignCast(@alignOf(Response), user_data.?));
    assert(size == 1);

    var typed_buffer: [*:0]u8 = @intToPtr([*:0]u8, @ptrToInt(ptr));
    resp.appendBody(typed_buffer[0..nMemb :0]) catch {
        return 0;
    };

    return nMemb;
}

// writeHeader called header by header when a header is fully loaded
// writeHeader -> user_data is Response struct pointer
fn writeHeader(ptr: [*c]u8, size: usize, nMemb: usize, user_data: ?*anyopaque) callconv(.C) usize {
    if (ptr == null) {
        return 0;
    }

    var resp: *Response = @ptrCast(*Response, @alignCast(@alignOf(Response), user_data.?));
    var typed_buffer: [*:0]u8 = @intToPtr([*:0]u8, @ptrToInt(ptr));
    resp.logging.logDebug(LOG_TAG, "received header: {s}", .{typed_buffer[0..nMemb :0]});

    var i: usize = 0;
    while (i < nMemb) : (i += 1) {
        if (ptr[i] != ':') {
            continue;
        }
        resp.addHeader(trim(typed_buffer[0..i]), trim(typed_buffer[(i + 1)..nMemb])) catch {
            return 0;
        };
        break;
    }

    return size * nMemb;
}

// rtCurlDebugCallback -> user_data is Runtime struct pointer
fn rtCurlDebugCallback(handle: *cURL.CURL, curl_infotype: cURL.curl_infotype, data: [*c]u8, size: usize, user_data: ?*anyopaque) callconv(.C) c_int {
    _ = handle;
    _ = curl_infotype;
    var self: *Runtime = @ptrCast(*Runtime, @alignCast(@alignOf(Runtime), user_data.?));
    var typed_data: [*:0]u8 = @intToPtr([*:0]u8, @ptrToInt(data));

    self.logging.logDebug(LOG_TAG, "CURL DBG: {s}", .{typed_data[0..size :0]});

    return 0;
}

fn setCurlNextOptions(self: *Runtime) void {
    // lambda freezes the container when no further tasks are available. The freezing period could be longer than the
    // request timeout, which causes the following get_next request to fail with a timeout error.
    cURL.curl_easy_reset(self.curl_handle.?);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_TIMEOUT, @as(c_long, 0));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_CONNECTTIMEOUT, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_NOSIGNAL, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_TCP_NODELAY, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HTTP_VERSION, cURL.CURL_HTTP_VERSION_1_1);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HTTPGET, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_URL, &self.endpoints[@enumToInt(EndPoints.NEXT)].ptr[0]);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_WRITEFUNCTION, writeData);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HEADERFUNCTION, writeHeader);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_PROXY, "");

    if (builtin.mode == .Debug) {
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_VERBOSE, @as(c_long, 1));
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_DEBUGFUNCTION, rtCurlDebugCallback);
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_DEBUGDATA, self); // self is already a pointer to the Runtime Struct
    }
}

fn setCurlPostResultOptions(self: *Runtime) void {
    cURL.curl_easy_reset(self.curl_handle.?);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_TIMEOUT, @as(c_long, 0));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_CONNECTTIMEOUT, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_NOSIGNAL, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_TCP_NODELAY, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HTTP_VERSION, cURL.CURL_HTTP_VERSION_1_1);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_POST, @as(c_long, 1));
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_READFUNCTION, readData);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_WRITEFUNCTION, writeData);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HEADERFUNCTION, writeHeader);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_PROXY, "");

    if (builtin.mode == .Debug) {
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_VERBOSE, @as(c_long, 1));
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_DEBUGFUNCTION, rtCurlDebugCallback);
        _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_DEBUGDATA, self); // self is already a pointer to the Runtime Struct
    }
}

fn doPost(self: *Runtime, url: [:0]const u8, request_id: [:0]const u8, handler_response: *InvocationResponse) !PostOutcome {
    self.setCurlPostResultOptions();
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_URL, &url.ptr[0]);
    self.logging.logInfo(LOG_TAG, "Making request to {s}", .{url});

    var headers: [*c]cURL.curl_slist = null;

    const content_type: ?[:0]const u8 = handler_response.getContentType();

    if ((content_type == null) or (content_type.?.len == 0)) {
        headers = cURL.curl_slist_append(headers, "content-type: text/html");
    } else {
        const content_typeBuffer: [:0]const u8 = try allocPrintZ(self.allocator, "content-type: {s}", .{content_type.?});
        try self.strings.append(content_typeBuffer);
        headers = cURL.curl_slist_append(headers, &content_typeBuffer.ptr[0]);
    }

    headers = cURL.curl_slist_append(headers, "Expect:");
    headers = cURL.curl_slist_append(headers, "transfer-encoding:");
    headers = cURL.curl_slist_append(headers, &self.user_agent_header.?.ptr[0]);

    const payload: ?[:0]const u8 = handler_response.getPayload();
    if (payload == null) {
        cURL.curl_slist_free_all(headers);
        return PostOutcome.init(.{ResponseCode}, .{ResponseCode.REQUEST_NOT_MADE});
    }

    self.logging.logDebug(LOG_TAG, "calculating content length... content-length: {d}", .{payload.?.len});
    const content_length: [:0]const u8 = try allocPrintZ(self.allocator, "content-length: {d}", .{payload.?.len});
    try self.strings.append(content_length);
    headers = cURL.curl_slist_append(headers, &content_length.ptr[0]);

    var ctx: Pair = Pair{ .first = payload.?, .second = 0 };
    var resp: Response = try Response.init(self.allocator, self.logging);

    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_WRITEDATA, &resp);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HEADERDATA, &resp);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_READDATA, &ctx);
    _ = cURL.curl_easy_setopt(self.curl_handle.?, cURL.CURLOPT_HTTPHEADER, headers);

    var curl_code: cURL.CURLcode = cURL.curl_easy_perform(self.curl_handle.?); // perform call
    cURL.curl_slist_free_all(headers);
    try self.responses.append(resp);

    if (curl_code != cURL.CURLE_OK) {
        self.logging.logDebug(LOG_TAG, "CURL returned error code {d} - {s}, for invocation {s}", .{ curl_code, cURL.curl_easy_strerror(curl_code), request_id });
        return PostOutcome.init(.{ResponseCode}, .{ResponseCode.REQUEST_NOT_MADE});
    }

    var http_response_code: c_long = 0;
    _ = cURL.curl_easy_getinfo(self.curl_handle.?, cURL.CURLINFO_RESPONSE_CODE, &http_response_code);

    if (!isSuccess(@intToEnum(ResponseCode, @intCast(i32, http_response_code)))) {
        self.logging.logError(LOG_TAG, "Failed to post handler success response. Http response code: {d}.", .{http_response_code});
        return PostOutcome.init(.{ResponseCode}, .{@intToEnum(ResponseCode, @intCast(i32, http_response_code))});
    }

    return PostOutcome.init(.{NoResult}, .{NoResult{}});
}

inline fn isWhitespace(char: u8) bool {
    const space: u8 = 0x20; // space (0x20, ' ')
    const form_feed: u8 = 0x0c; // form feed (0x0c, '\f')
    const line_feed: u8 = 0x0a; // line feed (0x0a, '\n')
    const carriage_return: u8 = 0x0d; // carriage return (0x0d, '\r')
    const horizontal_tab: u8 = 0x09; // horizontal tab (0x09, '\t')
    const vertical_tab: u8 = 0x0b; // vertical tab (0x0b, '\v')
    switch (char) {
        space, form_feed, line_feed, carriage_return, horizontal_tab, vertical_tab => {
            return true;
        },
        else => {
            return false;
        },
    }
}

inline fn trim(string: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = string.len - 1;
    while (isWhitespace(string[start])) : (start += 1) {}
    while (isWhitespace(string[end])) : (end -= 1) {}

    return string[start..(end + 1)];
}

fn isSuccess(http_code: ResponseCode) bool {
    comptime var HTTP_FIRST_SUCCESS_ERROR_CODE = 200;
    comptime var HTTP_LAST_SUCCESS_ERROR_CODE = 299;
    const code = @enumToInt(http_code);
    return (code >= HTTP_FIRST_SUCCESS_ERROR_CODE) and (code <= HTTP_LAST_SUCCESS_ERROR_CODE);
}

test "Runtime init/deinit" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    try expect(r.logging.allocator.ptr == test_allocator.ptr);
}

test "Runtime isSuccess " {
    const expect = std.testing.expect;
    try expect(isSuccess(ResponseCode.ACCEPTED));
    try expect(isSuccess(ResponseCode.BAD_REQUEST) == false);
}

test "Runtime trim" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    try expect(eql(u8, trim("   123 45  "), "123 45"));
    try expect(eql(u8, trim("123 45  "), "123 45"));
    try expect(eql(u8, trim("   123 45"), "123 45"));
    try expect(eql(u8, trim("123 45"), "123 45"));
}

test "Runtime getNext" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    try r.configureRuntime("endpoint1");
    var n = try r.getNext(); // if AWS_LAMBDA_RUNTIME_API is configured, it will call the server
    try expect(!n.isSuccess());
}

test "Runtime postSuccess" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    try r.configureRuntime("endpoint1");
    var irs = try InvocationResponse.success(test_allocator, "", "");
    defer irs.deinit();
    var ps = try r.postSuccess("12345678", &irs);
    try expect(!ps.isSuccess());
    var irf = try InvocationResponse.failure(test_allocator, "", "");
    defer irf.deinit();
    ps = try r.postSuccess("12345678", &irf);
    try expect(!ps.isSuccess());
}

test "Runtime postFailure" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    try r.configureRuntime("endpoint1");
    var irs = try InvocationResponse.success(test_allocator, "", "");
    defer irs.deinit();
    var ps = try r.postFailure("12345678", &irs);
    try expect(!ps.isSuccess());
    var irf = try InvocationResponse.failure(test_allocator, "", "");
    defer irf.deinit();
    ps = try r.postFailure("12345678", &irf);
    try expect(!ps.isSuccess());
}

test "Runtime handlePostOutcome" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    const request_id = "request_id";
    var pos = PostOutcome.init(.{NoResult}, .{NoResult{}});
    defer pos.deinit();
    var pof = PostOutcome.init(.{ResponseCode}, .{ResponseCode.NOT_IMPLEMENTED});
    defer pof.deinit();

    try expect(r.handlePostOutcome(&pos, request_id));
    try expect(!r.handlePostOutcome(&pof, request_id));
}

test "Runtime runHandler" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    var r = Runtime.init(test_allocator);
    defer r.deinit();
    // dummy tests
    var rh = try r.runHandler(testSuccessHandler1); // if AWS_LAMBDA_RUNTIME_API is fully configured, it will call the server
    try expect(rh == {});
    rh = try r.runHandler(testFailureHandler1); // if AWS_LAMBDA_RUNTIME_API is fully configured, it will call the server
    try expect(rh == {});
}

fn testSuccessHandler1(ir: InvocationRequest) !InvocationResponse {
    _ = ir;
    return try InvocationResponse.success(std.testing.allocator, "", "");
}

fn testFailureHandler1(ir: InvocationRequest) !InvocationResponse {
    _ = ir;
    return try InvocationResponse.failure(std.testing.allocator, "", "");
}
