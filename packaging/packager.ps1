#  translated from https://github.com/awslabs/aws-lambda-cpp/blob/master/packaging/packager
#  Copyright 2018-present Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License").
#  You may not use this file except in compliance with the License.
#  A copy of the License is located at
#
#   http://aws.amazon.com/apache2.0
#
#  or in the "license" file accompanying this file. This file is distributed
#  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
#  express or implied. See the License for the specific language governing
#  permissions and limitations under the License.
param(
    $PKG_BIN_PATH
)

function Usage() {
    Write-Host "Usage: packager.ps1 <binary name>"
    Exit
}

if ($PKG_BIN_PATH) {
    if (![System.IO.File]::Exists($PKG_BIN_PATH)) {
        Write-Host "$PKG_BIN_PATH - No such file."
        Exit
    }
}
else {
    Write-Host "Error: missing arguments"
    Usage
}

$ORIGIN_DIR = Get-Location
$PKG_DIR = "tmp"
$PKG_BIN_FILENAME = (get-item $PKG_BIN_PATH).psextended.BaseName

mkdir -p "$PKG_DIR/bin" | out-null
Copy-Item -Path "$PKG_BIN_PATH" -Destination "$PKG_DIR/bin" | out-null

New-Item "$PKG_DIR/bootstrap" | out-null
$bootstrap_script = @"
#!/bin/bash
set -euo pipefail
export AWS_EXECUTION_ENV=lambda-zig
exec `$LAMBDA_TASK_ROOT/bin/$PKG_BIN_FILENAME `${_HANDLER}
"@

Set-Content "$PKG_DIR/bootstrap" $bootstrap_script
# https://stackoverflow.com/questions/8852682/convert-file-from-windows-to-unix-through-powershell-or-batch
Get-ChildItem "$PKG_DIR/bootstrap" | ForEach-Object {
    # get the contents and replace line breaks by U+000A
    $contents = [IO.File]::ReadAllText($_) -replace "`r`n?", "`n"
    # create UTF-8 encoding without signature
    $utf8 = New-Object System.Text.UTF8Encoding $false
    # write the text back
    [IO.File]::WriteAllText($_, $contents, $utf8)
}

$acl = Get-Acl "$PKG_DIR/bootstrap"
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($username, "Full", "Allow")
$acl.SetAccessRule($accessRule)
$acl | Set-Acl "$PKG_DIR/bootstrap"

if ([System.IO.File]::Exists("$ORIGIN_DIR/$PKG_BIN_FILENAME.zip")) {
    Remove-Item "$ORIGIN_DIR/$PKG_BIN_FILENAME.zip" | out-null
}
Function ZipFiles($pathTarget, $zipFileName) {
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.AppContext]::SetSwitch('Switch.System.IO.Compression.ZipFile.UseBackslash', $false)
    [System.IO.Directory]::SetCurrentDirectory($ORIGIN_DIR)
    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    [System.IO.Compression.ZipFile]::CreateFromDirectory($pathTarget, $zipFileName, $compressionLevel, $false)
}

ZipFiles "$PKG_DIR" "$PKG_BIN_FILENAME.zip" 

Remove-Item "$PKG_DIR" -Recurse | out-null

# https://sourceforge.net/p/galaxyv2/code/HEAD/tree/other/zip_exec/
..\packaging\zip_exec.exe "$PKG_BIN_FILENAME.zip" "bootstrap" | out-null
..\packaging\zip_exec.exe "$PKG_BIN_FILENAME.zip" "bin/$PKG_BIN_FILENAME" | out-null

Write-Host Created "$ORIGIN_DIR\$PKG_BIN_FILENAME.zip"
