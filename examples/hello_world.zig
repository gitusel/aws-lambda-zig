const std = @import("std");
const Allocator = std.mem.Allocator;

const aws = @import("aws");
const lambda_runtime = aws.lambda_runtime;
const Runtime = lambda_runtime.Runtime;
const InvocationRequest = lambda_runtime.InvocationRequest;
const InvocationResponse = lambda_runtime.InvocationResponse;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn myHandler(ir: InvocationRequest) !InvocationResponse {
    _ = ir;
    return InvocationResponse.success(allocator, "{\"Hello\":\", World!\"}", "application/json");
}

pub fn main() !void {
    defer _ = gpa.deinit();
    var runtime = Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.runHandler(myHandler);
}
