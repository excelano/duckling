# Find the five DLLs that ship inside the package beside duckling.exe, and
# refuse rather than return a short list.
#
# Two scripts need exactly this set - `build-msix.ps1` stages it into the MSIX
# and `install.ps1` copies it into the side-loaded directory - and a set that
# differed between them would produce an application that starts one way and not
# the other. So it is found once, here, and `check-imports.ps1` holds the
# matching list of names with the reasoning for why each one is not simply
# linked in.
#
# Dot-source it or call it; it writes one object per file with `Name` and
# `Path`, and throws if anything is missing.
#
#   $runtime = & packaging\windows\runtime-files.ps1
#
# WHY THESE FILES ARE NOT LINKED IN
#
# `+crt-static` cannot link the prebuilt ONNX Runtime `ort` fetches for this
# target: it was compiled against the dynamic CRT and the link fails with 63
# unresolved `__imp_` externals. Measured on the Windows lane 2026-09-05;
# `.cargo/config.toml` carries the whole argument and the decision that followed
# from it. DirectML arrives in the same library and is a separate finding, which
# the comment above its lookup below records.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # The Cargo target directory, so that DirectML can be taken from the
    # build ONNX Runtime was actually linked from. Defaulted in the body.
    [string] $TargetDir
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)

function Refuse([string] $message) {
    throw "runtime-files.ps1: $message"
}

# --- the Visual C++ runtime -------------------------------------------------

# From the Visual Studio redistributable directory rather than from
# C:\Windows\System32. The System32 copy is whatever this machine's last
# Redistributable installer left there and is not ours to redistribute; the
# redist directory is the one Microsoft ships *for* app-local deployment, and it
# is the one whose licence covers putting these files in a package.
#
# vswhere is asked rather than a path being guessed, the same way the Linux
# scripts ask cargo where its target directory is. It is at a fixed location
# under Program Files (x86) on every machine that has any Visual Studio,
# including a Build Tools install with no IDE.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    Refuse "no vswhere at $vswhere - the Visual C++ runtime files ship with Visual Studio, and this lane needs it for the C compiler anyway"
}
$vsPath = & $vswhere -latest -products * -property installationPath
if (-not $vsPath) { Refuse 'vswhere found no Visual Studio installation' }
$vsPath = ($vsPath | Select-Object -First 1).Trim()

# The newest toolset under Redist\MSVC. `Microsoft.VC143.CRT` is the v143
# toolset's directory name; the wildcard covers a machine whose newest toolset
# has moved on, which is a thing that happens without anybody here deciding it.
$redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
if (-not (Test-Path $redistRoot)) {
    Refuse "no redistributable directory at $redistRoot - install the 'C++ Redistributable MSMs' or the ATL/MFC component that carries it"
}
$crt = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version] $_.Name } -Descending |
    ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $crt) { Refuse "no x64 Microsoft.VC*.CRT directory under $redistRoot" }

# Four and not the whole directory. `concrt140`, `msvcp140_2`,
# `msvcp140_atomic_wait`, `msvcp140_codecvt_ids`, `vccorlib140` and
# `vcruntime140_threads` sit beside them and this binary imports none of them -
# `check-imports.ps1` lists exactly what the import table holds, and shipping a
# file nothing loads is a file that has to be certified and licensed for
# nothing.
$vcNames = 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll'

$files = @()
foreach ($name in $vcNames) {
    $path = Join-Path $crt.FullName $name
    if (-not (Test-Path $path)) { Refuse "no $name in $($crt.FullName)" }
    $files += [pscustomobject]@{ Name = $name; Path = (Resolve-Path $path).Path }
}

# --- DirectML ---------------------------------------------------------------

# Taken from the ONNX Runtime distribution that was actually linked, and found
# by reading the path `ort-sys`'s build script printed rather than by guessing
# at a cache layout.
#
# It matters that it is *that* copy. The dist pyke serves for this target is
# `x86_64-pc-windows-msvc+directml`, so DirectML is linked in whether or not
# anything asks for it, and `directml.dll` becomes an import the process cannot
# start without. The copy in the dist is the one `onnxruntime.lib` was built
# against - 1.15.4 when this was written - where this machine's in-box copy is
# 1.0.200713 from July 2020, and a Windows at the 10.0.17763 floor
# `AppxManifest.xml.in` declares has none at all, since in-box DirectML began at
# 10.0.18362. Pairing the library with its own DLL is the only version
# relationship here that anybody has checked.
#
# The build script's `rustc-link-search=native=` line is the authority because
# it is what the linker was given. A cache directory named by content hash is
# not something to glob at: two of them can sit side by side after a dependency
# bump, and picking the wrong one pairs a 1.15 library with some other DirectML
# and says nothing.
if (-not $TargetDir) {
    $TargetDir = Join-Path $root 'target'
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Push-Location $root
        try {
            $meta = cargo metadata --format-version 1 --no-deps 2>$null | ConvertFrom-Json
            if ($meta) { $TargetDir = $meta.target_directory }
        } finally { Pop-Location }
    }
}

$outputs = Get-ChildItem (Join-Path $TargetDir 'release\build') -Directory -Filter 'ort-sys-*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'output' } |
    Where-Object { Test-Path $_ } |
    Sort-Object { (Get-Item $_).LastWriteTime } -Descending
if (-not $outputs) {
    Refuse "no ort-sys build output under $TargetDir\release\build - run 'cargo build --release' first"
}

$directml = $null
foreach ($output in $outputs) {
    $line = Select-String -LiteralPath $output -Pattern '^cargo:rustc-link-search=native=(.+)$' |
        Select-Object -First 1
    if (-not $line) { continue }
    $candidate = Join-Path $line.Matches[0].Groups[1].Value 'DirectML.dll'
    if (Test-Path $candidate) { $directml = (Resolve-Path $candidate).Path; break }
}
if (-not $directml) {
    Refuse "no DirectML.dll in the ONNX Runtime distribution ort-sys linked against - the newest build output under $TargetDir\release\build named a directory that has none, so either the dist changed shape or the link search line is gone"
}
$files += [pscustomobject]@{ Name = 'DirectML.dll'; Path = $directml }

$files
