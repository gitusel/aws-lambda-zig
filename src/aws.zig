pub const http = @import("http/http.zig");
pub const lambda_runtime = @import("lambda_runtime/lambda_runtime.zig");
pub const Logging = @import("logging/Logging.zig");

test "aws" {
    _ = lambda_runtime;
    _ = Logging;
}
