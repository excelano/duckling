# Run the Windows App Certification Kit against a package that already exists,
# and apply the same gate `build-msix.ps1 -Certify` applies.
#
# From an **elevated** prompt, which is the whole reason this is its own script:
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\certify.ps1
#   ...\certify.ps1 -Package dist\Duckling-0.1.1.0-x64.msix   # or name one
#
# WHY THIS EXISTS AND `build-msix.ps1 -Certify` IS NOT ENOUGH
#
# That switch implies `-SelfSign`, so it re-stages 821 MB and re-packs 605 MB
# before it tests anything. On 2026-09-05 this machine did not have the room,
# the kit was run by hand instead, and `-ReadReport` applied the gate
# afterwards; `SUBMITTING.local.md` wrote down that the script should one day
# take an existing package. This is that, kept separate rather than folded in,
# because the two scripts want different things from the person running them:
# `build-msix.ps1` wants an ordinary prompt and must never need elevation, and
# the kit will not run without it.
#
# It tests the package it is given and rebuilds nothing. That is the point, and
# it is also the thing to be careful about: the package must be the one just
# built, and the gate below says so out loud rather than trusting the file name.
#
# THE GATE IS NOT DUPLICATED HERE
#
# `build-msix.ps1` holds `KNOWN_FINDINGS` and the report reader, and this hands
# the report back to it with `-ReadReport`. One list of known findings, in the
# file where the reasoning for each entry is written. A second copy would drift
# from it silently, and the first thing to drift would be the entry that says
# which failure was decided on and by whom.
#
# WHAT THE KIT WILL SAY, SO IT IS NOT A SURPRISE
#
# `Blocked executables` fails and the overall result is PASS. The kit marks that
# task optional for Centennial packages and this is one. On 0.1.0, 2026-09-05,
# it reported 58 messages and all 58 were traced before any of it was baselined:
# forty are the kit's three-letter scan finding reg, cmd, csi, cdb and dnx
# inside 734 MB of model weights, and the rest are the Rust standard library's
# spawn path and the `ShellExecuteW` behind the Open and Show in folder buttons.
# `build-msix.ps1`'s KNOWN_FINDINGS comment is the long form, and `RELEASE.md`
# carries the decision to submit with it failing, which is David's and was taken
# once already for slipcase-desktop.
#
# **The count moves between builds and that is expected.** Those three-letter
# matches are byte coincidences in compressed weights; a different binary
# reshuffles them. A number that has changed is not by itself a finding.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # The package to test. Defaults to the throwaway-signed one this version's
    # build wrote to `dist\`. Not the copy under `dist\submit\`: that one is
    # unsigned, and the kit installs what it tests.
    [string] $Package,
    # Where the report goes. Defaults beside the package as `wack-<version>.xml`,
    # which is what `-ReadReport` and `SUBMITTING.local.md` both expect.
    [string] $Report,
    # Test the package and write the report, then stop without applying the
    # gate. For a report to be read by a person first.
    [switch] $NoGate
)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)

function Refuse([string] $message) {
    Write-Error "certify.ps1: $message"
}

# --- elevation, first, because everything after it is wasted without it ------

$elevated = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Refuse @"
the Windows App Certification Kit needs an elevated session.

Start an administrator PowerShell and run:
  powershell -ExecutionPolicy Bypass -File $here\certify.ps1

or from this one:
  Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','$here\certify.ps1'
"@
}

# --- the version, from the one parser ---------------------------------------

# Asked rather than read out of a file name, so that a package left over from
# another version cannot be tested under this version's name. Not `bash` off
# PATH: on a machine with WSL that name is a Linux distribution where this
# checkout is at another path.
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Refuse 'git is not on PATH, and version.sh needs the shell Git for Windows ships' }
$gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
$sh = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path $sh)) { $sh = Join-Path $gitRoot 'usr\bin\sh.exe' }
if (-not (Test-Path $sh)) { Refuse "no shell found beside $($git.Source)" }
$versionScript = (Join-Path $here '..\version.sh').Replace('\', '/')
$version = (& $sh $versionScript --appx | Select-Object -First 1).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+\.0$') {
    Refuse "version.sh --appx said '$version', which is not four parts ending in 0"
}

# --- the package ------------------------------------------------------------

if (-not $Package) { $Package = Join-Path $root "dist\Duckling-$version-x64.msix" }
if (-not (Test-Path $Package)) {
    Refuse @"
no package at $Package. The kit tests a signed package, which is the one
`build-msix.ps1 -SelfSign` writes to dist\:
  powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -SelfSign
"@
}
$packageItem = Get-Item $Package

if ($packageItem.Name -notlike "*$version*") {
    Refuse "$($packageItem.Name) does not carry version $version - pass -Package deliberately if that is really what should be tested"
}

# The kit installs what it tests, and an unsigned package will not install. The
# signature is looked for inside the package rather than inferred from the name:
# `dist\submit\` holds an unsigned copy of exactly the same version, and a file
# name is not a signature.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($packageItem.FullName)
try {
    $signed = $null -ne $zip.GetEntry('AppxSignature.p7x')
} finally {
    $zip.Dispose()
}
if (-not $signed) {
    Refuse @"
$($packageItem.Name) carries no AppxSignature.p7x, so it is the unsigned copy -
the one that goes to the Store, and the one the kit cannot install. Test the
signed package in dist\ instead; the Store signs what it distributes.
"@
}

# --- appcert ----------------------------------------------------------------

$appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\App Certification Kit\appcert.exe'
if (-not (Test-Path $appcert)) {
    Refuse "no appcert.exe at $appcert - the App Certification Kit is a separate feature of the Windows SDK installer"
}

if (-not $Report) { $Report = Join-Path $packageItem.DirectoryName "wack-$version.xml" }

# The report is removed first, and the one that appears is then checked for
# being newer than this run. Both, and the reasoning is build-msix.ps1's,
# learned there: `appcert` refuses to overwrite a report, printing "Please
# specify a unique report file name" and stopping before it runs a single test.
# The stale file is still there and still parses, so a gate that only checks for
# a file reports the previous package's verdict as though it were this one's.
if (Test-Path $Report) {
    Write-Host "removing the previous report at $Report"
    Remove-Item $Report -Force
}

Write-Host ("testing {0} ({1:N0} MB)" -f $packageItem.Name, ($packageItem.Length / 1MB))
Write-Host "  report  $Report"
Write-Host '  this takes several minutes on a package this size, and the kit'
Write-Host '  installs it, launches it and closes it while it works.'
Write-Host ''

$startedAt = Get-Date
& $appcert reset | Out-Null
& $appcert test -appxpackagepath $packageItem.FullName -reportoutputpath $Report

if (-not (Test-Path $Report)) {
    Refuse "the certification kit wrote no report to $Report"
}
if ((Get-Item $Report).LastWriteTime -lt $startedAt) {
    Refuse "the report at $Report is older than this run - the kit did not write it, so nothing in it would be about this package"
}

Write-Host ''
Write-Host ("the kit finished in {0:mm\:ss}" -f ((Get-Date) - $startedAt))

# --- the gate, which lives in build-msix.ps1 --------------------------------

if ($NoGate) {
    Write-Host ''
    Write-Host '-NoGate: the report is written and unread. Apply the gate with:'
    Write-Host "  powershell -ExecutionPolicy Bypass -File $here\build-msix.ps1 -ReadReport `"$Report`""
    return
}

Write-Host ''
& powershell -ExecutionPolicy Bypass -File (Join-Path $here 'build-msix.ps1') -ReadReport $Report
if ($LASTEXITCODE -ne 0) {
    Refuse "the gate refused the report at $Report - read what it printed above, and take anything new to David rather than adding a name to KNOWN_FINDINGS"
}

# The kit installs the package it tests and takes it away again afterwards, and
# the next thing to happen is CHECKLIST.md against an installed one. So this
# says whether it is still there rather than leaving it to be discovered by a
# Start menu entry that has gone.
$packageName = 'Excelano.Duckling'
$identityFile = Join-Path $here 'identity.psd1'
if (Test-Path $identityFile) { $packageName = (Import-PowerShellDataFile $identityFile).Name }
$installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
if (-not $installed) {
    Write-Host ''
    Write-Host 'the kit removed the package it installed. Put it back before the walkthrough:'
    Write-Host "  Add-AppxPackage `"$($packageItem.FullName)`""
} else {
    Write-Host ''
    Write-Host "still installed: $($installed.PackageFullName)"
}

Write-Host ''
Write-Host 'the kit is done. What is left before this version can be submitted is'
Write-Host 'CHECKLIST.md against the installed package, and then:'
Write-Host "  powershell -ExecutionPolicy Bypass -File $here\submit.ps1"
Write-Host ''
Write-Host 'write what the kit said into packaging\windows\SUBMITTING.local.md - the'
Write-Host 'message count moves between builds and next time wants this one to compare to.'
