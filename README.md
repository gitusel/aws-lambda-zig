# aws-lambda-zig
Zig implementation of the AWS lambda runtime API based on aws-lambda-cpp repo https://github.com/awslabs/aws-lambda-cpp

# building examples
The libraries are extracted from Alpine Linux v3.16. Builds tested on MacOS, Linux Ubuntu and Windows 10 using v0.11.0-dev.

## x86_64

Before zig commit #efa25e7:

zig build --build-file ./build_examples.zig -Dtarget=x86_64-linux-musl -Drelease-small=true

After zig commit #efa25e7:

zig build --build-file ./build_examples.zig -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall

## ARM64

Before zig commit #efa25e7:

zig build --build-file ./build_examples.zig -Dtarget=aarch64-linux-musl -Drelease-small=true

After zig commit #efa25e7:

zig build --build-file ./build_examples.zig -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSmall
