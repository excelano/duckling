<#
.SYNOPSIS
    Refuse a binary that imports a DLL Windows does not ship.

.DESCRIPTION
    Slipcase 0.1.1 failed Microsoft Store certification on 2026-08-29 under
    policy 10.2.4.1. The package installed on the tester's clean machine and
    then would not start: *The code execution cannot proceed because
    VCRUNTIME140.dll was not found.* That DLL ships in the Visual C++
    Redistributable, not in Windows.

    Nothing this project runs could have caught it there. The tests pass, the
    suite passes, the certification kit passed, and the application starts - on
    a machine with Visual Studio installed, which is every machine any of the
    three platforms has ever built on. The defect is invisible from inside the
    toolchain that causes it, so the check has to be about the artefact rather
    than about whether it runs here.

    This is the Windows analogue of the `ldd` line `linux.yml` uses and of
    `packaging/linux/check-libraries.sh`, and it exists for the same reason: the
    rule means the outcome, so check the outcome.

    It parses the PE import table itself rather than shelling out to dumpbin,
    because dumpbin comes with Visual C++ and a check that needs the toolchain
    is a check that cannot run where the toolchain is absent.

    **This script asks two questions where segler's asks one**, and that is
    Duckling's whole difference. Slipcase and Segler link the CRT in with
    `+crt-static` and ship no DLL of their own, so for them every import must be
    in-box or the build is wrong. Duckling cannot: the prebuilt ONNX Runtime it
    links was compiled against the dynamic CRT and will not link against the
    static one, measured 2026-09-05, and `.cargo/config.toml` carries the whole
    of that. So five DLLs travel *inside* the package beside the executable, and
    an import is acceptable if it is in-box **or** it is one of those five. The
    second list is not a relaxation of the first - it is a promise that
    `build-msix.ps1` and `install.ps1` keep, and both of them verify they have
    kept it.

    **What this does not cover.** A library loaded by name at run time is not in
    the import table, so this script cannot see it. Duckling ships pdfium, which
    docling.rs opens through `PDFIUM_DYNAMIC_LIB_PATH` from inside the package,
    and wgpu reaches Direct3D partly the same way. Neither is a gap worth
    closing here - a check that tried to follow run-time loading would be
    guessing at names - but a person reading a green line from this script
    should know it is a statement about the import table and not about
    everything the process will open.

.PARAMETER Binary
    The executable to read. Defaults to the release build of duckling.
#>
[CmdletBinding()]
param(
    [string] $Binary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Refuse([string] $why) {
    Write-Host "check-imports: $why" -ForegroundColor Red
    exit 1
}

# Every DLL here has been confirmed present in C:\Windows\System32 on a stock
# Windows 10 or 11 install. The list is deliberately explicit: a dependency
# this project has never seen before should stop a build and be looked at by a
# person, which is the step that was missing when VCRUNTIME140.dll arrived.
#
# The first eighteen are slipcase-desktop's list, which segler carried unchanged
# and which is what a Rust eframe window imports. The rest are Duckling's own
# and arrive with the ONNX Runtime that `ort` links in; each is annotated with
# what brought it and how its presence on a stock machine was confirmed. That
# annotation is the whole value of the list - a name added without one is a
# guess wearing the clothes of a measurement.
$InBox = @(
    # The window: eframe, winit, wgpu, accesskit. slipcase-desktop's eighteen,
    # which segler carried unchanged and which this binary imports too.
    'advapi32.dll', 'bcryptprimitives.dll', 'combase.dll', 'dwmapi.dll',
    'dxgi.dll', 'gdi32.dll', 'imm32.dll', 'kernel32.dll', 'ntdll.dll',
    'ole32.dll', 'oleaut32.dll', 'opengl32.dll', 'setupapi.dll',
    'shell32.dll', 'shlwapi.dll', 'user32.dll', 'uiautomationcore.dll',
    'uxtheme.dll',

    # Duckling's own three, all of them arriving with ONNX Runtime and all
    # three confirmed in C:\Windows\System32 on this machine on 2026-09-05,
    # with the versions read off the files:
    #
    #   bcrypt.dll    10.0.19041.1     Windows' cryptography API. In-box since
    #                                  Vista, and distinct from the
    #                                  bcryptprimitives.dll above, which Rust's
    #                                  standard library already brought.
    #   d3d12.dll     10.0.19041.5794  Direct3D 12, in-box since Windows 10.
    #                                  wgpu also reaches it through LoadLibrary,
    #                                  where it would not appear here; ONNX
    #                                  Runtime imports it outright.
    #   dbghelp.dll   10.0.19041.5848  Symbol handling, in-box since Windows
    #                                  2000.
    'bcrypt.dll', 'd3d12.dll', 'dbghelp.dll'
)

# The DLLs that are not in-box and are shipped inside the package beside
# duckling.exe. An import of one of these is correct; an import of anything else
# outside $InBox is the defect this script exists to catch.
#
# **Naming one here is a promise, and it is kept somewhere else.** This script
# reads a binary and cannot see a package, so it cannot tell whether the file is
# really being staged. `build-msix.ps1` checks that each of these five landed
# beside the executable before it packs, and `install.ps1` copies the same five
# for the side-loaded route. A name added here and nowhere else buys an
# application that starts on this machine and on no other, which is exactly the
# failure slipcase-desktop shipped.
#
# The four Visual C++ runtime DLLs, taken from the Visual Studio redistributable
# directory. They are here because `+crt-static` cannot link the prebuilt ONNX
# Runtime; `.cargo/config.toml` is where that is argued at length.
#
# DirectML is the fifth and is a finding of its own, measured 2026-09-05. The
# Windows dist `ort` chooses is `ms@1.28.0/x86_64-pc-windows-msvc+directml`, so
# DirectML is linked in whether or not anything asks for it - docling.rs runs
# the CPU provider and Duckling never selects another - and `directml.dll`
# becomes a hard import the process cannot start without. In-box DirectML began
# at Windows 10 10.0.18362 and `AppxManifest.xml.in` declares a floor of
# 10.0.17763, so relying on the machine's copy would promise a Windows that has
# none; the copy this machine does have is 1.0.200713, from July 2020, against
# the 1.15.4 that pyke ships beside the `onnxruntime.lib` actually linked.
# Shipping their copy is the only way the two are known to match. It does not
# make that floor proven - whether 1.15.4 loads on 1809 at all is untested, and
# README.md 2 says what to do about it if it ever matters.
$ShippedBeside = @(
    'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll',
    'directml.dll'
)

# API set contracts are resolved by the loader from the schema inside Windows
# itself; there is no file to be missing. api-ms-win-crt-* is the Universal C
# Runtime, which is a Windows component from Windows 10 onward - it is the
# *Visual C++* runtime beside it that is not.
$InBoxPrefixes = @('api-ms-win-', 'ext-ms-win-')

if (-not $Binary) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Binary = Join-Path $here '..\..\target\release\duckling.exe'
    # `[build] target-dir` moves the target directory and no environment
    # variable then says so, which is why the packaging scripts ask cargo.
    $meta = cargo metadata --format-version 1 --no-deps 2>$null | ConvertFrom-Json
    if ($meta) { $Binary = Join-Path $meta.target_directory 'release\duckling.exe' }
}

if (-not (Test-Path $Binary)) { Refuse "no binary at $Binary - run 'cargo build --release' first" }
$bytes = [System.IO.File]::ReadAllBytes($Binary)

function U16([int] $at) { return [System.BitConverter]::ToUInt16($bytes, $at) }
function U32([int] $at) { return [System.BitConverter]::ToUInt32($bytes, $at) }

if ((U16 0) -ne 0x5A4D) { Refuse "$Binary does not start with MZ" }
$pe = [int](U32 0x3C)
if ((U32 $pe) -ne 0x00004550) { Refuse "$Binary has no PE signature at e_lfanew" }

$sizeOfOptional = [int](U16 ($pe + 20))
$opt = $pe + 24
$magic = U16 $opt
if ($magic -ne 0x20B) { Refuse ("$Binary is not PE32+ (magic 0x{0:X}) - this build targets x64" -f $magic) }

# PE32+ data directories begin 112 bytes into the optional header; entry 1 is
# the import table and entry 13 is the delay-load table. Both are walked: a
# delay-loaded DLL is just as absent on the machine that lacks it, it merely
# fails later.
$importRva = U32 ($opt + 112 + (1 * 8))
$delayRva  = U32 ($opt + 112 + (13 * 8))

$sections = @()
$sectionTable = $pe + 24 + $sizeOfOptional
for ($i = 0; $i -lt [int](U16 ($pe + 6)); $i++) {
    $s = $sectionTable + ($i * 40)
    $sections += [pscustomobject]@{
        Virtual = U32 ($s + 12)
        Size    = [Math]::Max((U32 ($s + 8)), (U32 ($s + 16)))
        Raw     = U32 ($s + 20)
    }
}

function Offset([uint32] $rva) {
    foreach ($s in $sections) {
        if ($rva -ge $s.Virtual -and $rva -lt ($s.Virtual + $s.Size)) {
            return [int]($rva - $s.Virtual + $s.Raw)
        }
    }
    Refuse ("RVA 0x{0:X} falls in no section" -f $rva)
}

function NameAt([uint32] $rva) {
    $at = Offset $rva
    $end = $at
    while ($bytes[$end] -ne 0) { $end++ }
    return [System.Text.Encoding]::ASCII.GetString($bytes, $at, $end - $at)
}

$imports = @()
if ($importRva -ne 0) {
    $at = Offset $importRva
    while ((U32 ($at + 12)) -ne 0) {      # the Name RVA; a zero descriptor ends the table
        $imports += NameAt (U32 ($at + 12))
        $at += 20
    }
}
if ($delayRva -ne 0) {
    $at = Offset $delayRva
    while ((U32 ($at + 4)) -ne 0) {       # DllNameRVA
        $imports += NameAt (U32 ($at + 4))
        $at += 32
    }
}

if ($imports.Count -eq 0) { Refuse "$Binary imports nothing, which cannot be right - the parse is wrong" }

$unknown = @()
$shipped = @()
foreach ($dll in $imports) {
    $lower = $dll.ToLowerInvariant()
    $ok = $InBox -contains $lower
    if (-not $ok) {
        foreach ($p in $InBoxPrefixes) { if ($lower.StartsWith($p)) { $ok = $true } }
    }
    if (-not $ok -and ($ShippedBeside -contains $lower)) {
        $ok = $true
        if ($shipped -notcontains $lower) { $shipped += $lower }
    }
    if (-not $ok -and ($unknown -notcontains $dll)) { $unknown += $dll }
}

$distinct = $imports | Sort-Object -Unique
Write-Host "check-imports: $Binary"
Write-Host "  $($distinct.Count) distinct imports, $($shipped.Count) shipped in the package, $($unknown.Count) neither"

if ($unknown.Count -gt 0) {
    foreach ($dll in $unknown) { Write-Host "  UNKNOWN  $dll" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'A DLL that is not part of Windows and not in the package has to be' -ForegroundColor Yellow
    Write-Host 'on the machine before Duckling will start, and a Store tester will' -ForegroundColor Yellow
    Write-Host 'have a clean machine.' -ForegroundColor Yellow
    Write-Host 'If it is genuinely in-box, add it to $InBox above and say how that' -ForegroundColor Yellow
    Write-Host 'was confirmed. If it is not, either remove the dependency or add it' -ForegroundColor Yellow
    Write-Host 'to $ShippedBeside and make build-msix.ps1 and install.ps1 stage it.' -ForegroundColor Yellow
    exit 1
}

# The shipped ones are listed rather than merely counted, because they are the
# claim this script cannot verify and the reader should see which files the
# package is now on the hook for.
foreach ($dll in ($shipped | Sort-Object)) {
    Write-Host "  in the package  $dll"
}
Write-Host '  every import is in-box or ships beside the executable' -ForegroundColor Green
exit 0
