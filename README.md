# aws-lambda-zig
Zig implementation of the AWS lambda runtime API based on aws-lambda-cpp repo https://github.com/awslabs/aws-lambda-cpp

# building examples
The libraries are extracted from Alpine Linux v3.16. For aarch64, Alpine Linux's libcrypto.a and libsssl.a include aarch64 outline atomics not yet fully supported by Zig. Both libcrypto.a and libsssl.a were recompiled using Zig cc with the same config. Builds tested on MacOS, Linux Ubuntu and Windows 10 using v0.10.0-dev.

Currently forcing stage1 due to https://github.com/ziglang/zig/issues/12706

## x86_64

zig build --build-file build_examples.zig -Dtarget=x86_64-linux-musl -Drelease-small=true -fstage1

## ARM64

zig build --build-file build_examples.zig -Dtarget=aarch64-linux-musl -Drelease-small=true -fstage1
