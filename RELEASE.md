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
3. **macOS**, on the Mac lane, which packages a build it cannot run;
   `macos.yml` and TestFlight are where that build runs.
4. **Back on Linux**, for the readiness review across all three.

Nothing is submitted to a store until step 4. apt is the exception, taken
deliberately: it is our own repository, publishing is one command and
unpublishing is a prune.

**0.1.0 ships from steps 1, 2 and 4 with step 3 unfinished.** Decided
2026-09-06. The Mac lane has run as far as an Intel Mac can run it and its
build has not yet been run by a person, because that takes an Apple silicon Mac
and a TestFlight build. apt and the Microsoft Store do not wait on that. The
Mac submission comes from the same tag when the walkthrough has happened, which
the version scheme allows because `CFBundleVersion` counts commits rather than
uploads, and it gets its own step 4.

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
Windows x64 (`pdfium.dll`) and macOS (`libpdfium.dylib`, universal, thinned to
the executable's architecture when bundled), each by the archive's hash. On
Windows the script runs under Git Bash, which has the `tar` and `sha256sum`
it needs; macOS has both. All three hashes have been verified by a run on
their lanes.

The Mac lane, run the same day, found a third reason, and it is the largest:
**the Mac build is Apple silicon only**, because no prebuilt ONNX Runtime
exists for an Intel Mac, and the lane machine is one. That section says what
follows from it.

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

Cloned from `slipcase-desktop/packaging/macos` on 2026-09-05, on the Mac lane,
which is an Intel Mac. The lane has been run once as far as an Intel Mac can
run it; what follows is the process, and `packaging/macos/README.md` is where
the measurements behind it live.

    ./packaging/fetch-models.sh
    MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --target aarch64-apple-darwin
    ./packaging/macos/build-app.sh --store ~/Downloads/Duckling_Mac_App_Store.provisionprofile
    ./packaging/macos/check-install.sh dist/Duckling.app

`--store` produces what a submission is: the bundle carrying the profile as
`embedded.provisionprofile`, signed for distribution inside out - pdfium first,
then the bundle - wrapped by `productbuild --component` into a signed `.pkg`.
Nothing account-specific is written down: the team and application identifier
are read out of the profile. It refuses before it builds on a missing, invalid
or expired profile, on an application identifier that does not match
`CFBundleIdentifier`, on anything but exactly one matching signing identity of
each kind, on an x86_64 executable, on one with no ONNX Runtime linked in, on
an executable whose floor disagrees with the property list's, and on a file
still marked with quarantine, which is the rejection slipcase-desktop's build
165 met by email. It also refuses, on any build, an executable or a pdfium
that imports a symbol from a system framework which that framework's public
headers do not declare - Guideline 2.5.1, the review cycle slipcase-desktop
lost, and the reason `Cargo.toml` carries a winit pin.

Then validate without submitting, and upload; the two commands are printed by
the script and `packaging/macos/SUBMITTING.local.md` holds the key and the
account half.

**What the lane found, and the first is the one that shapes the rest.**
`DESIGN.md` §2 carries the reasoning and this is the short form:

- **The build is Apple silicon only.** `ort` has no prebuilt ONNX Runtime for
  `x86_64-apple-darwin` and neither has Microsoft since 1.28.0, so the
  universal binary this section once asked for cannot be built from any
  machine. The Store lists the application for Apple silicon from the binary.
- **The lane machine cannot run the build.** David's Mac is Intel. The
  release build cross-compiles here in four minutes; nothing here executes
  it. `.github/workflows/macos.yml` runs the suite, the demo conversions and
  the window probe on an arm64 runner, and the walkthrough in `CHECKLIST.md`
  is done against the TestFlight build on an Apple silicon Mac. The
  `intel-mac` feature builds the application with no ONNX Runtime in it for
  measuring everything else here; on this Mac every `cargo` command needs
  `--features intel-mac` or `ort-sys` refuses at once.
- **The floor is macOS 13.4**, ONNX Runtime's, read off the library. So
  `MACOSX_DEPLOYMENT_TARGET=13.4` on the release build, and `--store` checks it.
- **The models are resources and pdfium is a framework**, because a bundle
  cannot carry 734 MB under `Contents/MacOS`; `locate_assets` learnt the
  second place. 805 MB of bundle, 594 MB of package.
- **The sandbox grants a file and not its folder**, so `src/main.rs` asks for
  the folder before writing beside a file that arrived alone. Measured on the
  `intel-mac` build under a real sandbox; `packaging/macos/README.md` §3.
- **No document types**, so no Open With on this platform, because receiving
  an opened document needs the `unsafe` module `CLAUDE.md` reserves for David.
  `DESIGN.md` §9.
- **CoreML is linked in unasked**, the DirectML story again, carried in the
  same `§9` thread.

**The signing identities, whose names differ from the portal's labels:**

    Apple Distribution: Excelano LLC (9K6W5PMFYP)
    3rd Party Mac Developer Installer: Excelano LLC (9K6W5PMFYP)
    Developer ID Application: Excelano LLC (9K6W5PMFYP)

The middle one is what the portal calls *Mac Installer Distribution*; it signs
packages rather than code, so it does not appear under `security find-identity
-p codesigning` and its absence there is correct. All three are on the lane
machine.

**Three things exist only once David makes them in a browser**, in this order,
and `SUBMITTING.local.md` has the clicks: the App ID `com.excelano.duckling`,
the Mac App Store provisioning profile against it, and the App Store Connect
record. The bare name **Duckling** is the first ask and "Duckling Converter"
the fallback; `packaging/store-listing.md` says which was taken once one is.
The support and privacy pages on `excelano.com` are the fourth thing, and a
submission blocker.

**A Store-signed build cannot be launched off the Store**, and this one could
not be launched here anyway. Screenshots therefore need an Apple silicon Mac
and a bundle signed with another identity from the same commit, and the
walkthrough against the real article goes through TestFlight.

**A rejection can arrive only by email.** An upload can answer *UPLOAD
SUCCEEDED with no errors* and be refused afterwards with nothing in the web
interface saying so. Check mail after every upload.

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
