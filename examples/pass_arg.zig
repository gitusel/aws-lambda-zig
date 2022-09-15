const std = @import("std");
const Allocator = std.mem.Allocator;

const aws = @import("aws");
const lambda_runtime = aws.lambda_runtime;
const Runtime = lambda_runtime.Runtime;
const InvocationRequest = lambda_runtime.InvocationRequest;
const InvocationResponse = lambda_runtime.InvocationResponse;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn myHandlerWithArg(ir: InvocationRequest, val: i32) !InvocationResponse {
    _ = ir;
    var buf: [64]u8 = [_]u8{0} ** 64;
    var json = try std.fmt.bufPrintZ(buf[0..], "{{\"Hello\":\", World! with arg: {d}\"}}", .{val});
    return InvocationResponse.success(allocator, json, "application/json");
}

pub fn myHandler(ir: InvocationRequest) !InvocationResponse {
    // if arg in myHandlerWithArg needs alloc, it will need to be free before returning the response;
    return myHandlerWithArg(ir, 0);
}

pub fn main() !void {
    defer _ = gpa.deinit();
    var runtime = Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.runHandler(myHandler);
}
