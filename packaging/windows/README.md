# Windows packaging

`DESIGN.md` §8. The MSIX the Microsoft Store distributes, and the pair of
scripts that install the same application without one.

    powershell -ExecutionPolicy Bypass -File packaging\windows\install.ps1
    powershell -ExecutionPolicy Bypass -File packaging\windows\uninstall.ps1

`install.ps1 -NoBinary` registers the Open With entries without copying an
executable, and `-Prefix DIR` puts the files somewhere else. `uninstall.ps1
-KeepFiles` removes the registrations and leaves them.

**This directory is `segler/packaging/windows` cloned, which is
`slipcase-desktop/packaging/windows` cloned.** Those repositories have been
through Microsoft Store certification, a rejection, and a resubmission; their
READMEs are the long form of everything here and are worth reading before
changing anything. What is genuinely different in this copy is not a rename, and
it is the whole of the rest of this file.

Everything below marked **measured** was measured on the Windows lane on
2026-09-05, on this machine, against this application. Everything else is
inherited and says where from.

---

## 1. The one that changed the build: `+crt-static` cannot be used

`RELEASE.md` sent this lane to find out whether the prebuilt ONNX Runtime `ort`
fetches for `x86_64-pc-windows-msvc` links against the static CRT without
conflict. **It does not.**

The dist is `ms@1.28.0/x86_64-pc-windows-msvc+directml` from pyke's CDN, and it
was compiled against the *dynamic* CRT, so its objects reach the C library
through `__imp_` import thunks that the static CRT does not define. The link
fails with **63 unresolved externals**, every one of them an ordinary C
function: `strtoll`, `erff`, `nearbyintf`, `fopen_s`, `_dupenv_s`. This is not a
flag that can be argued with. Dropping it links, and the window comes up.

So the rule slipcase-desktop paid for stands, and is kept by the other route
`DESIGN.md` §2 already uses for pdfium: **the runtime ships inside the package.**
`.cargo/config.toml` is where the decision is written down, and it is written as
a comment in a file with no settings in it, so that the next person to reach for
the obvious flag finds out why it is not there before they add it back.

Slipcase 0.1.1's rejection was for a DLL *outside* the package. These are inside
it, beside the executable, where the loader finds them first.

## 2. Five DLLs travel in the package, and one of them was a surprise

**Measured.** The release binary imports 37 DLLs. Twenty-one are in-box; five
are not and are shipped; `check-imports.ps1` holds both lists with a line per
name saying how it was confirmed.

The four Visual C++ runtime files - `vcruntime140.dll`, `vcruntime140_1.dll`,
`msvcp140.dll`, `msvcp140_1.dll`, 0.73 MB together - follow directly from §1.
They come from the Visual Studio redistributable directory and not from
`System32`, because the redist directory is the copy Microsoft ships *for*
app-local deployment and is the one whose licence covers putting these files in
a package.

**DirectML is the fifth and nobody predicted it.** The Windows dist `ort`
chooses carries the DirectML execution provider, so DirectML is linked in
whether or not anything asks for it - docling.rs runs the CPU provider and
Duckling never selects another - and `directml.dll` becomes a hard import the
process cannot start without. Three things then matter at once:

- In-box DirectML began at Windows 10 **10.0.18362**, and
  `AppxManifest.xml.in` declares a floor of **10.0.17763**. Relying on the
  machine's copy would promise a Windows that has none. Shipping one removes
  *that* problem and is not a proof the floor is right: whether DirectML
  1.15.4 loads on 1809 at all is **untested**, because no 1809 machine is to
  hand and 1809 has been out of support since 2021. If the floor ever needs
  defending rather than assuming, raising it to 10.0.18362 costs nothing
  anybody would notice and is the cheaper answer than finding the machine.
- The copy on this machine is **1.0.200713**, from July 2020. The copy pyke
  ships beside the `onnxruntime.lib` actually linked is **1.15.4**. The
  application starts against the old one, so the imported entry points happen to
  resolve - but nobody has checked anything beyond that, and the pairing that
  *is* checked is the library with its own DLL.
- It is 18.5 MB, which against 740 MB of models is not a number worth trading
  anything for.

So the dist's own copy ships. `runtime-files.ps1` finds it by reading the
`cargo:rustc-link-search=native=` line out of `ort-sys`'s build output, which is
the directory the linker was actually given - not by globbing a cache whose
directories are named by content hash, where two can sit side by side after a
dependency bump and picking the wrong one pairs a 1.15 library with some other
DirectML and says nothing.

**Linking DirectML at all is cost for nothing**, and the note upstream is worth
making: docling.rs ships no DirectML models and this application never selects
that provider. `DESIGN.md` §9 carries it as an open thread.

**The five are provably the ones that load, measured 2026-09-05 and worth more
than the clean-machine test it substitutes for.** A machine with no Visual C++
Redistributable can only tell you that the application started; it cannot tell
you *which* copy of `vcruntime140.dll` it used, because there is only one. This
machine has the redistributable in `System32`, which makes it the better
experiment: run the installed package and read `Get-Process duckling | Select
-Expand Modules`. Every one of the five resolves inside the package -

    MSVCP140.dll         C:\Program Files\WindowsApps\Excelano.Duckling_...\MSVCP140.dll
    MSVCP140_1.dll       ...same
    VCRUNTIME140.dll     ...same
    VCRUNTIME140_1.dll   ...same
    directml.dll         ...same

- and none from `System32`, with a perfectly good `System32` copy sitting there
to be preferred if the loader were going to prefer it. `pdfium.dll` is absent
from that list because docling.rs opens it on the first PDF rather than at
load. A clean machine is still worth running for what it might catch that
nobody predicted; it is no longer what this decision rests on.

**The listing's largest claim is checkable here, and was checked.** *No network
connection of any kind* is the sentence a store reviewer can test as easily as
we can, and the import table is where it is either true or not. **Measured**:
the 37 distinct imports carry none of `ws2_32`, `winhttp`, `wininet`,
`iphlpapi`, `urlmon`, `netapi32`, `dnsapi`, `ncrypt` or `secur32`. That is a
property of the artefact rather than a promise about the code, which is the
same reason `check-imports.ps1` exists at all - and it is why that script
prints every name it saw rather than only the ones it objects to.

## 3. Duckling owns no format, and that changes every registration

Segler claims `.dclx` and `.dclg`: a ProgID per kind, a content type, an icon,
and the extension's default value, so a double-click opens Segler. **Duckling
claims nothing.** Every type it reads is somebody else's - a PDF belongs to
whatever opens PDFs on the machine - and all either install route asks for is a
place in the Open With list, which is what `MimeType=` in
`packaging/linux/duckling.desktop` asks a file manager for.

The two routes reach it differently and both were measured:

| | What it writes | Claims a default? |
| --- | --- | --- |
| MSIX | One `uap:FileTypeAssociation` named `documents`, seventeen extensions, no `DisplayName` and no `Logo` | No. It lands in each extension's `OpenWithProgids` as an `AppX…` ProgID |
| `install.ps1` | `Applications\duckling.exe` with `FriendlyAppName`, a command and `SupportedTypes`; plus `<ext>\OpenWithList\duckling.exe` | No. The extension's default value is never written |

**Measured, both of them.** After installing the MSIX,
`HKCU\Software\Classes\.pdf\OpenWithProgids` gained an `AppX…` entry and
`HKCU\Software\Classes\.pdf` still had no default value. After running
`install.ps1`, `.pdf\OpenWithList\duckling.exe` appeared and the default value
was still empty. Neither route can take a type over, which is the behaviour
segler's README measured on 2026-09-04 and the behaviour this application wants
rather than merely tolerates.

**No `uap:DisplayName` and no `uap:Logo` on the association**, and that is a
decision rather than an omission. A `DisplayName` would put Duckling's words in
Explorer's Type column for a PDF the day Duckling ever became its default, and a
`Logo` would put Duckling's face on it. Neither is Duckling's to supply. It is
also why `make-ico` writes four images where segler's writes six: the two
missing ones are that application's file-type logos.

**`uninstall.ps1` must not remove a `UserChoice`, and segler's does.** That
script deletes `Explorer\FileExts\<ext>\UserChoice` because a stale one pointing
at a deleted Segler is a dead association. A `UserChoice` for `.pdf` is a
person's decision about which application opens their PDFs, made possibly years
ago and nothing to do with this installation. Removing it would break a working
machine to tidy up after software that never touched it.

**So segler's warning about installing both does not apply here.** That README
says to run `uninstall.ps1` before installing from the Store, because a script
install silently shadows the packaged one by claiming the extension's default.
Neither Duckling route claims anything, so neither shadows the other; a machine
with both simply offers two Duckling entries under Open With, which is untidy
and not a defect. **Measured**: `uninstall.ps1` removed its own
`.pdf\OpenWithList` subkey and left the packaged `.pdf\OpenWithProgids` entries
in place.

## 4. The package is 605 MB, and that is the point of it

**Measured.** 821 MB staged, 605 MB packed, 62 files. `models\` and `pdfium\`
sit beside `duckling.exe` because `locate_assets` in `src/lib.rs` looks beside
the canonicalized executable and nowhere else, which is the same relative layout
`/usr/lib/duckling` has on Linux.

**Measured, and it is the thing the whole design rests on**: installed from the
MSIX, launched from the apps folder, the window came up without the *No models
found beside the application* status - so `locate_assets` resolved inside
`C:\Program Files\WindowsApps`. A PDF queued from the command line converted:
layout ran, headings and picture regions came back, bare DocLang was written
with its `assets/` beside it. `CHECKLIST.md` item 1 is the version of this that
counts, because it adds the network being off.

`makeappx` takes minutes rather than seconds, for the same reason
`packaging/debian/build-deb.sh` says xz does: three quarters of the contents are
ONNX weights that barely compress.

## 5. Launching the packaged application with files

**Measured.** The executable inside `C:\Program Files\WindowsApps` cannot be run
directly - `Start-Process` on it fails with *Access is denied*, which is the
package's ACL and not something to work around. segler's `screenshot.ps1` opens
its document and lets the file association find the packaged application;
Duckling claims no association, so that route does not exist here.

What works is the apps folder moniker with arguments:

    Start-Process "shell:AppsFolder\Excelano.Duckling_nbxmgv0sk86m4!Duckling" `
        -ArgumentList '"C:\path\to\report.pdf"'

and the application receives them as `std::env::args_os`, which is the same path
an Open With activation takes. `screenshot.ps1` uses it, and reads the family
name out of `identity.psd1` rather than carrying it.

## 6. What is here

| File | What it is |
| --- | --- |
| `install.ps1` | Copies the files, registers Open With, makes the Start menu shortcut |
| `uninstall.ps1` | Removes all of it. Copied into the install directory, because Add/Remove Programs points at it and a checkout may be gone |
| `runtime-files.ps1` | Finds the five DLLs §2 describes. Shared, so the packaged and side-loaded routes cannot ship different sets |
| `duckling.ico` | The application icon, nine sizes. Built from the Linux SVG, not drawn separately |
| `assets/` | The four PNGs `AppxManifest.xml` names and their scale variants, from the same SVG. Committed for the same reason the `.ico` is |
| `listing/` | The Store logo at the two sizes Partner Center's listing form accepts. Not in the package |
| `make-ico/` | The tool that builds all of it |
| `AppxManifest.xml.in` | The MSIX manifest, with the identity and the version left as placeholders |
| `identity.psd1` | What Partner Center assigned when the name was reserved. Not committed; `identity.psd1.example` is the template |
| `build-msix.ps1` | Builds the package from a release binary, and optionally signs it and runs the certification kit |
| `check-imports.ps1` | Walks the PE import table and refuses any DLL that is neither in-box nor shipped in the package |
| `screenshot.ps1` | Photographs the window at a size the Store accepts |
| `duckling.manifest` | The Win32 application manifest, embedded by `build.rs` |

## 7. Two scripts rather than an installer

Inherited from slipcase-desktop, argument unchanged: MSI through WiX, Inno Setup
and NSIS were all considered and all rejected, because each needs a toolchain
that is not on a stock Windows and not in this repository's build, to produce a
package that would do what forty lines of registry writes do.
`packaging/linux/install.sh` is a shell script for the same reason and these two
are its counterpart.

That rejection stands here, and the channel decides it too: the Store takes
MSIX, WiX builds MSI, and the two are not steps on one path. The scripts stay as
well - they are the per-user, no-toolchain, no-account route, and a Store
listing is not a reason to take that away from somebody who would rather not
have one.

## 8. The icons

`duckling.ico` is built from `packaging/linux/icons/duckling.svg`, which is the
source for every platform's icons and is not duplicated here:

    cd packaging/windows/make-ico && cargo run --release

Nine sizes - 16, 20, 24, 32, 40, 48, 64, 128, 256. The three the shell asks for
are 16, 32, and 48; the rest are those again at the display scalings Windows
offers, plus 256 for the extra-large view. Entries above 48 are stored as PNG
and the rest as bitmaps, which is the convention and saves a quarter of a
megabyte on the 256 alone.

The same run writes `assets/`, which is what the MSIX ships, and `listing/`,
which is what Partner Center's listing form takes and which is deliberately
*not* in the package: a file added to `assets` lands in the MSIX, and a package
that gains a file has to be certified again for an image no installed copy would
ever read.

`make-ico` is its own package rather than anything this crate depends on, so
nothing it uses reaches the shipped binary. It renders with `resvg` and
assembles with `ico`, both pure Rust.

## 9. The window's own icon, the taskbar, and the manifest

**Neither egui, eframe, nor winit sets an AppUserModelID.** `APP_ID` in
`src/main.rs` is `with_app_id`, which is Wayland's `xdg_toplevel.set_app_id` and
does nothing at all on Windows. Measured on slipcase-desktop by reading all three
crates.

That is left alone deliberately, and the Start menu shortcut carries no
AppUserModelID either. Setting one on the shortcut without the process declaring
the same identity through `SetCurrentProcessExplicitAppUserModelID` would break
the pairing rather than fix it - and that call is raw FFI, which
`#![deny(unsafe_code)]` puts out of reach. With neither side declaring one,
Windows derives both from the executable's path, they agree, and pinning and
taskbar grouping work.

**The window icon is embedded as bytes, not compiled into a resource.** Windows
takes a window's icon from a resource in the executable, and building one needs
`rc.exe` or `windres`. So `main.rs` carries `duckling.ico` through
`include_bytes!` and hands the 64-pixel entry to the window at startup: 64 is a
whole multiple of the sizes a display at 100% or 200% asks for - 16 and 32 in
the title bar, 32 and 64 in the task bar - so each of those is an integer
downsample rather than a resample of a resample. This is why the `.ico` is a
committed artifact in a repository that otherwise holds only sources.

**`build.rs` is the tree's only build script and it compiles nothing.** It hands
the MSVC linker `/MANIFEST:EMBED` and `/MANIFESTINPUT` and the linker that was
already linking the binary embeds `duckling.manifest`. Its only content is the
DPI declaration, which the certification kit reads out of the manifest rather
than out of the running process - slipcase-desktop's kit reported that
application as not DPI aware until this existed. **Measured**: the release
binary is subsystem 2 and carries `PerMonitorV2`, both on the first build.

## 10. What a Store build is

`build-msix.ps1` produces it and `RELEASE.md` has the process; what belongs here
is why it is shaped that way.

**Signing is not optional for a local install.** The shell will not accept an
unsigned MSIX, so unlike macOS there is no unsigned build-and-test loop. The
Store signs what it distributes, so the package that goes up is unsigned and the
throwaway-signed copy is only for installing locally - and the two must come
from one release binary with no rebuild between, because a rebuild of identical
source produces a different file. `build-msix.ps1` packs from the same
`target/release/duckling.exe` every time and only the signature differs.

**The signing certificate was already trusted**, because Partner Center assigns
`Publisher` per account and not per product: Duckling's is the same X.500 string
segler's and slipcase-desktop's are, so the throwaway certificate already in
`LocalMachine\TrustedPeople` from those applications' test signing matches this
one. **Measured** - the one administrator action those READMEs describe had
already been spent on this machine, and a different machine will have to spend
it again.

**The manifest declares `runFullTrust` and nothing else.** A capability asked for
and unused is a question at certification with no good answer, and the
justification field caps at 500 characters and truncates silently at the paste.

**The kit was run on 2026-09-05 and 23 of its 24 tests passed.** `DPIAwareness­Validation`
passed on the first run, which is worth saying because it is the one
slipcase-desktop failed until a `build.rs` existed; so did `File association
verbs`, which is the seventeen-extension association in §3 being accepted.

The one failure is `Blocked executables`, it is `OPTIONAL="TRUE"` on a
`Centennial` package, and all 58 of its messages were traced before anything
went into `$KNOWN_FINDINGS`. The long form is in that variable's comment in
`build-msix.ps1`; the short form is that forty-odd are the kit's
case-insensitive scan for `reg`, `cmd`, `csi`, `cdb` and `dnx` finding those
byte sequences inside ONNX weights, pdfium and DirectML - `layout_heron.onnx`
holds 20 occurrences of `cmd` where uniform random bytes would give 82, so the
models match *less* often than chance - and the `cmd.exe` strings are the Rust
standard library's own spawn path, identifiable by the rustc commit hash
compiled in beside them.

**One of the 58 is real, and it is a feature rather than a finding.**
`ShellExecuteW` is `opener::open` and `opener::reveal` at `src/main.rs:478` and
`:483` - the preview pane's Open and Show in folder buttons. Duckling does
launch something: the file a person just converted, in whatever opens it, when
they press the button. That is the honest difference from segler's version of
this finding, and the certification note says so in those words rather than
reusing that repository's.

Whether to submit with an optional test failing is David's decision;
`RELEASE.md` carries it and recording the finding does not take it.
