# Release: getting Duckling into apt and two stores, repeatably

**This is the process, not the history.** What a given release did is in
`git log` and `CHANGELOG.md`; what is here is what the next one costs and in
what order. Anything a machine can do is a script under `packaging/`; where a
step is prose, that is a claim it cannot be scripted, and a later reader is
invited to prove it wrong. The loop is segler's, which is slipcase-desktop's,
which is the hand-cut loop in the fleet's `~/notes/releasing.md`.

Two documents are named here and not committed, because each carries an
account's own identifiers: `packaging/windows/SUBMITTING.local.md` and
`packaging/macos/SUBMITTING.local.md`. `packaging/windows/identity.psd1` is the
same and has an `identity.psd1.example` beside it.

## The order

1. **Linux**, which needs no other machine and where most shared work lands.
2. **Windows**, on the Windows lane.
3. **macOS**, on the Mac lane.
4. **Back on Linux**, for the readiness review across all three.

Nothing is submitted to a store until step 4. apt is the exception, taken
deliberately: it is our own repository, publishing is one command and
unpublishing is a prune.

## One number, three spellings

`Cargo.toml` holds the version and nothing else should. `packaging/version.sh`
is the only thing that reads it.

| Where | Shape | Rule |
| --- | --- | --- |
| `Cargo.toml` | `X.Y.Z` | The source. |
| `AppxManifest.xml` | `X.Y.Z.0` | Four parts, and the Store requires the fourth to be `0`. |
| `Info.plist` `CFBundleShortVersionString` | `X.Y.Z` | What a person sees. |
| `Info.plist` `CFBundleVersion` | the first-parent commit count | Must increase on every upload, including a rejected one resubmitted unchanged. |

**Bump only for a number that has been tagged.** Ask `git tag --list` before
deciding.

## What is different about this application

Every lane starts from segler's directory of the same name, and every lane
has more to do than a rename, for one reason: **the package carries 740 MB
of models and a shared library**, and the application finds them beside its
own executable. `packaging/fetch-models.sh` puts them at the repository root
and verifies them by hash; each lane's build script copies them next to the
executable as `models/` and `pdfium/`. The Linux script is the reference for
the layout.

The Windows lane, run 2026-09-05, found a second reason: it ships five more
DLLs than any other application in the fleet, because `+crt-static` will not
link the ONNX Runtime this application uses. That section says what it costs.

pdfium is per platform, and the fetch script pins all three: docling.rs's
own Linux x64 build, and bblanchon's prebuilts at `chromium/8035` for
Windows x64 (`pdfium.dll`) and macOS (`libpdfium.dylib`, universal), each by
the archive's hash. On Windows the script runs under Git Bash, which has
the `tar` and `sha256sum` it needs. The Linux hash was verified by a run;
the other two were hashed on Linux from the archives and are first
exercised on their lanes.

## Linux

    ./packaging/fetch-models.sh
    cargo build --release
    ./packaging/linux/check-libraries.sh          # both display backends
    ./packaging/debian/build-deb.sh
    ./packaging/preflight.sh --ci

`preflight.sh` is the gate: a clean tree, nothing unpushed, both changelogs
naming the version, a version the Appx spelling can represent, the models
present and verified, silent clippy, a formatted tree, a passing suite, and
CI green on `HEAD`. It refuses and never repairs.

Then tag, release, and ship:

    git tag -a vX.Y.Z
    gh release create vX.Y.Z dist/duckling_X.Y.Z_amd64.deb --notes-file …
    apt-ship duckling vX.Y.Z -y

amd64 only, and say so wherever the install is written.

**The package is most of a gigabyte, and that is a question for apt before
it is a question for anything else.** The Excelano apt repository has
shipped packages of a few megabytes. Whether the host serves a 700 MB file
comfortably, and whether `rebuild.sh` and the mirror steps in
`~/notes/excelano_apt.md` handle it, is measured on the first release rather
than assumed. If it does not, the `.deb` lives on the GitHub release and the
apt entry waits.

## Windows

Cloned from `segler/packaging/windows` on 2026-09-05, which clones it from
slipcase-desktop's. The lane has been run once; what follows is the process,
and `packaging/windows/README.md` is where the measurements behind it live.

The build machine needs Visual Studio - a C compiler for oniguruma under the
tokenizer docling.rs carries, the Windows 10/11 SDK for `makeappx`, `makepri`
and `signtool`, and the redistributable directory the four runtime DLLs are
taken from - and Git for Windows, whose Git Bash is what `fetch-models.sh`
runs under and whose `sh` is what `build-msix.ps1` asks for the version.

    ./packaging/fetch-models.sh                      # in Git Bash
    cargo build --release
    powershell -ExecutionPolicy Bypass -File packaging\windows\check-imports.ps1
    powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -SelfSign

Then, from an **elevated** prompt, the certification kit, which is the one step
here that needs administrator and so is David's:

    powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -SelfSign -Certify

and to install the signed copy and walk `CHECKLIST.md` against it:

    Get-AppxPackage Excelano.Duckling | Remove-AppxPackage    # if rebuilding
    Add-AppxPackage dist\Duckling-X.Y.Z.0-x64.msix

The copy that goes to Partner Center is the **unsigned** one: rerun
`build-msix.ps1` without `-SelfSign` from the same release binary, with no
rebuild between, because a rebuild of identical source produces a different
file.

**What the lane found, because two of the three were not the expected
answers.** `DESIGN.md` §2 carries the reasoning and this is the short form:

- **`+crt-static` cannot be used.** The prebuilt ONNX Runtime is a
  dynamic-CRT build and the link fails with 63 unresolved externals. The
  four Visual C++ runtime DLLs ship inside the package instead, beside the
  executable. `.cargo/config.toml` is now a file of comments with no settings
  in it, saying why the flag every other repository in the fleet carries is
  absent here.
- **DirectML is linked in unasked**, so its DLL ships too - 18.5 MB, the copy
  pyke ships beside the library actually linked rather than whatever the
  machine has. `DESIGN.md` §9 holds the upstream question.
- **`pdfium.dll` ships inside the package** and is loaded by name at run time,
  so it never enters the import table and `check-imports.ps1` passes as
  written. This was the one prediction that held.
- **The package is 605 MB**, packed from 821 MB staged. The Store allows it and
  `packaging/store-listing.md` says it.
- **The certification kit passed 23 of its 24 tests**, run 2026-09-05.
  `DPIAwarenessValidation` passed on the first build, which is the test
  slipcase-desktop failed until it had a `build.rs`. The one failure is
  `Blocked executables`, optional on a Centennial package, and all 58 of its
  messages were traced before any of it was baselined.

**That last bullet is not a new decision, and the fleet has already taken it
once.** slipcase-desktop met the same failing test, traced it to the same two
real causes - the Rust standard library's spawn path, and `ShellExecuteW` under
`opener` doing what the Open button exists to do - and David decided on
2026-08-28 to submit with it failing. That application's 0.1.2 passed
certification and was published on 2026-08-30 with the test failing exactly as
it fails here; its rejection, the one that produced `check-imports.ps1`, was
policy 10.2.4.1 over VCRUNTIME140.dll and unrelated.

So the question here is only whether anything about Duckling changes that
answer, and the honest report is that one thing might: **volume.**
slipcase-desktop's finding was six messages and this one is fifty-eight,
because 734 MB of model weights plus pdfium and DirectML give the kit's
three-letter scan far more bytes to find itself in. The kind of finding is
identical and none of it is removable short of dropping the Open and Show in
folder buttons; the length of the list a reviewer reads is not.
`packaging/windows/SUBMITTING.local.md` carries the paragraph to paste into
Notes for certification, and it leads with the model files for that reason.

**Run the kit directly rather than through `-Certify` if the disk is tight.**
That switch implies `-SelfSign`, so it re-stages 821 MB and re-packs 605 MB
before testing anything. `appcert.exe` against the existing package followed by
`build-msix.ps1 -ReadReport` reaches the same gate and costs nothing.

`check-imports.ps1` now asks two questions rather than one - in-box, or shipped
in the package - and the five shipped names are spelled in three files that
`windows.yml` compares against each other on every push.

The Partner Center reservation is **Duckling**, and Product identity assigned
`Excelano.Duckling` with the Excelano account's publisher, which is the same
X.500 string segler and slipcase-desktop carry. `packaging/windows/identity.psd1`
holds it and is not committed.

## macOS

Cloned from `segler/packaging/macos` by the Mac lane. What carries over:
`build-app.sh`, the entitlements, the universal binary, `CFBundleVersion`
from `version.sh --build`. What is new: `models/` and `pdfium/` under
`Contents/MacOS` (or `Contents/Resources` with `locate_assets` taught the
second place; decide on the lane), `libpdfium.dylib` universal from
bblanchon, signed with the bundle, and the sandbox entitlements unchanged
since the application opens nothing but the files it is given. No document
type declarations: Duckling owns no format. The winit patch for Guideline
2.5.1 applies here as it does to segler until a winit release carries the
gate.

No App Store Connect record exists yet. The bare name is the first ask and
"Duckling Converter" the fallback; `packaging/store-listing.md` says which
was taken once one is.

## Step 4: the readiness review

Before either store submission, on Linux, with all three artefacts built from
one tagged commit:

- `packaging/store-listing.md` agrees with `CHANGELOG.md`, claim by claim,
  against the built application and not against memory.
- The version is the same in every spelling, and `CFBundleVersion` is higher
  than the last upload's.
- `CHECKLIST.md` has been run on each platform against the packaged
  application, not a developer build, with the network off for its first
  item.
- apt is serving the version the stores are about to be given, or the
  `.deb` is on the release and the apt entry is a recorded exception.
