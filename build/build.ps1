# Build fastm.plugin on Windows (MSVC), targeting x86_64.
#
#   Stata is an x86_64 binary, so the plugin must be x86_64. Run this from a
#   "Developer PowerShell for VS" (so cl.exe / link.exe are on PATH), or let the
#   CI workflow set up the MSVC environment. Requires a Rust toolchain.
#
# Usage:  pwsh build/build.ps1
$ErrorActionPreference = "Stop"
$env:CARGO_TERM_COLOR = "never"   # keep ANSI codes out of --print native-static-libs
$Root   = Split-Path -Parent $PSScriptRoot
$Crate  = Join-Path $Root "crate"
$Vendor = Join-Path $Root "vendor"
$Obj    = Join-Path $Root "build"
$Out    = Join-Path $Root "fastm.plugin"
$Target = "x86_64-pc-windows-msvc"

Write-Host ">> Rust staticlib  (target $Target)"
# Statically link the MSVC runtime so the plugin does not depend on the Visual
# C++ Redistributable (VCRUNTIME140.dll) being installed -- keeps fastm loadable
# on a clean Windows. Must match the C shim, compiled /MT below.
$env:RUSTFLAGS = "-C target-feature=+crt-static"
Push-Location $Crate
rustup target add $Target | Out-Null
cargo build --release --target $Target
# System libs that Rust's std needs when its staticlib is linked into a DLL.
$nat = cargo rustc --release --target $Target -- --print native-static-libs 2>&1
Pop-Location

$Alib = Join-Path $Crate "target\$Target\release\fastm.lib"
if (!(Test-Path $Alib)) { throw "missing $Alib" }

$syslibs = ""
foreach ($line in $nat) {
    if ($line -match "native-static-libs:\s*(.*)$") {
        # strip any stray ANSI escapes, then split into lib names
        $syslibs = ($Matches[1] -replace "\x1b\[[0-9;]*m", "").Trim()
    }
}

Write-Host ">> StataCorp shim  (SYSTEM=STWIN32=4)"
# /MT = static release CRT, matching the Rust crt-static above (no VCRUNTIME140 dep).
cl /nologo /MT /c /DSYSTEM=4 /I"$Vendor" "$Vendor\stplugin.c" /Fo"$Obj\stplugin.obj"
if ($LASTEXITCODE -ne 0) { throw "cl failed on stplugin.c ($LASTEXITCODE)" }
cl /nologo /MT /c /DSYSTEM=4 /I"$Vendor" "$Crate\src\shim.c"   /Fo"$Obj\shim.obj"
if ($LASTEXITCODE -ne 0) { throw "cl failed on shim.c ($LASTEXITCODE)" }

Write-Host ">> link $Out"
$linkArgs = @("/nologo", "/DLL", "/OUT:$Out", "$Obj\shim.obj", "$Obj\stplugin.obj", "$Alib")
if ($syslibs) { $linkArgs += ($syslibs.Split(" ") | Where-Object { $_ -ne "" }) }
& link @linkArgs
if ($LASTEXITCODE -ne 0) { throw "link failed ($LASTEXITCODE)" }

Write-Host "built: $Out"
# Stata loads the DLL by the name fastm.plugin; confirm the entry points export.
dumpbin /exports "$Out" | Select-String "stata_call|pginit"
