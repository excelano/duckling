# Remove what install.ps1 put in place, and tell the shell it is gone.
#
# The whole of it, because an Open With entry that outlives its executable is
# worse than none: the shell keeps offering the application and choosing it
# fails with a message about a missing file rather than the dialog that would
# have let a person pick something else.
#
# **What this must not remove, and segler's copy does.** That script deletes
# `Explorer\FileExts\<ext>\UserChoice` for each of its extensions, because
# Segler claims `.dclx` and `.dclg` as the default handler and a stale
# UserChoice pointing at a deleted Segler is a dead association. Duckling claims
# nothing. A `UserChoice` for `.pdf` is a person's decision about which
# application opens their PDFs, made possibly years ago and nothing to do with
# this installation - removing it would break a working machine to tidy up after
# software that never touched it. `install.ps1` writes no default value for any
# extension, so there is no stale default here to clean and nothing to be
# tempted by.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

[CmdletBinding()]
param(
    [string] $Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\Duckling'),
    # Leave the installed executable, models and icon where they are.
    [switch] $KeepFiles
)

$ErrorActionPreference = 'Stop'

# The same list install.ps1 writes from, and it has to stay the same list: an
# extension added there and not here is exactly the dead entry this script
# exists to prevent.
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

$exeName = 'duckling.exe'
$appIcon = 'duckling.ico'

# The .NET API for the same reason install.ps1 uses it, and it matters more
# here: `DeleteSubKeyTree` on a path this script built is precise about what it
# removes, where a provider that misread a path could take a neighbouring key
# with it. Everything below names a key this installation created.
function Remove-Key {
    param([string] $Path)
    try {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($Path, $false)
    } catch {
        Write-Verbose "nothing at $Path"
    }
}

$classes = 'Software\Classes'

foreach ($extension in $Extensions) {
    # Only this application's own entry under the extension's OpenWithList, and
    # never the extension's key itself. `HKCU\Software\Classes\.pdf` may hold
    # things this installation did not write - another application's
    # OpenWithProgids, a user's own choice - and it merges with the machine-wide
    # key that actually defines what a PDF is. Deleting the subkey Duckling
    # created leaves all of that alone.
    Remove-Key "$classes\$extension\OpenWithList\$exeName"

    # And the OpenWithList key itself if this left it empty, so that an
    # uninstall does not leave a trail of empty keys under seventeen
    # extensions. `DeleteSubKey` with the second argument false is a no-op on a
    # key that still has children, which is exactly the condition wanted: if
    # another application put itself in that list, the list stays.
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$classes\$extension\OpenWithList", $false)
        if ($key) {
            $empty = ($key.SubKeyCount -eq 0 -and $key.ValueCount -eq 0)
            $key.Close()
            if ($empty) {
                [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey("$classes\$extension\OpenWithList", $false)
            }
        }
    } catch {
        Write-Verbose "left $classes\$extension\OpenWithList alone"
    }
}

Remove-Key "$classes\Applications\$exeName"
Remove-Key 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Duckling'

$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Duckling.lnk'
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force -Confirm:$false }

if (-not $KeepFiles) {
    foreach ($name in @($exeName, $appIcon)) {
        $path = Join-Path $Prefix $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -Confirm:$false }
    }
    # The runtime DLLs, by the same list runtime-files.ps1 supplies and
    # install.ps1 copies. Named rather than globbed: a `*.dll` sweep of an
    # install directory is a sweep of whatever is in it, and this script should
    # only ever remove what its partner put there.
    foreach ($name in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll',
                      'msvcp140_1.dll', 'DirectML.dll') {
        $path = Join-Path $Prefix $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -Confirm:$false }
    }
    # The models and pdfium, which are most of what is here: about 740 MB that
    # a person removing this application certainly means to get back.
    foreach ($dir in 'models', 'pdfium') {
        $path = Join-Path $Prefix $dir
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -Confirm:$false }
    }
    # Add/Remove Programs points at the copy inside the install directory, so
    # the usual run is a script emptying the directory it is itself in, and a
    # running script cannot delete itself. Run from a checkout it is not that
    # file, and then the copy is an ordinary file that can go with the rest.
    #
    # Both branches were one line in slipcase-desktop until 2026-08-26, when a
    # run from the checkout left the copy behind and said it was the script now
    # running. That was untrue and it left a directory the script says it
    # removes, so the two cases are told apart rather than assumed to be one.
    $copy = Join-Path $Prefix 'uninstall.ps1'
    $self = $MyInvocation.MyCommand.Path
    if (Test-Path -LiteralPath $copy) {
        $same = $self -and
            ([System.IO.Path]::GetFullPath($self) -ieq [System.IO.Path]::GetFullPath($copy))
        if ($same) {
            Write-Output "left ${copy} behind: it is the script now running"
        } else {
            Remove-Item -LiteralPath $copy -Force -Confirm:$false
        }
    }
    # And the directory, where emptying it emptied it. Left alone if anything
    # else is in there, because this script installed none of it.
    if ((Test-Path -LiteralPath $Prefix) -and
        -not (Get-ChildItem -LiteralPath $Prefix -Force)) {
        Remove-Item -LiteralPath $Prefix -Force -Confirm:$false
    }
}

Add-Type -Namespace DucklingUninstall -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet=CharSet.Unicode)]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
[DucklingUninstall.Shell]::SHChangeNotify(0x08000000, 0, [System.IntPtr]::Zero, [System.IntPtr]::Zero)

Write-Output "removed the Open With entries for $($Extensions.Count) extensions, the Start menu entry, and the uninstall entry"
Write-Output "no file type default was changed, because none was ever claimed"
