const InvocationRequest = @This();
const std = @import("std");

//
// The user's payload represented as a UTF-8 string.
//
payload: ?[:0]const u8 = null,
//
// An identifier unique to the current invocation.
//
request_id: ?[:0]const u8 = null,
//
// X-Ray tracing ID of the current invocation.
//
xray_trace_id: ?[:0]const u8 = null,
//
// Information about the client application and device when invoked through the AWS Mobile SDK.
//
client_context: ?[:0]const u8 = null,
//
// Information about the Amazon Cognito identity provider when invoked through the AWS Mobile SDK.
//
cognito_identity: ?[:0]const u8 = null,
//
//The ARN requested. This can be different in each invoke that executes the same version.
//
function_arn: ?[:0]const u8 = null,
//
// Function execution deadline counted in milliseconds since the Unix epoch.
//
deadline: i64 = 0,
//
// The number of milliseconds left before lambda terminates the current execution.
//
pub fn getTimeRemaining(self: *InvocationRequest) i64 {
    return (self.deadline - std.time.milliTimestamp());
}

test "InvocationRequest" {
    const expect = std.testing.expect;
    var ir = InvocationRequest{ .payload = "BODY", .request_id = "request_id", .deadline = (std.time.milliTimestamp() + 10000) };
    ir.xray_trace_id = "xray_trace_id";
    ir.client_context = "client_context";
    ir.cognito_identity = "cognito_identity";
    ir.function_arn = "function_arn";
    try expect(ir.getTimeRemaining() > 0);
}
