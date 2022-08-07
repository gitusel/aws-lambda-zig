#!/bin/bash

set -euo pipefail

ZIG_FORMAT="zig fmt"

FAIL=0
SOURCE_FILES=$(find src -type f -name "*.zig")

for i in $SOURCE_FILES
do
    if [ $($ZIG_FORMAT --check $i | wc -l) -ne 0 ]
    then
        echo "$i failed zig format check."
        FAIL=1
    fi
done

exit $FAIL
