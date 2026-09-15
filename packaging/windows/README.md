# Windows packaging

The MSIX the Microsoft Store distributes, and the pair of scripts that install
the same application without one. `DESIGN.md` §8 has the reasoning.

    ./packaging/fetch-models.sh                      # in Git Bash
    cargo build --release
    powershell -ExecutionPolicy Bypass -File packaging\windows\check-imports.ps1
    powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -SelfSign
    powershell -ExecutionPolicy Bypass -File packaging\windows\install.ps1
    powershell -ExecutionPolicy Bypass -File packaging\windows\uninstall.ps1

`install.ps1 -NoBinary` registers the Open With entries without copying an
executable, and `-Prefix DIR` puts the files somewhere else. `uninstall.ps1
-KeepFiles` removes the registrations and leaves the files. `build-msix.ps1
-SelfSign -Certify` from an elevated prompt also runs the Windows App
Certification Kit; the findings it expects are `$KNOWN_FINDINGS` in the
script, and a new one goes into that list with a traced reason or nowhere.

## The five DLLs

`+crt-static` cannot link the prebuilt ONNX Runtime `ort` fetches for this
target: it is compiled against the dynamic CRT and the link fails with
unresolved `__imp_` externals. So the runtime ships inside the package, beside
the executable where the loader finds it first: `vcruntime140.dll`,
`vcruntime140_1.dll`, `msvcp140.dll` and `msvcp140_1.dll`, taken from the
Visual Studio redistributable directory, which is the copy Microsoft ships for
app-local deployment and whose licence covers it. `.cargo/config.toml` says
why the flag is absent; do not add it back without rerunning the link.

The fifth is `directml.dll`. The dist `ort` chooses carries the DirectML
execution provider, so it is a hard import although docling.rs runs the CPU
provider and Duckling never selects another. In-box DirectML began at Windows
10 10.0.18362, `AppxManifest.xml.in` declares a floor of 10.0.17763, and an
in-box copy can be years older than the one the library was built against, so
the dist's own copy ships. `runtime-files.ps1` finds it by reading the
`cargo:rustc-link-search=native=` line out of `ort-sys`'s build output, the
directory the linker was given, rather than globbing a cache where two versions
can sit side by side. Whether that DirectML loads on 1809 at all is untested;
if the floor ever needs defending, raising it to 10.0.18362 is cheaper than
finding the machine.

`check-imports.ps1` walks the release binary's import table and refuses any DLL
that is neither in-box nor one of the five; it prints every name it sees, so
the listing's claim of no network connection is checkable against the
artefact: none of `ws2_32`, `winhttp`, `wininet`, `iphlpapi`, `urlmon`,
`netapi32`, `dnsapi`, `ncrypt` or `secur32` is imported. `pdfium.dll` is loaded
by name on the first PDF and never appears in the table. To see which copy of
each DLL a running install uses, read `Get-Process duckling | Select-Object
-Expand Modules`: every one of the five resolves inside the package directory
and none in `System32`. A clean machine, one with no Visual C++
Redistributable (check `Test-Path C:\Windows\System32\vcruntime140.dll`
first), proves only that the application started.

## No file type

Every type Duckling reads is somebody else's, so both install routes ask only
for a place in the Open With list. The MSIX declares one
`uap:FileTypeAssociation` named `documents` over seventeen extensions with no
`DisplayName` and no `Logo`, which lands in each extension's `OpenWithProgids`
as an `AppX…` ProgID. `install.ps1` writes `Applications\duckling.exe` with
`FriendlyAppName`, a command and `SupportedTypes`, plus
`<ext>\OpenWithList\duckling.exe`. Neither writes an extension's default value,
and `uninstall.ps1` must not remove a `UserChoice`: that key is a person's own
choice of what opens their PDFs. Both routes can be installed at once; a
machine with both offers two Duckling entries under Open With, and removing
the script install leaves the package's entries alone. `make-ico` writes four
images rather than segler's six because the two missing ones are file-type
logos.

## The package

`models\` and `pdfium\` sit beside `duckling.exe`, where `locate_assets` looks.
`makeappx` takes minutes rather than seconds, because most of the contents are
ONNX weights that barely compress. The shell will not accept an unsigned MSIX,
so the throwaway-signed copy is for installing locally and the unsigned one is
what goes to the Store, which signs it; both are packed from the same
`target\release\duckling.exe` with no rebuild between. Partner Center assigns
`Publisher` per account, so the throwaway certificate in
`LocalMachine\TrustedPeople` from another Excelano application's test signing
matches this one; a machine without it spends that one administrator action.
The manifest declares `runFullTrust` and nothing else.

The executable inside `C:\Program Files\WindowsApps` cannot be run directly
(`Start-Process` on it is *Access is denied*). Launch the packaged application
with files through the apps folder moniker, which is the path an Open With
activation takes:

    Start-Process "shell:AppsFolder\Excelano.Duckling_nbxmgv0sk86m4!Duckling" `
        -ArgumentList '"C:\path\to\report.pdf"'

`screenshot.ps1` does this and reads the family name out of `identity.psd1`.

The certification kit's `Blocked executables` test is optional on a
`Centennial` package and reports matches for `reg`, `cmd`, `csi`, `cdb` and
`dnx` inside ONNX weights, pdfium and DirectML, the Rust standard library's
`cmd.exe` spawn path, and `ShellExecuteW`, which is `opener::open` and
`opener::reveal` behind the preview pane's Open and Show in folder buttons.
The certification note in `store-listing.md` says so; submitting with the test
failing is David's decision.

## The icons and the manifest

`duckling.ico` is built from `packaging/linux/icons/duckling.svg`:

    cd packaging/windows/make-ico && cargo run --release

Nine sizes, 16 to 256; entries above 48 are stored as PNG. The same run writes
`assets/`, which the MSIX ships, and `listing/`, which Partner Center's listing
form takes and which is deliberately not in the package: a file added to
`assets` lands in the MSIX and a package that gains a file has to be certified
again. `make-ico` is its own package, so nothing it uses reaches the shipped
binary.

The window icon is embedded as bytes through `include_bytes!` rather than
compiled into a resource, because a resource compiler is a tool this build
keeps out; `main.rs` hands the 64-pixel entry to the window, a whole multiple
of the 16, 32 and 64 the title bar and taskbar ask for. Neither egui, eframe
nor winit sets an AppUserModelID and the Start menu shortcut carries none, so
Windows derives both from the executable's path and they agree. `build.rs`
hands the MSVC linker `/MANIFEST:EMBED` and `/MANIFESTINPUT` so that
`duckling.manifest`, whose only content is the DPI declaration, is embedded;
`windows.yml` reads `PerMonitorV2` and the GUI subsystem out of the release
binary.

## What is here

| File | What it is |
| --- | --- |
| `install.ps1` | Copies the files, registers Open With, makes the Start menu shortcut |
| `uninstall.ps1` | Removes all of it. Copied into the install directory, because Add/Remove Programs points at it and a checkout may be gone |
| `runtime-files.ps1` | Finds the five DLLs. Shared, so the packaged and side-loaded routes cannot ship different sets |
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

The two scripts are the per-user, no-toolchain, no-account route beside the
Store, the counterpart of `packaging/linux/install.sh`.
