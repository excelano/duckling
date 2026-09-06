# Photograph the application's own window at a size the Microsoft Store accepts.
#
# Screenshots were once listed as something no script could do, and that was an
# assumption rather than a measurement. What a script cannot do is decide which
# documents to queue and whether the result is a good advertisement. What it can
# do is every mechanical part: launch the application with those documents, size
# the window so the visible frame is exactly the size asked for, bring it to the
# front, capture it, and refuse if what came back is the wrong size.
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\screenshot.ps1 `
#       -Documents C:\scratch\demo -Out C:\shots\01-queue.png
#
# `-Documents` takes a directory, which is the form to prefer, or files
# comma-joined with no spaces; its own comment says why the spaced form cannot
# work through `-File`.
#
# HOW THE PACKAGED APPLICATION IS LAUNCHED WITH FILES, MEASURED HERE 2026-09-05
#
# segler's copy of this script opens its document and lets the file association
# find the packaged application. Duckling claims no association, so that route
# does not exist: opening a PDF opens whatever opens PDFs on the machine.
#
# The executable inside `C:\Program Files\WindowsApps` cannot be run directly
# either - `Start-Process` on it fails with *Access is denied*, which is the
# package's ACL and not something to work around. What does work is the apps
# folder moniker with arguments:
#
#   Start-Process "shell:AppsFolder\<PackageFamilyName>!<AppId>" -ArgumentList ...
#
# and the application receives them as `std::env::args_os`, which is the same
# path an Open With activation takes. That is how this script reaches the build
# a person actually gets rather than a developer build.
#
# TWO THINGS MEASURED RATHER THAN ASSUMED, BOTH OF THEM PIXELS
#
# `SetWindowPos` sizes the *window rect*, which on Windows 10 carries an
# invisible resize border outside the visible frame: asking for 1366x768 gave a
# frame of 1352x761, which is under the Store's minimum. The visible frame is
# `DWMWA_EXTENDED_FRAME_BOUNDS`, and the difference measured on slipcase-desktop
# is 14 by 7.
#
# And that frame's top edge is one pixel above what is actually drawn, so a
# capture at exactly the frame rect picks up a sliver of whatever is behind. It
# arrived as a strip of console text across the top of slipcase-desktop's first
# two attempts. The capture is two rows taller than needed and the top two are
# cropped.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    # The documents to queue, or one directory holding them. Which ones is an
    # editorial decision and not this script's: `packaging/store-listing.md`
    # records what was used and why, and `packaging/demo/documents` is the set
    # it names.
    #
    # **A directory is the form to prefer, and that is a measurement.** Invoked
    # as `powershell -File screenshot.ps1`, which is how every other script here
    # is invoked, PowerShell does not pass arrays: `-Documents a b c` binds `a`
    # to this parameter and then tries `b` as `-Width`, and the error names
    # `Width` and an .epub path in the same sentence and explains nothing.
    # Comma-joining with no spaces works and is easy to get wrong by adding one.
    # A single directory has neither problem.
    [Parameter(Mandatory = $true)][string[]] $Documents,
    [Parameter(Mandatory = $true)][string] $Out,
    # The Store's minimum for a desktop screenshot, and the default because a
    # window this size looks like a window rather than like an advertisement.
    [int] $Width = 1366,
    [int] $Height = 768,
    # Where to put the window. Anywhere it fits entirely on screen.
    [int] $X = 200,
    [int] $Y = 100,
    # Seconds to wait after the window appears before capturing. The default is
    # enough for a queue that has not been converted yet; a shot taken after
    # pressing Convert wants enough for the conversion, which for a PDF is the
    # models loading as well as the pages.
    [int] $Settle = 3,
    # How many of egui's own zoom steps to apply before capturing, each 0.1.
    #
    # **A listing screenshot wants this and the reason is not vanity.** The
    # Store renders screenshots small, and at the default scale this
    # application's text is around ten pixels - legible in the window and not
    # in a thumbnail. Four steps is about 140% and was what the first pair were
    # taken at; measured 2026-09-05, six steps also fixed the preview pane
    # wrapping the DocLang into fragments.
    #
    # It is egui's own `Ctrl` and `+`, so this changes nothing a person could
    # not do in the running application, and nothing persists: eframe's
    # `persistence` feature is off, so the next launch is back at 100%.
    [int] $Zoom = 0,
    # Launch the side-loaded build under %LOCALAPPDATA% rather than the packaged
    # one. The packaged application is what a person gets and is the default;
    # this is for looking at a build that is not packaged yet.
    [switch] $SideLoaded
)

$ErrorActionPreference = 'Stop'

function Refuse([string] $message) { Write-Error "screenshot.ps1: $message" }

# One directory expands to the files in it, in name order, which is the order
# the queue puts them in anyway - so what is photographed matches what
# `packaging/demo/README.md` lists. Files that Duckling cannot read would be
# rejected at queueing and appear as a status line rather than a row, so they
# are dropped here instead: a directory is a request for what can be converted,
# which is the same rule `walk` in `src/lib.rs` follows for a dropped folder.
$readable = '.pdf', '.docx', '.pptx', '.xlsx', '.doc', '.ppt', '.xls',
            '.odt', '.odp', '.ods', '.epub', '.rtf', '.html', '.htm',
            '.md', '.markdown', '.csv'
$resolved = @()
foreach ($document in $Documents) {
    if (-not (Test-Path $document)) { Refuse "no document at $document" }
    $item = Get-Item $document
    if ($item.PSIsContainer) {
        $inside = Get-ChildItem $item.FullName -File |
            Where-Object { $readable -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name
        if (-not $inside) { Refuse "nothing Duckling reads in $($item.FullName)" }
        $resolved += $inside.FullName
    } else {
        $resolved += $item.FullName
    }
}

Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Shot -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
public struct RECT { public int Left, Top, Right, Bottom; }
'@

# Anything already running is stopped first, so the window being photographed is
# the one holding these documents and not a previous one.
Get-Process duckling -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$arguments = $resolved | ForEach-Object { "`"$_`"" }
if ($SideLoaded) {
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\Duckling\duckling.exe'
    if (-not (Test-Path $exe)) { Refuse "no side-loaded build at $exe - run install.ps1 first" }
    Start-Process $exe -ArgumentList $arguments
} else {
    # The identity from the one file that holds it, rather than typed here. A
    # moniker with the wrong family name starts nothing and says nothing about
    # why.
    $identityFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'identity.psd1'
    if (-not (Test-Path $identityFile)) {
        Refuse "no identity at $identityFile - copy identity.psd1.example beside it, or pass -SideLoaded"
    }
    $identity = Import-PowerShellDataFile $identityFile
    if (-not $identity.PackageFamilyName) { Refuse 'identity.psd1 has no PackageFamilyName' }
    if (-not (Get-AppxPackage $identity.Name -ErrorAction SilentlyContinue)) {
        Refuse "$($identity.Name) is not installed - build-msix.ps1 -SelfSign and Add-AppxPackage it, or pass -SideLoaded"
    }
    Start-Process "shell:AppsFolder\$($identity.PackageFamilyName)!Duckling" -ArgumentList $arguments
}
Start-Sleep -Seconds 6

$app = Get-Process duckling -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $app -or $app.MainWindowHandle -eq [IntPtr]::Zero) {
    Refuse 'Duckling did not come up with a window'
}
$handle = $app.MainWindowHandle

# The border measured on this platform, and the two spare rows for the crop.
$BORDER_W = 14
$BORDER_H = 7
$TOPMOST = [IntPtr](-1)
$NOTOPMOST = [IntPtr](-2)

[void][Shot.Win]::SetWindowPos(
    $handle, $TOPMOST, $X, $Y, $Width + $BORDER_W, $Height + $BORDER_H + 2, 0)
[void][Shot.Win]::SetForegroundWindow($handle)

# The zoom, before the pointer is parked and before the settle, so the layout
# has the same time to come to rest as it would without it.
#
# `SendKeys` through `WScript.Shell` is the obvious way to do this and it throws
# *Value does not fall within the expected range* on this machine; the Forms one
# works. Measured 2026-09-05, and written down because the COM error message
# names nothing that would lead anybody to the answer.
if ($Zoom -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    Start-Sleep -Milliseconds 600
    for ($i = 0; $i -lt $Zoom; $i++) {
        [System.Windows.Forms.SendKeys]::SendWait("^{ADD}")
        Start-Sleep -Milliseconds 350
    }
}

# The pointer goes somewhere the window is not, because egui draws hover state
# and the capture keeps it. Measured on slipcase-desktop 2026-08-29: a retake
# landed with the mouse resting over a field, which came out highlighted and
# focus-ringed in a picture meant to show the application at rest, and with the
# scroll bar drawn because the pointer was inside the scroll area. Neither is
# wrong and both are noise a shopper reads as an interface doing something.
#
# Bottom right of the virtual screen rather than a constant: the window is
# placed near the top left, and a fixed 1900x1200 is off-screen on a smaller
# display, where Windows clamps it to an edge the window might occupy.
Add-Type -AssemblyName System.Windows.Forms
$away = [System.Windows.Forms.SystemInformation]::VirtualScreen
[System.Windows.Forms.Cursor]::Position =
    New-Object System.Drawing.Point(($away.Right - 2), ($away.Bottom - 2))

# Long enough for the window to settle and repaint at its new size. egui draws
# on demand, and a capture taken during the resize catches a half-laid-out frame.
Start-Sleep -Seconds $Settle

$rect = New-Object Shot.Win+RECT
[void][Shot.Win]::DwmGetWindowAttribute($handle, 9, [ref]$rect, 16)
$frameW = $rect.Right - $rect.Left
$frameH = $rect.Bottom - $rect.Top
if ($frameW -lt $Width -or $frameH -lt $Height + 2) {
    Refuse "the visible frame came back ${frameW}x${frameH}, which cannot yield ${Width}x${Height} - the resize border is not what this script measured"
}

$full = New-Object System.Drawing.Bitmap($frameW, $frameH)
$graphics = [System.Drawing.Graphics]::FromImage($full)
$graphics.CopyFromScreen(
    $rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($frameW, $frameH)))
$graphics.Dispose()

$shot = $full.Clone(
    (New-Object System.Drawing.Rectangle(0, 2, $Width, $Height)), $full.PixelFormat)
$shot.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$shot.Dispose()
$full.Dispose()

[void][Shot.Win]::SetWindowPos($handle, $NOTOPMOST, 0, 0, 0, 0, 0x0003)

# Read back rather than trusted. A screenshot of the wrong size is refused at
# upload, and this is the one property of it a machine can check.
$written = [System.Drawing.Image]::FromFile((Resolve-Path $Out).Path)
$got = "$($written.Width)x$($written.Height)"
$written.Dispose()
if ($got -ne "${Width}x${Height}") {
    Refuse "wrote $got and the Store was asked for ${Width}x${Height}"
}
Write-Host "wrote $Out - $got, $($resolved.Count) document(s) queued"
Write-Host 'look at it before it goes anywhere: a correct size is not a good screenshot'
