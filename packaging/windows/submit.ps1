# Send a built package and the listing text to the Microsoft Store, through the
# submission API rather than through the forms.
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\submit.ps1 -DryRun
#   ...\submit.ps1                          # upload, patch the listing, publish
#   ...\submit.ps1 -MetadataOnly            # upload and patch, stop before publish
#
# `msstore-cli` does the talking; this decides what it says. The listing text
# comes out of `packaging/store-listing.md`, which stays the one copy of every
# field, and the certification notes out of `packaging/windows/PASTE.local.md`,
# which is where the account-shaped text lives. Nothing here holds a credential:
# the CLI keeps its own, configured once with `msstore reconfigure`.
#
# WHAT IT DOES NOT DO
#
# It does not build, and it does not sign. The package it uploads is the
# **unsigned** one `build-msix.ps1` makes without `-SelfSign`; the Store signs
# what it distributes. It does not touch the screenshots, the logo, the price,
# the markets, the age rating or the category - those round-trip untouched from
# whatever the last submission set, and changing one is form work or another
# script's job.
#
# THE FOUR RULES THIS IS SHAPED BY
#
# Every one of them was measured against Microsoft's documentation or the live
# account rather than assumed; `~/.claude/CLAUDE.md` is where the fleet keeps
# them and `SUBMITTING.local.md` beside this file is the log.
#
#   1. A product's **first** submission cannot go through the API, because the
#      age ratings questionnaire is a form job. Duckling is past it: 0.1.0 was
#      submitted through the forms on 2026-09-06 and is published.
#   2. **A submission created through the API must be edited only through the
#      API.** Opening it in Partner Center afterwards leaves it uncommittable,
#      and the fix is to delete it and start over. So once this script has run,
#      the browser is for reading.
#   3. **`msstore publish` deletes the pending draft** on a product that already
#      has a published submission, and rebuilds it from the last published one.
#      The package therefore goes up first, with `--noCommit`, and the metadata
#      is patched onto the draft that leaves behind. Never the other way round:
#      this script's fixed order is the enforcement.
#   4. **The listing locale is whatever the submission says it is.** This
#      product's is `en-gb`, inherited from the first package's manifest and not
#      renameable now. Microsoft's own examples index `en-us` and would silently
#      miss, so this writes **every** locale the submission returns.
#
# THE ONE THING THAT IS DUCKLING'S AND NOT THE FLEET'S
#
# The package is about 605 MB, where every other application here is single
# figures. `msstore publish` defaults to a 100-second upload timeout, which is
# not a Duckling-sized number; `-UploadTimeout` defaults to an hour below.
#
# This is the first copy of this script in the fleet. `~/.claude/CLAUDE.md`
# agreed the design and the rest of `packaging/` says how a copy travels: it
# clones per repository, one directory per platform, with the names changed.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # The package to upload. Defaults to the unsigned one under `dist\submit\`,
    # which is where `build-msix.ps1` without `-SelfSign` is asked to put it so
    # that the signed copy cannot be picked up by mistake: `msstore publish`
    # takes a directory and chooses the best candidate in it, and "best" is not
    # a judgement to leave to a directory holding two packages.
    [string] $Package,
    # The Store product ID. Defaults to `identity.psd1`'s StoreId, which is the
    # same number the listing URL ends with.
    [string] $ProductId,
    # The one copy of the listing text.
    [string] $ListingFile,
    # Where the certification notes are. Optional: without it the notes already
    # on the submission are left alone, which for a resubmission is usually
    # right and for a new version usually is not.
    [string] $NotesFile,
    # Where the JSON this sends and receives is written, for reading afterwards.
    [string] $WorkDir,
    # Seconds. The CLI's own default is 100, which uploads about 6 MB of
    # Slipcase and not 605 MB of this.
    [int] $UploadTimeout = 3600,
    # Patch the metadata of a draft that already has its package, rather than
    # uploading one. For a second run after a listing correction.
    [switch] $SkipUpload,
    # Upload and patch, then stop with the draft sitting there. What to use
    # when a person is going to read the draft in Partner Center before it goes
    # - reading is safe, editing is rule 2 - and then run this again with
    # -SkipUpload -PublishOnly.
    [switch] $MetadataOnly,
    # Publish the draft as it stands and poll. Uploads nothing and patches
    # nothing.
    [switch] $PublishOnly,
    # Say what would be sent and send nothing. Writes the patched JSON to
    # $WorkDir and stops. Costs nothing and touches no submission.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)

function Refuse([string] $message) {
    Write-Error "submit.ps1: $message"
}

# Run msstore and hand back its standard output. The CLI writes its progress to
# standard error and its JSON to standard output, so the two are kept apart
# rather than merged: a caller that merges them gets progress lines inside the
# JSON it is about to parse.
function Invoke-MSStore([string[]] $Arguments) {
    $out = & msstore @Arguments
    if ($LASTEXITCODE -ne 0) {
        Refuse "msstore $($Arguments -join ' ') exited $LASTEXITCODE"
    }
    return $out
}

# --- the sections of store-listing.md ---------------------------------------

# The listing file is prose with headings, and these read it rather than a
# generated copy of it, so that the file a person edits is the file that goes
# up. Each of them refuses on a heading that is not there: a listing field
# silently left empty is exactly the drift this whole arrangement exists to
# stop, and 0.1.0's own submission shows what it looks like - eight feature
# bullets and a seventh search term were written in PASTE.local.md, and the
# live listing came back from the API with zero features and six keywords.
function Get-ListingSection([string] $text, [string] $headingPattern) {
    $m = [regex]::Match($text, "(?ms)^## $headingPattern[^\r\n]*\r?\n(.*?)(?=^## |\z)")
    if (-not $m.Success) { Refuse "store-listing.md has no '## $headingPattern' heading" }
    # Line endings only, not whitespace. `.Trim()` would take the four spaces
    # off the front of the first indented line of a section, and a list read
    # that way is silently one item short - which is how this was found.
    #
    # And the endings inside are normalised to LF, because that is what the
    # Store stores: the published listing came back with 4 LF and no CR in a
    # short description and 25 in a description, read on 2026-09-09. This
    # checkout is CRLF, so a section handed over unchanged would carry a CR per
    # line into a field with a character limit - which is exactly how a 498
    # character short description arrived at the limit check as 502.
    return ($m.Groups[1].Value -replace "`r`n", "`n").Trim([char[]]"`n")
}

# The indented lines of a section, which is how this file spells a list of
# short strings: the feature bullets and the keyword line are both one.
function Get-IndentedLines([string] $section) {
    $lines = @()
    foreach ($line in ($section -split "\r?\n")) {
        if ($line -match '^\s{4}(\S.*?)\s*$') { $lines += $Matches[1] }
    }
    return $lines
}

# --- what to send ------------------------------------------------------------

if (-not $ListingFile) { $ListingFile = Join-Path $root 'packaging\store-listing.md' }
if (-not $WorkDir) { $WorkDir = Join-Path $root 'dist\submission' }

if (-not (Get-Command msstore -ErrorAction SilentlyContinue)) {
    Refuse 'msstore is not on PATH. The CLI is msstore-cli and it needs the .NET Desktop Runtime; `msstore reconfigure` is what puts credentials in its own store.'
}
if (-not (Test-Path $ListingFile)) { Refuse "no listing text at $ListingFile" }

$identityFile = Join-Path $here 'identity.psd1'
if (-not $ProductId) {
    if (-not (Test-Path $identityFile)) {
        Refuse "no -ProductId and no identity.psd1 beside this script - see identity.psd1.example"
    }
    $identity = Import-PowerShellDataFile $identityFile
    $ProductId = $identity.StoreId
}
if (-not $ProductId) { Refuse 'identity.psd1 carries no StoreId' }

# The version, from the one parser, the way every other script here asks for it.
# Not `bash` off PATH: on a machine with WSL that name is a Linux distribution
# where this checkout is at another path.
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Refuse 'git is not on PATH, and version.sh needs the shell Git for Windows ships' }
$gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
$sh = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path $sh)) { $sh = Join-Path $gitRoot 'usr\bin\sh.exe' }
if (-not (Test-Path $sh)) { Refuse "no shell found beside $($git.Source)" }
$versionScript = (Join-Path $here '..\version.sh').Replace('\', '/')
$release = (& $sh $versionScript | Select-Object -First 1).Trim()
$appxVersion = (& $sh $versionScript --appx | Select-Object -First 1).Trim()
if ($appxVersion -notmatch '^\d+\.\d+\.\d+\.0$') {
    Refuse "version.sh --appx said '$appxVersion', which is not four parts ending in 0"
}

if (-not $Package) { $Package = Join-Path $root "dist\submit\Duckling-$appxVersion-x64.msix" }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# --- the state the Store is in ----------------------------------------------

# Asked before anything is sent, because two of the answers are refusals. A
# pending draft that this run did not make is somebody's work in progress, and
# rule 3 says an upload would delete it.
Write-Host "product $ProductId, version $release ($appxVersion)"

# **Read out of the JSON and not out of the CLI's own words.** The first
# version of this grepped `submission status` for "Could not find a Pending
# Submission" and got the answer backwards on a product that had none: the CLI
# writes that sentence to **standard error**, so it is on the screen and not in
# the variable, and its absence read as a draft that was not there. Measured
# 2026-09-09, on the first real run of this script, which refused to submit.
#
# `submission get` prefers a pending submission and falls back to the last
# published one, and a published submission is the one thing a draft can never
# be. So the status field answers the question with no text matching at all.
$stateJson = (Invoke-MSStore @('submission', 'get', $ProductId) | Out-String).Trim()
if (-not $stateJson.StartsWith('{')) { Refuse 'msstore submission get did not answer with JSON' }
$state = $stateJson | ConvertFrom-Json
$hasPending = $state.status -ne 'Published'
Write-Host "  the store has: $($state.status)$(if ($hasPending) { ' - a pending submission' } else { ' - no pending submission' })"
if ($hasPending -and -not ($SkipUpload -or $PublishOnly -or $DryRun)) {
    Refuse @"
there is already a pending submission on $ProductId, and uploading a package
would delete it and rebuild the draft from the last published one. Read it
first. Then either finish it - `-SkipUpload` patches its metadata, `-PublishOnly`
sends it - or `msstore submission delete $ProductId` and run this again.
"@
}
if (-not $hasPending -and ($SkipUpload -or $PublishOnly)) {
    Refuse "there is no pending submission on $ProductId to $(if ($PublishOnly) { 'publish' } else { 'patch' })"
}

# --- 1. the package ---------------------------------------------------------

if (-not ($SkipUpload -or $PublishOnly)) {
    # A dry run says what it would send, and one before the package exists is
    # worth having: it is how the listing text gets read back and argued with
    # while the build is still running.
    if ($DryRun -and -not (Test-Path $Package)) {
        Write-Warning "no package at $Package yet - a real run would refuse here"
    }
    elseif (-not (Test-Path $Package)) {
        Refuse @"
no package at $Package. The copy that goes to the Store is the **unsigned** one:
  powershell -File packaging\windows\build-msix.ps1 -OutDir dist\submit
built from the same release binary as the signed copy that was installed and
walked through CHECKLIST.md, with no rebuild between them - a rebuild of
identical source produces a different file.
"@
    }
    $packageItem = $null
    if (Test-Path $Package) { $packageItem = Get-Item $Package }
    if ($packageItem -and $packageItem.Name -notlike "*$appxVersion*") {
        Refuse "$($packageItem.Name) does not carry version $appxVersion - that is either the wrong package or an unbumped Cargo.toml"
    }
    # A signed package is not a refusal by the Store, which strips and re-signs,
    # but it is a sign that the wrong file is about to go up: `build-msix.ps1`
    # names the throwaway-signed one for installing here.
    if ($packageItem -and $packageItem.Name -like '*signed*') {
        Refuse "$($packageItem.Name) looks like the self-signed copy. The Store gets the unsigned one."
    }

    if ($packageItem) {
        Write-Host ("uploading {0} ({1:N0} MB), timeout {2}s" -f $packageItem.Name, ($packageItem.Length / 1MB), $UploadTimeout)
    }
    if ($DryRun) {
        Write-Host '  -DryRun: not uploading'
    } else {
        # --noCommit is rule 3: it leaves the draft sitting there for the
        # metadata patch below rather than committing a submission carrying the
        # last version's listing text.
        #
        # **The path is the `.msix` file itself, and that took three tries to
        # find out.** The CLI's own help calls this argument "the root directory
        # path where the project file is", and a directory is what the first two
        # attempts passed:
        #
        #   dist\submit             ->  "We could not find a project publisher
        #                                for the project at ..."
        #   the same, plus a copy of the package's AppxManifest.xml  ->  same
        #   the same, with it renamed Package.appxmanifest  ->  "This seems to
        #                                be a UWP project. Finding MSBuild...
        #                                Could not find MSBuild." - it went
        #                                looking for a project to compile
        #   the .msix file          ->  "This seems to be a MSIX project."
        #
        # So the file is what makes its MSIX configurator match, and with that
        # there is nothing to detect, nothing to build and no `msstore init`
        # ever needed for this repository. `--appId` is what stands in for the
        # initialisation, and `--inputDirectory` is not passed at all: the file
        # is the input. Measured 2026-09-09 against 0.4.2.2.
        Invoke-MSStore @('publish', $packageItem.FullName, '--appId', $ProductId,
                         '--noCommit', '--uploadTimeout', "$UploadTimeout") | Out-Null
        Write-Host '  uploaded, draft left uncommitted'
    }
}

# --- 2. the metadata --------------------------------------------------------

if (-not $PublishOnly) {
    $listing = Get-Content $ListingFile -Raw

    $shortDescription = Get-ListingSection $listing 'Short description'
    $description = Get-ListingSection $listing 'Description'
    $features = Get-IndentedLines (Get-ListingSection $listing 'App features')
    if ($features.Count -eq 0) { Refuse 'store-listing.md has no App features bullets' }

    # The seven Microsoft Store terms, which are not the Mac App Store's line in
    # the same section.
    $keywordSection = Get-ListingSection $listing 'Keywords'
    $km = [regex]::Match($keywordSection, "(?ms)\*\*Microsoft Store\*\*[^\r\n]*\r?\n\r?\n\s+([^\r\n]+)")
    if (-not $km.Success) { Refuse 'store-listing.md Keywords has no Microsoft Store line' }
    $keywords = @($km.Groups[1].Value -split '\s*,\s*' | Where-Object { $_ })

    # The release notes for this version and no other. A missing section is a
    # refusal rather than an empty field: *What's new in this version* left
    # blank is a decision, and a decision belongs in the file rather than in
    # whether a regular expression matched.
    $notesSection = Get-ListingSection $listing 'Release notes'
    $rm = [regex]::Match($notesSection, "(?ms)^### $([regex]::Escape($release))\s*\r?\n(.*?)(?=^### |\z)")
    if (-not $rm.Success) { Refuse "store-listing.md has no '### $release' under Release notes" }
    $releaseNotes = $rm.Groups[1].Value.Trim()

    # The certification notes, out of the file that holds the text that only
    # ever goes into a form.
    $certificationNotes = $null
    if ($NotesFile) {
        if (-not (Test-Path $NotesFile)) { Refuse "no notes file at $NotesFile" }
        $notesText = Get-Content $NotesFile -Raw
        $nm = [regex]::Match($notesText, '(?ms)^## Notes for certification[^\r\n]*\r?\n+```\r?\n(.*?)\r?\n```')
        if (-not $nm.Success) { Refuse "$NotesFile has no '## Notes for certification' fenced block" }
        $certificationNotes = ($nm.Groups[1].Value -replace "`r`n", "`n").Trim()
    }

    Write-Host "listing text from $ListingFile"
    Write-Host ("  short description  {0,5} characters" -f $shortDescription.Length)
    Write-Host ("  description        {0,5} characters" -f $description.Length)
    Write-Host ("  features           {0,5}" -f $features.Count)
    Write-Host ("  keywords           {0,5}  $($keywords -join ', ')" -f $keywords.Count)
    Write-Host ("  release notes      {0,5} characters, from ### $release" -f $releaseNotes.Length)
    if ($certificationNotes) {
        Write-Host ("  certification notes{0,5} characters" -f $certificationNotes.Length)
    } else {
        Write-Host '  certification notes    - left as they are (-NotesFile to set them)'
    }

    $currentPath = Join-Path $WorkDir "submission-$release-current.json"
    $patchedPath = Join-Path $WorkDir "submission-$release-patched.json"

    $current = Invoke-MSStore @('submission', 'get', $ProductId)
    $currentJson = ($current | Out-String).Trim()
    if (-not $currentJson.StartsWith('{')) { Refuse 'msstore submission get did not answer with JSON' }
    [System.IO.File]::WriteAllText($currentPath, $currentJson, (New-Object System.Text.UTF8Encoding($false)))
    $product = $currentJson | ConvertFrom-Json

    # Rule 4: every locale the submission returns, not the one Microsoft's
    # examples index. This product's is en-gb.
    $locales = @($product.listings.PSObject.Properties.Name)
    if ($locales.Count -eq 0) { Refuse 'the submission carries no listings at all' }
    Write-Host "patching $($locales.Count) locale(s): $($locales -join ', ')"
    foreach ($locale in $locales) {
        $base = $product.listings.$locale.baseListing
        $base.description = $description
        $base.shortDescription = $shortDescription
        $base.features = $features
        $base.keywords = $keywords
        $base.releaseNotes = $releaseNotes
    }
    if ($certificationNotes) { $product.notesForCertification = $certificationNotes }

    # Everything not named above rides back exactly as it arrived - the images,
    # the price, the markets, the category, the age rating, the package just
    # uploaded. Depth well past what this document nests, because the default
    # of 2 would quietly turn the rest of it into strings.
    $patched = $product | ConvertTo-Json -Depth 64
    [System.IO.File]::WriteAllText($patchedPath, $patched, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "wrote $patchedPath"

    if ($DryRun) {
        Write-Host '-DryRun: nothing sent. Read the two files above and diff them.'
        return
    }

    Invoke-MSStore @('submission', 'update', $ProductId, '--payload', $patchedPath) | Out-Null
    Write-Host 'draft updated'
}

# --- 3. send it -------------------------------------------------------------

if ($MetadataOnly) {
    Write-Host ''
    Write-Host 'the draft is sitting there with its package and its listing text.'
    Write-Host 'read it in Partner Center - reading is safe, editing is not - then:'
    Write-Host "  powershell -File packaging\windows\submit.ps1 -PublishOnly"
    return
}
if ($DryRun) { return }

Write-Host 'publishing'
Invoke-MSStore @('submission', 'publish', $ProductId) | Out-Null
Invoke-MSStore @('submission', 'poll', $ProductId)

Write-Host ''
Write-Host 'submitted. Certification takes hours to days and a rejection can arrive by email'
Write-Host 'with nothing in the web interface saying so, so read the mail.'
Write-Host "  msstore submission status $ProductId"
Write-Host "  https://apps.microsoft.com/detail/$ProductId"
Write-Host ''
Write-Host 'then write down what happened in packaging\windows\SUBMITTING.local.md.'
