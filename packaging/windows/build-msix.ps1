# Assemble the MSIX package the Microsoft Store distributes: the release
# executable, the models and pdfium that sit beside it, the manifest with the
# identity and the version substituted into it, and the four images the manifest
# names.
#
# The rule this works to is the one that matters: refuse loudly rather than
# produce something subtly wrong. A package quietly built from a debug binary
# says nothing at the moment it is made and everything days later. Every check
# below exists because the thing it checks cannot be seen by looking at the
# finished package.
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1
#   ...\build-msix.ps1 -SelfSign            # sign it, so it can be installed here
#   ...\build-msix.ps1 -SelfSign -Certify   # and run the certification kit
#
# WHAT THIS DOES NOT DO
#
# It does not submit, and it does not produce a signature that goes anywhere
# near a submission. The Store signs what it distributes, so `-SelfSign` exists
# only so that a package can be installed on this machine and looked at. The
# certificate it makes is a throwaway.
#
# This is segler's script, which is slipcase-desktop's, with the names changed,
# four assets where it checks six, an empty findings baseline, and one thing
# neither of those has: **the package carries 740 MB of models and a shared
# library**, staged into `models\` and `pdfium\` beside the executable, which is
# where `locate_assets` in `src/lib.rs` looks. DESIGN.md 8. Every measurement in
# the comments below was taken on one of those two repositories unless it says
# otherwise.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # The executable to package. With neither this nor a release build present
    # this refuses rather than building one: `cargo build --release` is the
    # caller's to run, the way it is for every other packaging script here.
    [string] $Binary,
    # Where to write the package and its staging tree. Defaulted in the body
    # rather than here: $PSScriptRoot is empty while parameters are being bound
    # in Windows PowerShell 5.1, so a default built from it is a refusal before
    # the script has run a line. `install.ps1` reads its own path in the body
    # for the same reason.
    [string] $OutDir,
    # Sign with a throwaway certificate whose subject is the manifest's
    # Publisher, so that the package can be installed here. Not for submission.
    [switch] $SelfSign,
    # Run the Windows App Certification Kit and fail on it. Needs elevation, and
    # needs the package to be installable, so it needs -SelfSign as well.
    [switch] $Certify,
    # Apply the -Certify gate to a report that already exists and do nothing
    # else. Needs no elevation and builds nothing, which is what makes the gate
    # checkable: breaking KNOWN_FINDINGS deliberately and watching this refuse
    # is the only way to know it still bites, and a kit run costs an elevated
    # session and several minutes.
    [string] $ReadReport
)

$ErrorActionPreference = 'Stop'

# What the Windows App Certification Kit says about this application every time,
# so that `-Certify` can be quiet about those and loud about anything else.
#
# **This is a record of what is known, not a claim that it is acceptable.**
# Whether to submit with a test failing is a decision, it is David's, and
# `RELEASE.md` carries it. Recording a finding here does not take it.
#
# One entry, from the first kit run, 2026-09-05, against
# `Duckling-0.1.0.0-x64.msix`. 23 of 24 tests passed. It was left empty until
# that run rather than copied from segler's, because a baseline copied from
# another application is a list of things somebody else measured.
#
# `Blocked executables` reported 58 messages and every one of them was traced
# before this line was written. They are four different things:
#
#   The model files          Forty of the fifty-eight. `layout_heron.onnx`,
#                            `bbox.onnx.data` and the rest "contain a blocked
#                            executable reference to" reg, cmd, csi, cdb, dnx -
#                            with casings like `cSI`, `DnX`, `REg`. The kit
#                            scans for those three-letter names case-insensitively
#                            and these are ONNX weights, so it is finding bytes.
#                            Measured rather than asserted: `layout_heron.onnx`
#                            is 172 MB and holds 20 occurrences of `cmd` where
#                            uniform random bytes would give 82. Every count in
#                            every model file came in *under* chance, which is
#                            what floating-point weights should do. There is
#                            nothing in them to remove.
#
#   pdfium and DirectML      The same scan on two prebuilt C libraries, and the
#                            same answer.
#
#   `cmd.exe` in the binary  Two hits, and the bytes around them settle it:
#                            `cmd.exe /e:ON /v:OFF /d /c "batch file ar` and
#                            `\cmd.exe/rustc/48a229ceaefd4985c50990b1411`. That
#                            second one carries the rustc commit hash, so it is
#                            the Rust standard library's own batch-file spawn
#                            path compiled in. `grep` finds no `Command::new`
#                            anywhere in `src/` or `tests/`. It arrives because
#                            `webbrowser` is linked, which comes under
#                            `egui-winit` and is what egui opens a hyperlink
#                            with. `Bash` is the same kind of thing and not even
#                            a process reference: all four of its hits are
#                            inside lists of names - a syntax-highlighting
#                            language list and a locale list that contains
#                            *Bashkir*.
#
#   `ShellExecuteW`          **The one that is real, and it is a feature.**
#                            `opener::open` and `opener::reveal` at
#                            `src/main.rs:478` and `:483` are the preview pane's
#                            Open and Show in folder buttons, which
#                            `packaging/store-listing.md` advertises. Duckling
#                            does launch something: the file a person just
#                            converted, in whatever opens it, when they ask.
#                            This is where Duckling's finding genuinely differs
#                            from segler's, and the certification note should
#                            say so plainly rather than reuse that repository's
#                            wording. `CreateProcessW` beside it is the same
#                            std::process linkage as the `cmd.exe` strings.
#
# The test is `OPTIONAL="TRUE"` in the report and the package is
# `APP_TYPE="Centennial"`, which is why an overall of PASS sits over a test
# reading FAIL. slipcase-desktop read the same fact out of the kit's own
# `configuration.xml`, where the task is marked
# `OPTIONAL_FOR_APP_TYPES="Centennial"`; that attribute is not in the
# configuration shipped with SDK 10.0.26100 on this machine, so the report's own
# attribute is what was checked here. Both say the same thing.
#
# **This is not a new decision. slipcase-desktop took it on 2026-08-28: submit
# with it failing.** That application had the same two real messages this one
# has - the `cmd.exe` strings and `ShellExecuteW` under `opener` - and its
# 0.1.2 passed certification and was published on 2026-08-30 with the test
# failing exactly as it fails here. Its rejection, the one that produced
# `check-imports.ps1`, was policy 10.2.4.1 over VCRUNTIME140.dll and had nothing
# to do with this test.
#
# What is new here is the volume rather than the kind: slipcase-desktop traced
# six messages and this run has fifty-eight, because 734 MB of model weights and
# two prebuilt C libraries give the three-letter scan far more bytes to find
# itself in. That is worth saying in the certification note, since a reviewer
# reading fifty-eight lines is reading a longer list than any Excelano
# submission has carried before.
#
# `DPIAwarenessValidation` is not in this list and that is worth saying, because
# it is slipcase-desktop's second entry: the kit reads the PE application
# manifest, and that application had none until a `build.rs` was written, so it
# was reported as not DPI aware. This one embedded the manifest from the first
# build and the test passed on the first run.
#
# Shrink this list when a finding goes away; the run says so when one does.
$KNOWN_FINDINGS = @{
    'Blocked executables' = 'FAIL'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }

function Refuse([string] $message) {
    Write-Error "build-msix.ps1: $message"
}

# Read a certification report and apply the gate. A function so that it can
# be run against a report on its own, which is the only way to check that the
# gate bites without an elevated session and a fresh kit run: `-ReadReport`
# takes that path.
function Test-CertificationReport([string] $report) {
    # The verdict is read out of the report rather than out of an exit code. A
    # kit that ran and failed and a kit that never ran are different things, and
    # this must never call the second one a pass: a missing verdict is a refusal
    # too.
    [xml] $xml = Get-Content $report
    $overall = $xml.REPORT.OVERALL_RESULT
    if (-not $overall) {
        Refuse "the certification kit's report at $report has no OVERALL_RESULT - read it rather than trusting this script"
    }
    # Read out of `<TEST><RESULT>` and not out of an `OVERALL_RESULT` attribute.
    # Only the report element carries that attribute; every individual test
    # states its verdict in a child element, so the first version of this printed
    # nothing at all while a test was failing, and said only "WARNING". Worse
    # than useless: the kit's own overall verdict does not escalate a failing
    # test, so a test can read FAIL under an overall of WARNING.
    # Whatever this refuses on, it now says what.
    $unexpected = @()
    $seen = @{}
    foreach ($test in $xml.SelectNodes('//TEST')) {
        $node = $test.SelectSingleNode('RESULT')
        if (-not $node) { continue }
        $verdict = $node.InnerText.Trim()
        if ($verdict -eq 'PASS') { continue }
        $name = $test.GetAttribute('NAME')
        $seen[$name] = $verdict
        $expected = $KNOWN_FINDINGS[$name]
        if ($expected -eq $verdict) {
            Write-Host "$verdict  $name  (known - see RELEASE.md)"
        } else {
            $unexpected += "$verdict $name"
            Write-Host "$verdict  $name  ** NOT IN THE KNOWN LIST **"
        }
        foreach ($message in $test.SelectNodes('.//MESSAGE')) {
            $text = $message.GetAttribute('TEXT')
            if ($text) { Write-Host "        $text" }
        }
    }
    # A known finding that stopped being reported is good news and not a
    # refusal, but it is said out loud, because a baseline nobody ever shrinks
    # becomes a list of things that used to be true.
    foreach ($name in $KNOWN_FINDINGS.Keys) {
        if (-not $seen.ContainsKey($name)) {
            Write-Host "gone   $name is no longer reported - take it out of KNOWN_FINDINGS"
        }
    }
    Write-Host "certification kit: $overall  ($report)"

    # The gate is the comparison against the list, not the count of things that
    # are not PASS. A finding that will be reported on every run this project
    # ever does would, if refused on, make `-Certify` refuse always - and a
    # check whose red is the normal state announces nothing. This one is quiet
    # when the kit says what it said last time and loud when it says anything
    # else.
    #
    # An overall of FAIL is still a refusal on its own. The kit does not
    # escalate a failing test into it, so if it does say FAIL it has decided
    # something the per-test list does not cover.
    if ($unexpected) {
        Refuse "the certification kit reported $($unexpected.Count) finding(s) not in the known list: $($unexpected -join '; ') - certification runs it too, so this comes back"
    }
    if ($overall -eq 'FAIL') {
        Refuse 'the Windows App Certification Kit says FAIL overall'
    }
}


# Nothing above this line has run yet, which is the point: a report is read on
# its own, without building or signing anything.
if ($ReadReport) {
    if (-not (Test-Path $ReadReport)) { Refuse "no report at $ReadReport" }
    Test-CertificationReport (Resolve-Path $ReadReport).Path
    exit 0
}


# --- the identity, from one place -------------------------------------------

# `identity.psd1` holds what Partner Center assigned. The manifest keeps its
# placeholders, so that nothing has to be edited per build and so that the one
# file a person might mistype lives beside a comment saying where its values
# came from.
#
# It is not committed - `.gitignore` says why - so a fresh checkout does not
# have one, and the refusal names the template rather than just the missing
# path. A build script whose first failure is "no such file" teaches nothing.
$identityFile = Join-Path $here 'identity.psd1'
if (-not (Test-Path $identityFile)) {
    Refuse "no identity at $identityFile - copy identity.psd1.example beside it and fill in what Partner Center shows under Product management, Product identity"
}
$identity = Import-PowerShellDataFile $identityFile
foreach ($field in 'Name', 'Publisher', 'PublisherDisplayName') {
    if (-not $identity.$field) { Refuse "identity.psd1 has no $field" }
}
# The one value with a shape worth checking. `Publisher` is an X.500 string and
# the display name is what gets put there by mistake; a package whose Publisher
# does not match the reservation is rejected at upload, which is the most
# expensive place to find out.
if ($identity.Publisher -notmatch '^CN=') {
    Refuse "identity.psd1's Publisher is '$($identity.Publisher)', which is not an X.500 string - Partner Center's Package/Identity/Publisher begins CN="
}

# --- the version, from the one parser ---------------------------------------

# `packaging/version.sh` is the only thing that reads Cargo.toml's version, and
# it is asked here rather than copied, which is the whole reason it takes an
# argument. It is POSIX sh, so it needs a shell, and Git for Windows ships one.
#
# Not `bash` off PATH. On a machine with WSL that name resolves to
# C:\Windows\System32\bash.exe, which runs inside a Linux distribution where
# this checkout is at a different path, so version.sh would read a Cargo.toml
# that is not this one - or nothing at all.
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Refuse 'git is not on PATH, and version.sh needs the shell Git for Windows ships' }
$gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
$sh = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path $sh)) { $sh = Join-Path $gitRoot 'usr\bin\sh.exe' }
if (-not (Test-Path $sh)) {
    Refuse "no shell found beside $($git.Source) - version.sh is POSIX sh and needs the one Git for Windows installs"
}
$versionScript = (Join-Path $here '..\version.sh').Replace('\', '/')
$version = & $sh $versionScript --appx
if ($LASTEXITCODE -ne 0 -or -not $version) {
    Refuse 'version.sh --appx would not answer'
}
$version = ($version | Select-Object -First 1).Trim()
# The Store requires four parts with the fourth 0, and version.sh says so too.
# This is the check that shelling out produced what was asked for rather than a
# message on standard output.
if ($version -notmatch '^\d+\.\d+\.\d+\.0$') {
    Refuse "version.sh --appx said '$version', which is not four parts ending in 0"
}

# --- the executable ---------------------------------------------------------

# Cargo is asked where its target directory is rather than guessed at, because
# `[build] target-dir` in a Cargo configuration file moves it and no
# environment variable then says so. Every packaging script here asks.
if (-not $Binary) {
    $targetDir = $null
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Push-Location $root
        try {
            $meta = cargo metadata --format-version 1 --no-deps 2>$null | ConvertFrom-Json
            if ($meta) { $targetDir = $meta.target_directory }
        } finally { Pop-Location }
    }
    if (-not $targetDir) { $targetDir = Join-Path $root 'target' }
    $Binary = Join-Path $targetDir 'release\duckling.exe'
}
if (-not (Test-Path $Binary)) {
    Refuse "no executable at $Binary - run 'cargo build --release' first"
}
$Binary = (Resolve-Path $Binary).Path

# Two things read straight out of the PE header, because neither is visible in
# a finished package and both are shipping defects.
#
# The architecture, because the manifest declares x64, and a package whose
# declaration disagrees with its executable installs and then fails to launch.
#
# The subsystem, because `main.rs` carries `windows_subsystem = "windows"` only
# when `debug_assertions` is off - so a debug binary packaged by mistake is a
# console subsystem one, and a console window behind the application is a defect
# slipcase-desktop found by eye once already. It is the cheapest check in this
# file and it guards the one thing here that cost an eye to notice.
$pe = [System.IO.File]::ReadAllBytes($Binary)
$peOffset = [BitConverter]::ToInt32($pe, 0x3C)
$machine = [BitConverter]::ToUInt16($pe, $peOffset + 4)
$subsystem = [BitConverter]::ToUInt16($pe, $peOffset + 92)
if ($machine -ne 0x8664) {
    Refuse ("$Binary is machine 0x{0:X4}, and AppxManifest declares x64" -f $machine)
}
if ($subsystem -ne 2) {
    Refuse "$Binary is not a Windows GUI subsystem executable (subsystem $subsystem) - a debug build is a console one, and packaging that puts a console window behind the application"
}

# The imports, because a DLL that is not part of Windows has to already be on
# the machine before the application will start, and the machine that matters
# is a certification tester's rather than this one. Slipcase 0.1.1 was packaged,
# certified, submitted and failed on exactly that: it imported VCRUNTIME140.dll
# from the Visual C++ Redistributable, which every machine here has and a clean
# Windows does not. The check is its own script because CI runs it too, and it
# is here because this is the last place a bad binary can still be stopped.
& (Join-Path $here 'check-imports.ps1') -Binary $Binary
if ($LASTEXITCODE -ne 0) {
    Refuse "$Binary imports a DLL that does not ship with Windows - see above"
}

# --- the tools --------------------------------------------------------------

# Neither is on PATH on a stock machine and both are stock in the SDK. The
# newest SDK is taken, and the x64 build of the tool because that is the
# architecture everything else here is.
function Find-SdkTool([string] $name) {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path $kits)) { return $null }
    Get-ChildItem $kits -Directory |
        Where-Object { $_.Name -match '^10\.' } |
        Sort-Object { [version] $_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName "x64\$name" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
}
$makeappx = Find-SdkTool 'makeappx.exe'
if (-not $makeappx) { Refuse 'no makeappx.exe in any Windows SDK - install the Windows 10/11 SDK' }

# --- the staging tree -------------------------------------------------------

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path
$stage = Join-Path $OutDir 'msix-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage 'Assets') -Force | Out-Null

Copy-Item $Binary (Join-Path $stage 'duckling.exe')

# --- the models and pdfium --------------------------------------------------
#
# The whole reason this package is what it is. `locate_assets` in `src/lib.rs`
# runs before any thread exists and names `models\` and `pdfium\` beside the
# canonicalized executable, so the layout here is not a choice: it is the same
# relative layout `/usr/lib/duckling` has on Linux and `Contents/MacOS` has in a
# bundle. DESIGN.md 2 and 8.
#
# Fetched rather than built, verified by hash by the script that fetches them,
# and copied rather than re-verified here: `packaging/fetch-models.sh` is
# idempotent and `preflight.sh` is the gate that asks whether they match. What
# this refuses on is their absence, because the alternative is an MSIX that
# installs, launches, and cannot convert a PDF - which is a defect no check
# after this point would see.
$models = Join-Path $root '.models'
$pdfium = Join-Path $root '.pdfium\lib'
if (-not (Test-Path $models)) {
    Refuse "no models at $models - run packaging/fetch-models.sh (it needs the Git Bash that Git for Windows installs)"
}
if (-not (Test-Path (Join-Path $pdfium 'pdfium.dll'))) {
    Refuse "no pdfium.dll at $pdfium - run packaging/fetch-models.sh"
}
Copy-Item $models (Join-Path $stage 'models') -Recurse
New-Item -ItemType Directory -Path (Join-Path $stage 'pdfium') -Force | Out-Null
Copy-Item (Join-Path $pdfium '*') (Join-Path $stage 'pdfium')

# --- the runtime DLLs -------------------------------------------------------
#
# The four Visual C++ runtime files and DirectML, beside the executable rather
# than in a subdirectory of their own: the loader looks in the application
# directory and nowhere this package could put them instead.
#
# This is the promise `check-imports.ps1` makes and cannot keep. That script
# reads an import table and lets those five through on the strength of their
# being shipped; here is where they are shipped, and the check below is what
# turns the promise into something verified. An empty `pdfium\` would fail a
# conversion; a missing `vcruntime140.dll` fails the launch, on the tester's
# machine and not on this one.
#
# `.cargo/config.toml` says why they are not simply linked in, and
# `runtime-files.ps1` says where each comes from and why that source rather than
# System32.
$runtime = & (Join-Path $here 'runtime-files.ps1')
foreach ($file in $runtime) {
    Copy-Item $file.Path (Join-Path $stage $file.Name) -Force
}
foreach ($file in $runtime) {
    if (-not (Test-Path (Join-Path $stage $file.Name))) {
        Refuse "$($file.Name) did not land beside the executable in $stage"
    }
}
Write-Host "staged $($runtime.Count) runtime DLLs beside duckling.exe: $(($runtime.Name) -join ', ')"

# Said out loud rather than assumed, because it is the one number about this
# package a person needs before they look at a store listing or an upload form.
$staged = (Get-ChildItem $stage -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("staged {0:N0} MB into $stage" -f ($staged / 1MB))

$assets = Join-Path $here 'assets'
Copy-Item (Join-Path $assets '*.png') (Join-Path $stage 'Assets')
# The whole directory is copied and then the four the manifest names are
# checked, rather than the four being copied by name. The qualified variants
# beside them are resolved by `resources.pri` and never named anywhere, so a
# copy-by-name list would silently stop shipping them the day one was added.
#
# Four where segler checks six. The two it has and this does not are its
# file-type logos: Duckling owns no format and gives the types it reads no logo,
# which `AppxManifest.xml.in` argues and `make-ico` follows.
foreach ($image in 'StoreLogo.png', 'Square150x150Logo.png', 'Square44x44Logo.png',
                   'Wide310x150Logo.png') {
    if (-not (Test-Path (Join-Path $stage "Assets\$image"))) {
        Refuse "no $image in $assets - run 'cargo run --release' in packaging/windows/make-ico"
    }
}

# --- the manifest -----------------------------------------------------------

$manifest = Get-Content (Join-Path $here 'AppxManifest.xml.in') -Raw
$manifest = $manifest.
    Replace('@IDENTITY_NAME@', $identity.Name).
    Replace('@PUBLISHER@', $identity.Publisher).
    Replace('@PUBLISHER_DISPLAY_NAME@', $identity.PublisherDisplayName).
    Replace('@VERSION_APPX@', $version)

# A placeholder that survived substitution is a package that installs and is
# wrong, so it is looked for rather than assumed away. This catches a
# placeholder added to the template and not to this script, which is the
# realistic way the two part company.
$left = [regex]::Matches($manifest, '@[A-Z_]+@') |
    ForEach-Object { $_.Value } | Sort-Object -Unique
if ($left) {
    Refuse "AppxManifest.xml.in has placeholders this script does not substitute: $($left -join ', ')"
}

# UTF-8 with no byte order mark. `Out-File -Encoding utf8` in Windows
# PowerShell 5.1 writes one, and a manifest beginning with a BOM is malformed
# XML as far as makeappx is concerned.
[System.IO.File]::WriteAllText(
    (Join-Path $stage 'AppxManifest.xml'),
    $manifest,
    (New-Object System.Text.UTF8Encoding $false))

# --- the resource index -----------------------------------------------------

# Without this the package ships the images and the shell reads only the four
# the manifest names by literal path: every `scale-` and `altform-` qualifier
# beside them is inert, because a qualifier is resolved through the resource
# index and nowhere else.
#
# The visible cost of not having one was the taskbar. `BackgroundColor` is
# `transparent`, so Windows plates the icon in the user's accent colour, and on
# slipcase-desktop that drew the application on a purple square while the
# side-loaded install drew the same icon unplated. The `altform-unplated` asset
# is what stops it, and it was in that package and doing nothing until this step
# existed.
#
# The configuration is written outside the staging tree on purpose. `makepri`
# indexes the directory it is given, so a configuration file left inside it
# becomes a resource of the package.
$makepri = Find-SdkTool 'makepri.exe'
if (-not $makepri) { Refuse 'no makepri.exe in any Windows SDK' }
$priConfig = Join-Path $OutDir 'priconfig.xml'
# `en-US` matches the `<Resource Language="en-us" />` the manifest declares. If
# the two disagree the index has no default language and the shell falls back to
# the literal paths, which is the failure this whole step exists to remove -
# and it fails silently, so it is spelled once here from the manifest's value.
# It was `en-GB` until 2026-09-06; the manifest carries the why.
& $makepri createconfig /cf $priConfig /dq en-US /o | Out-Null
if ($LASTEXITCODE -ne 0) { Refuse "makepri createconfig failed ($LASTEXITCODE)" }

# The default configuration splits qualified resources into *resource packages*,
# which is right for a bundle and wrong for one monolithic package. Left alone,
# `makepri` wrote `resources.scale-125.pri` and four siblings and left the scale
# variants out of the main index entirely: `makepri dump` of the installed
# package found no `scale-125` anywhere in it, so every one of those images
# shipped and resolved to nothing. This is a package, not a bundle, so the
# splitting is turned off and everything lands in one index.
[xml] $priXml = Get-Content $priConfig
foreach ($split in @($priXml.SelectNodes('//autoResourcePackage'))) {
    $split.ParentNode.RemoveChild($split) | Out-Null
}
$priXml.Save($priConfig)

& $makepri new /pr $stage /cf $priConfig /of (Join-Path $stage 'resources.pri') /o | Out-Null
if ($LASTEXITCODE -ne 0) { Refuse "makepri new failed ($LASTEXITCODE)" }
Remove-Item $priConfig -Force
if (-not (Test-Path (Join-Path $stage 'resources.pri'))) {
    Refuse 'makepri reported success and wrote no resources.pri'
}
# Nothing should have been split out. If a `resources.<qualifier>.pri` appears
# beside the main one, the configuration edit above stopped working and the
# variants are silently unresolvable again - which is a thing that looks like a
# working package right up until somebody photographs a taskbar.
$split = Get-ChildItem (Join-Path $stage 'resources.*.pri') -ErrorAction SilentlyContinue
if ($split) {
    Refuse "makepri split resources into $($split.Name -join ', ') - those belong to a bundle, and this is one package"
}

# --- the package ------------------------------------------------------------

# This takes minutes rather than seconds, and the reason is the three quarters
# of a gigabyte of ONNX weights it is compressing. They barely compress, which
# is the same thing `packaging/debian/build-deb.sh` says about xz.
$package = Join-Path $OutDir "Duckling-$version-x64.msix"
& $makeappx pack /d $stage /p $package /o
if ($LASTEXITCODE -ne 0) { Refuse "makeappx pack failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host "built $package"
Write-Host "  identity  $($identity.Name)"
Write-Host "  publisher $($identity.Publisher)"
Write-Host "  version   $version"
Write-Host "  from      $Binary"
Write-Host ("  size      {0:N0} MB" -f ((Get-Item $package).Length / 1MB))
# Said out loud because the package name is deterministic, so a plain run
# overwrites a signed package of the same version with an unsigned one and says
# nothing about it. Deployment then fails 0x800B0100, "no signature was present",
# which reads like a signing problem rather than like the last build having been
# a different build.
if (-not $SelfSign) {
    Write-Host '  unsigned  - pass -SelfSign to install it here'
}

# --- signing, for a local install and nothing else --------------------------

if ($SelfSign) {
    $signtool = Find-SdkTool 'signtool.exe'
    if (-not $signtool) { Refuse 'no signtool.exe in any Windows SDK' }

    # signtool refuses a package whose manifest Publisher and whose certificate
    # subject differ, so the subject is built from the identity rather than
    # typed a second time.
    #
    # Duckling's Publisher is the Excelano account's and is the same X.500
    # string segler and slipcase-desktop carry, so a certificate left in this
    # store by either application's test signing matches this one and is reused.
    # That is correct rather than a coincidence to guard against: the subject is
    # what signtool checks, all three packages are this account's, and the
    # certificate is a throwaway either way.
    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $identity.Publisher -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if (-not $cert) {
        Write-Host "making a throwaway signing certificate for $($identity.Publisher)"
        $cert = New-SelfSignedCertificate -Type CodeSigningCert `
            -Subject $identity.Publisher `
            -KeyUsage DigitalSignature `
            -FriendlyName 'Excelano MSIX test signing (throwaway)' `
            -CertStoreLocation Cert:\CurrentUser\My `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    }
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint $package
    if ($LASTEXITCODE -ne 0) { Refuse "signtool failed ($LASTEXITCODE)" }
    Write-Host "signed with $($cert.Thumbprint) - a throwaway, and not what the Store distributes"

    # Deployment reads LocalMachine\TrustedPeople and not the per-user store:
    # importing into CurrentUser\TrustedPeople leaves Add-AppxPackage failing
    # 0x800B0109 just the same. That import is the one administrator action in
    # this whole path, so it is printed rather than attempted.
    $trusted = Get-ChildItem Cert:\LocalMachine\TrustedPeople -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
    Write-Host ''
    if ($trusted) {
        Write-Host 'install it:'
        Write-Host "  Add-AppxPackage $package"
        # Deployment refuses 0x80073CFB for a package whose identity and version
        # match one already installed but whose contents differ, which is every
        # rebuild during a day's work. The version is not bumped for that - it
        # is one number with three spellings and a release decision - so the old
        # one comes off first.
        Write-Host '  # rebuilding the same version? remove the installed one first:'
        Write-Host "  Get-AppxPackage $($identity.Name) | Remove-AppxPackage"
    } else {
        Write-Host 'to install it, this certificate has to be trusted, which needs administrator once:'
        Write-Host "  Export-Certificate -Cert Cert:\CurrentUser\My\$($cert.Thumbprint) -FilePath `$env:TEMP\excelano-test.cer"
        Write-Host '  # then, from an elevated prompt:'
        Write-Host "  Import-Certificate -FilePath `$env:TEMP\excelano-test.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
        Write-Host "  Add-AppxPackage $package"
    }
}

# --- the certification kit --------------------------------------------------

if ($Certify) {
    if (-not $SelfSign) {
        Refuse '-Certify needs -SelfSign: the kit installs the package it tests, and an unsigned one will not install'
    }
    $elevated = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $elevated) {
        Refuse 'the Windows App Certification Kit needs an elevated session - rerun this from an administrator prompt'
    }
    $appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\App Certification Kit\appcert.exe'
    if (-not (Test-Path $appcert)) {
        Refuse "no appcert.exe at $appcert - the App Certification Kit is a separate SDK feature"
    }

    $report = Join-Path $OutDir "wack-$version.xml"

    # The report is removed first, and then the one that appears is checked for
    # being newer than this run. Both, because the first version of this did
    # neither and reported a previous run's verdict as though it were this one's.
    #
    # `appcert` refuses to overwrite a report: given a path that exists it prints
    # "Please specify a unique report file name" and stops before running a
    # single test. The file was still there, `Test-Path` was satisfied, and the
    # findings printed were the previous package's - on a run whose whole
    # purpose was to test a different package under the same version number.
    #
    # This is the failure the comment above already claimed to guard against,
    # which is worth reading twice: a kit that ran and failed and a kit that
    # never ran must not come out the same, and *stale* is a third state neither
    # of those words covers.
    if (Test-Path $report) { Remove-Item $report -Force }
    $startedAt = Get-Date
    & $appcert reset | Out-Null
    & $appcert test -appxpackagepath $package -reportoutputpath $report
    if (-not (Test-Path $report)) {
        Refuse "the certification kit wrote no report to $report"
    }
    if ((Get-Item $report).LastWriteTime -lt $startedAt) {
        Refuse "the report at $report is older than this run - the kit did not write it, so nothing below would be about this package"
    }

    Test-CertificationReport $report
}
