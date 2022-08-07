pub const Runtime = @import("Runtime.zig");
pub const Outcome = @import("Outcome.zig").Outcome;
pub usingnamespace @import("version.zig");
pub const InvocationRequest = @import("InvocationRequest.zig");
pub const InvocationResponse = @import("InvocationResponse.zig");
pub const NoResult = struct {};

test "lambda_runtime" {
    _ = Runtime;
    _ = Outcome;
    _ = @import("version.zig");
    _ = InvocationRequest;
    _ = InvocationResponse;
}
