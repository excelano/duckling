# macOS packaging

The application bundle the Mac App Store distributes, and the scripts that
build, check and photograph it. `DESIGN.md` §8 has the reasoning.

    build-app.sh          assembles dist/Duckling.app, signs it, wraps the Store .pkg
    Info.plist.in         the bundle's property list, @VERSION@ and @BUILD@ substituted
    Duckling.entitlements what a development build is signed with
    check-install.sh      asks an installed bundle what it is, on the machine it is on
    screenshot.sh         photographs the window at a size App Store Connect accepts
    display-mode.swift    switches a display to its HiDPI mode, for a walkthrough at 2x
    window-probe.swift    asks the window server whether a window appeared, for CI

    ./packaging/fetch-models.sh
    MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --target aarch64-apple-darwin
    ./packaging/macos/build-app.sh                         # dist/Duckling.app, unsigned
    ./packaging/macos/build-app.sh --store PROFILE         # dist/Duckling.pkg, what is uploaded

## Apple silicon only

`ort` links a prebuilt ONNX Runtime and its dist list for macOS carries only
`aarch64-apple-darwin`; Microsoft's own releases, which those builds are made
from, ship no `onnxruntime-osx-x86_64` or `onnxruntime-osx-universal2` from
1.28.0, the version `ort` pins. So there is no Intel slice to join, App Store
Connect reads the architectures out of the binary and lists the application for
Apple silicon, and an Intel Mac cannot run the release build. On an Intel lane
machine the release build cross-compiles and links, `.github/workflows/macos.yml`
on an arm64 runner is where it converts anything, and `check-install.sh` is
carried to the machine that can run the bundle.

The `intel-mac` feature turns `ort`'s `load-dynamic` on, which links no ONNX
Runtime and looks for a `libonnxruntime.dylib` at run time that no Intel Mac
has: everything docling.rs converts without a model still converts, a PDF or an
image fails in its own row with the loader's message, and the status line says
at startup that the build has no runtime in it. It is never a release build:
`build-app.sh --store` refuses an executable with no `OrtGetApiBase` in it, and
refuses an x86_64 one before that. It is the build for measuring the window,
the sandbox and the bundle on an Intel Mac, signed with the development
identity so that the sandbox is real:

    MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --features intel-mac
    ./packaging/macos/build-app.sh --binary target/release/duckling \
        --sign "Apple Development: David Anderson (Y79D796839)"
    open -a dist/Duckling.app

Add files through the button: a file given as an argument to a sandboxed
application cannot be read, which is the sandbox and not a defect.
Accessibility granted to the terminal lets `osascript` keystrokes and a
CGEvent click reach the window, and `window-probe.swift` asks the window server
whether it drew.

The floor is 13.4 and it is ONNX Runtime's: `otool -l` on the
`libonnxruntime.a` `ort` fetches reports `minos 13.4`, pdfium's arm64 slice
13.0, and nothing else more than 11. So `LSMinimumSystemVersion` is 13.4 and
the release build is made with `MACOSX_DEPLOYMENT_TARGET=13.4`, which
`build-app.sh --store` checks against the executable; Cargo's default for the
target is 11.0, and a bundle declaring 13.4 over an executable claiming 11.0 is
a promise the bundle breaks.

CoreML is linked in unasked: the dist `ort` selects is
`aarch64-apple-darwin+coreml`, so the executable links `CoreML.framework` and
carries that provider while docling.rs runs the CPU provider.

## The bundle layout

`codesign` treats everything under `Contents/MacOS` as nested code and will not
seal the ONNX weights there as resources, and a shared library the Store
accepts has to be nested code under `Contents/Frameworks`, signed with the
bundle's identity. So:

    Duckling.app/Contents/MacOS/duckling
    Duckling.app/Contents/Frameworks/libpdfium.dylib
    Duckling.app/Contents/Resources/models/...
    Duckling.app/Contents/Resources/duckling.icns

`locate_assets` in `src/lib.rs` looks in `../Resources/models` and
`../Frameworks` after looking beside the executable; docling.rs takes
`PDFIUM_DYNAMIC_LIB_PATH` as a directory holding the library under its
platform name. pdfium is fetched universal and thinned to the executable's
architecture. `cp -c` clones the models on APFS, so staging costs seconds and
no disk.

## The sandbox and the folder a file arrived without

`Duckling.entitlements` asks for the sandbox and user-selected files and
nothing else. A file a person drops on the window or picks in Add files is
granted on its own and its folder is not, so *Beside each file* over a single
dropped PDF would fail at the write, after the models had run. A folder dropped
or picked in Add folder is granted whole, and so is a destination chosen for
*Into a folder*.

So `src/main.rs` asks, once per folder, before anything is sent: `can_write_in`
in `src/lib.rs` creates and removes one empty entry in each folder a queued
file sits in, and for each folder that refuses, the standard open panel is put
up at that folder with the message *Allow Duckling to write beside the files
in ...: choose that folder*. Choosing it extends the grant for the rest of the
session. The probe is asked again afterwards rather than the answer trusted;
files whose folder is still not writable stay queued, and the status line says
so and names *Into a folder* as the other way out. The panel is macOS only. A
file given as a command-line argument (`open --args`) cannot be read at all,
*Operation not permitted*; CI's unsandboxed bundle is the only place the
argument route is used. A file the sandboxed process writes carries
`com.apple.quarantine`.

## No document types

`Info.plist.in` declares no `CFBundleDocumentTypes`, so Finder offers no Open
With. A document opened through Open With reaches a Mac application as an Apple
Event, not as an argument, and `main.rs` reads arguments; receiving the event
is the `unsafe` module slipcase-desktop carries in `src/opened_document.rs`,
and `CLAUDE.md` makes adding one a decision to take with David. Declaring the
types without the handler would have Finder offer Duckling and AppKit refuse
the document with a dialog blaming the application. Drops, the Add buttons and
the Dock work without it.

## The private-symbol check

`build-app.sh` refuses to bundle an executable or a library that imports a
symbol from a system framework which that framework's own public headers do
not declare, which is the line Mac App Store review draws under Guideline
2.5.1. `Cargo.toml`'s `[patch.crates-io]` pins winit so that
`CGSSetWindowBackgroundBlurRadius` and `CGSMainConnectionID` are not in the
executable; `CGShieldingWindowLevel`, which winit also uses, is declared in
`CGDirectDisplay.h` and passes. pdfium's imports from libSystem, CoreGraphics
and CoreFoundation are all declared. One symbol is allowed by name:
`___CFConstantStringClassReference`, which clang emits for every
`CFSTR("...")` literal, is exported by CoreFoundation's `.tbd` and declared in
no header, and reaches this executable through the CoreML provider objects
inside ONNX Runtime.

## Signing, inside out

`build-app.sh --sign` signs `libpdfium.dylib` first with the identity alone,
then the bundle with the identity and the entitlements, not `--deep`, which
would give the library the sandbox entitlement. The Store path does the same
with `--options runtime` on both and the profile's two identifiers added to the
bundle's entitlements, then `productbuild` wraps it and `lsregister -u`
withdraws whatever claim a development build at the same path left, because a
Store build in `dist/` is what `open -a Duckling` would reach and the kernel
kills it. pdfium's arm64 slice arrives carrying the ad-hoc signature Apple's
linker gives every arm64 binary; it verifies, it is not a signature the Store
accepts, and `check-install.sh` asks for the bundle's own team on it.

A Store-signed bundle launches nowhere but through the Store or TestFlight, so
the walkthrough runs against the arm64 bundle signed with the Apple Development
identity: the same code and the same entitlements, the sandbox real.
`SUBMITTING.local.md`, which is not committed, has the account half of a
submission.

## The icon

`build-app.sh` renders the ten sizes `iconutil` wants from
`packaging/linux/icons/duckling.svg` with `sips`, rewriting the SVG's declared
size before each rendering so that every size is a true rendering rather than
an upscale.
