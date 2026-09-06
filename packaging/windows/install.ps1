# Install the Windows integration DESIGN.md 8 describes: the executable with its
# models and runtime beside it, the icon, a Start menu entry, and Duckling under
# Open With for the document types it reads. Per-user, under HKCU and
# %LOCALAPPDATA%, which is the counterpart of the Linux script's default of
# ~/.local: no administrator, and nothing written that another account can see.
# There is no all-users variant because the machine-wide half of every key here
# needs elevation, and a packaging script that sometimes needs it and sometimes
# does not is worse than one that never does.
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\install.ps1
#
# **Duckling owns no format, and that is the whole difference from segler's copy
# of this script.** Segler claims `.dclx` and `.dclg`: it writes a ProgID per
# kind, a content type, an icon, and the extension's default value, so a
# double-click opens Segler. Duckling claims nothing. Every type below is
# somebody else's - a PDF belongs to whatever opens PDFs on this machine - and
# all this script asks for is a place in the Open With list, which is what
# `MimeType=` in `packaging/linux/duckling.desktop` asks a file manager for. The
# extension's default value is never written, no ProgID is created, and
# `uninstall.ps1` never removes a `UserChoice`.
#
# It also copies about 740 MB, which is the models. `packaging/linux/install.sh`
# does the same into ~/.local and for the same reason: the application finds
# them beside its own executable and there is no download at run time.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # Where to install. The default is the per-user location Windows names for
    # applications that do not go through an installer service.
    [string] $Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\Duckling'),
    # The executable to install. With neither this nor -NoBinary, a built one is
    # looked for.
    [string] $Binary,
    # Install the integration only: the icon, the Open With entries, the Start
    # menu shortcut. No executable, no models.
    [switch] $NoBinary
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)

# The extensions Duckling offers to open, and the only place this script spells
# them.
#
# They are the fifteen media types `packaging/linux/duckling.desktop` lists, in
# the same order, as the extensions Windows identifies them by;
# `AppxManifest.xml.in` carries the same list for the packaged route and says
# more about why `.htm` and `.markdown` are here as second spellings rather than
# as extra types. If the three ever disagree, a person who has both installs
# sees Duckling offered for one set of files by one of them and a different set
# by the other, with nothing anywhere explaining it.
$Extensions = @(
    '.pdf',
    '.docx', '.pptx', '.xlsx',
    '.doc', '.ppt', '.xls',
    '.odt', '.odp', '.ods',
    '.epub', '.rtf',
    '.html', '.htm',
    '.md', '.markdown',
    '.csv'
)

$appName = 'Duckling'
$exeName = 'duckling.exe'
$appIcon = 'duckling.ico'

# --- writing to the registry ------------------------------------------------

# The .NET API rather than PowerShell's registry provider. Segler needs it
# because its media type keys contain forward slashes and the provider reads one
# as a path separator; this script writes no such key, and uses the same API
# anyway so that the two scripts read alike and so that a media type key added
# here later does not have to rediscover the lesson. An empty $Name is the key's
# default value.
function Set-RegistryValue {
    param([string] $Path, [string] $Name, $Value, [string] $Kind = 'String')
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try {
        $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind] $Kind)
    } finally {
        $key.Close()
    }
}

function New-RegistryKey {
    param([string] $Path)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    $key.Close()
}

# --- the executable ---------------------------------------------------------

# Cargo is asked where its target directory is rather than guessed at, because
# `[build] target-dir` in a Cargo configuration file moves it and no environment
# variable then says so. The Linux script learned this the hard way and this one
# inherits the lesson rather than repeating it.
function Find-TargetDir {
    $targetDir = $null
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Push-Location $root
        try {
            $meta = cargo metadata --format-version 1 --no-deps 2>$null | ConvertFrom-Json
            if ($meta) { $targetDir = $meta.target_directory }
        } catch { }
        finally { Pop-Location }
    }
    if (-not $targetDir) { $targetDir = Join-Path $root 'target' }
    return $targetDir
}

$targetDir = Find-TargetDir
$foundBinary = $null
if ($NoBinary) {
    # Nothing to find.
} elseif ($Binary) {
    if (-not (Test-Path -LiteralPath $Binary)) { throw "install.ps1: $Binary is not there" }
    $foundBinary = (Resolve-Path -LiteralPath $Binary).Path
} else {
    foreach ($built in 'release', 'debug') {
        $candidate = Join-Path $targetDir "$built\$exeName"
        if (Test-Path -LiteralPath $candidate) {
            $foundBinary = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
}

# --- the files --------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Prefix | Out-Null

$source = Join-Path $here $appIcon
if (-not (Test-Path -LiteralPath $source)) {
    throw "install.ps1: $appIcon is not beside this script; run make-ico first"
}
Copy-Item -LiteralPath $source -Destination (Join-Path $Prefix $appIcon) -Force
$installedAppIcon = Join-Path $Prefix $appIcon

# The uninstaller is copied in rather than run from the repository, because the
# Add/Remove Programs entry below points at it and a checkout is not something
# that has to still be there a year later.
Copy-Item -LiteralPath (Join-Path $here 'uninstall.ps1') `
          -Destination (Join-Path $Prefix 'uninstall.ps1') -Force

$installedExe = Join-Path $Prefix $exeName
if ($foundBinary) {
    # An upgrade over a running copy is the one failure here a person meets in
    # the ordinary course of things, and Windows will not let a running
    # executable be overwritten. Left to itself the script stops with a .NET
    # IOException and a stack trace naming Copy-Item, which is true and tells
    # nobody what to do. slipcase-desktop walked this on 2026-08-26; the run
    # stopped before the registry stage, so nothing was left half-registered,
    # and that part is worth keeping exactly as it is.
    try {
        Copy-Item -LiteralPath $foundBinary -Destination $installedExe -Force
    } catch [System.IO.IOException] {
        $running = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($exeName)) `
                               -ErrorAction SilentlyContinue |
                   Where-Object { $_.Path -eq $installedExe }
        if ($running) {
            throw "install.ps1: Duckling is running from $installedExe, so it cannot be replaced. " +
                  "Close it and run this again. Nothing has been changed."
        }
        throw
    }
    Write-Output "installed $installedExe from $foundBinary"

    # --- the models, pdfium, and the runtime --------------------------------
    #
    # The same layout every package uses, because `locate_assets` in
    # `src/lib.rs` looks beside the executable and nowhere else: `models\` and
    # `pdfium\` as directories, the five runtime DLLs loose beside the
    # executable where the loader will find them. DESIGN.md 2 and 8.
    #
    # A copy without these produces an application that starts, queues a Word
    # file happily, and fails every PDF - or, without the runtime, does not
    # start at all. So this refuses rather than installing half of it.
    $models = Join-Path $root '.models'
    $pdfium = Join-Path $root '.pdfium\lib'
    if (-not (Test-Path -LiteralPath $models) -or
        -not (Test-Path -LiteralPath (Join-Path $pdfium 'pdfium.dll'))) {
        throw "install.ps1: no models under $root; run packaging/fetch-models.sh first " +
              "(it needs the Git Bash that Git for Windows installs)"
    }
    foreach ($dir in 'models', 'pdfium') {
        $destination = Join-Path $Prefix $dir
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    }
    Write-Output "copying the models; this is about 740 MB and takes a moment"
    Copy-Item -LiteralPath $models -Destination (Join-Path $Prefix 'models') -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $Prefix 'pdfium') | Out-Null
    Copy-Item -Path (Join-Path $pdfium '*') -Destination (Join-Path $Prefix 'pdfium') -Force

    # `runtime-files.ps1` finds these and says where each comes from;
    # `.cargo/config.toml` says why they are not linked in. The packaged route
    # stages exactly the same five.
    $runtime = & (Join-Path $here 'runtime-files.ps1') -TargetDir $targetDir
    foreach ($file in $runtime) {
        Copy-Item -LiteralPath $file.Path -Destination (Join-Path $Prefix $file.Name) -Force
    }
    Write-Output "installed the models, pdfium, and $($runtime.Count) runtime DLLs beside it"
} elseif (-not (Test-Path -LiteralPath $installedExe)) {
    Write-Warning "no executable installed; the Open With entries will point at $installedExe, which is not there yet"
}

# --- the registry -----------------------------------------------------------

$classes = 'Software\Classes'

# The application itself: the name the shell shows and the command a chosen
# Open With entry runs. This is the whole registration for an application that
# claims no type - there is no ProgID, because a ProgID is a *type* and Duckling
# has none to declare.
$applications = "$classes\Applications\$exeName"
Set-RegistryValue $applications 'FriendlyAppName' $appName
Set-RegistryValue "$applications\shell\open\command" '' "`"$installedExe`" `"%1`""
Set-RegistryValue "$applications\DefaultIcon" '' "$installedAppIcon,0"

foreach ($extension in $Extensions) {
    # What puts Duckling in the "Choose another app" list for this type.
    Set-RegistryValue "$applications\SupportedTypes" $extension ''

    # And what puts it in the Open With menu itself. `OpenWithList` names an
    # executable where `OpenWithProgids` names a type, which is why this script
    # uses the first: it is the list that can be joined without owning a ProgID.
    #
    # **The extension's default value is deliberately not written.** That value
    # is what a double-click follows, and for every type here it belongs to
    # whatever opens PDFs or Word files on this machine. Segler writes it
    # because `.dclg` is Segler's; nothing below is Duckling's. A key created
    # here with no default value leaves the machine-wide default in force, which
    # is what the merged class root does.
    New-RegistryKey "$classes\$extension\OpenWithList\$exeName"
}

# --- the Start menu ---------------------------------------------------------

# The counterpart of the `.desktop` entry: what puts the application in front of
# a person who has not got a document to right-click yet. It matters more here
# than on Linux, because Duckling claims no type and a Start menu entry is the
# only place its name appears on its own.
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcut = Join-Path $startMenu 'Duckling.lnk'
if (Test-Path -LiteralPath $installedExe) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = $installedExe
    $link.WorkingDirectory = $Prefix
    $link.IconLocation = "$installedAppIcon,0"
    $link.Description = 'Convert documents to DocLang, Markdown, JSON or LaTeX'
    $link.Save()
    # Deliberately no AppUserModelID on this shortcut. Setting one would need
    # the running process to declare the same identity through
    # SetCurrentProcessExplicitAppUserModelID, which is a raw call this
    # application cannot make under `#![deny(unsafe_code)]`. With neither side
    # declaring one, Windows derives both from the executable path, they agree,
    # and pinning and taskbar grouping work. README.md has the whole of it.
}

# --- Add/Remove Programs ----------------------------------------------------

$version = '0.1.0'
$cargoToml = Join-Path $root 'Cargo.toml'
if (Test-Path -LiteralPath $cargoToml) {
    $line = Select-String -LiteralPath $cargoToml -Pattern '^version = "([^"]+)"' | Select-Object -First 1
    if ($line) { $version = $line.Matches[0].Groups[1].Value }
}

$uninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Duckling'
$uninstallCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Prefix 'uninstall.ps1')`""

# **Not plain "Duckling", and the suffix is somebody else's defect report.** The
# Store package names itself Duckling with a publisher of Excelano, and on
# segler an entry that did the same put two rows in Settings > Apps reading
# "Segler" by "Excelano" with the same icon, separated by nothing but 0.1.0
# against 0.1.0.0. David hit that on 2026-09-04: he picked the one that said
# Excelano, which was both of them, and removed the package instead of the
# script install. The package's name is fixed by the manifest and the
# reservation; this one is ours, so this one is the one that changes.
Set-RegistryValue $uninstallKey 'DisplayName' 'Duckling (user install)'
Set-RegistryValue $uninstallKey 'DisplayVersion' $version
Set-RegistryValue $uninstallKey 'Publisher' 'Excelano'
Set-RegistryValue $uninstallKey 'DisplayIcon' "$installedAppIcon,0"
Set-RegistryValue $uninstallKey 'InstallLocation' $Prefix
Set-RegistryValue $uninstallKey 'UninstallString' $uninstallCommand
Set-RegistryValue $uninstallKey 'QuietUninstallString' $uninstallCommand
Set-RegistryValue $uninstallKey 'NoModify' 1 'DWord'
Set-RegistryValue $uninstallKey 'NoRepair' 1 'DWord'
# Settings > Apps reads this and shows it; a person deciding whether to remove
# something that is most of a gigabyte should be able to see that it is.
$size = (Get-ChildItem -LiteralPath $Prefix -Recurse -File -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum).Sum
if ($size) {
    Set-RegistryValue $uninstallKey 'EstimatedSize' ([int] ($size / 1KB)) 'DWord'
}

# --- tell the shell ---------------------------------------------------------

# Without this the Open With entries appear at the next logon rather than now,
# which reads as the install not having worked.
Add-Type -Namespace Duckling -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet=CharSet.Unicode)]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
[Duckling.Shell]::SHChangeNotify(0x08000000, 0, [System.IntPtr]::Zero, [System.IntPtr]::Zero)

Write-Output ""
Write-Output "Duckling is under Open With for $($Extensions.Count) extensions, and opens nothing by default"
Write-Output "under $Prefix"
Write-Output ""
Write-Output "check it with:"
# Not `assoc` and `ftype`. Both report these extensions as though nothing here
# had happened: they read and write the machine-wide half of the class root
# only, and everything above is per-user. Measured on slipcase-desktop, after
# they were put in that script first and printed exactly the message a failed
# install would have.
Write-Output "  reg query `"HKCU\Software\Classes\Applications\$exeName`" /s"
Write-Output "and by right-clicking a PDF and a Word file, where Duckling should be under"
Write-Output "Open With without having become what either one opens with by default."
