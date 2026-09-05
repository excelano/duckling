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

Cloned from `segler/packaging/windows` by the Windows lane, which clones it
from slipcase-desktop's. What carries over: `.cargo/config.toml`, already
here, linking the CRT in; `build-msix.ps1`'s refusals; `make-ico` from the
SVG. What is new, and each is a measurement before it is a step:

- **`pdfium.dll` ships inside the package**, in the application directory
  beside `duckling.exe`, under `pdfium\`. `check-imports.ps1` refuses any
  import that does not ship with Windows; pdfium is loaded by name at run
  time and is not in the import table, so the check may pass as written.
  If it does not, the allowlist gains one entry with this paragraph as its
  reason. Whether the Store's software-dependency policy is satisfied by a
  DLL inside the package is what certification will say; slipcase-desktop's
  rejection was for a DLL *outside* it.
- **ONNX Runtime is a static library and `+crt-static` is set.** Whether
  the prebuilt `ort` fetches for `x86_64-pc-windows-msvc` links against the
  static CRT without conflict is the lane's first build. If it does not, the
  choice is between dropping `+crt-static` and declaring the VC runtime
  framework dependency, or building ONNX Runtime against the static CRT,
  and `DESIGN.md` §2 wants the reasoning either way.
- **The package is 700 MB.** The Store allows it; the listing should say it.
- **A C compiler is a build requirement on this lane**, for oniguruma under
  the tokenizer docling.rs carries. Visual Studio's is fine.

The Partner Center reservation is **Duckling**.

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
