# macOS packaging

`DESIGN.md` §8. The application bundle the Mac App Store distributes, and the
scripts that build, check and photograph it.

    build-app.sh          assembles dist/Duckling.app, signs it, wraps the Store .pkg
    Info.plist.in         the bundle's property list, @VERSION@ and @BUILD@ substituted
    Duckling.entitlements what a development build is signed with
    check-install.sh      asks an installed bundle what it is, on the machine it is on
    screenshot.sh         photographs the window at a size App Store Connect accepts
    window-probe.swift    asks the window server whether a window appeared, for CI

**This directory is `slipcase-desktop/packaging/macos` cloned.** That
repository has been through Mac App Store review, a rejection under Guideline
2.5.1, and a resubmission; its README is the long form of the signing, the
profile, the private-symbol check and the Launch Services claim, and is worth
reading before changing anything here. What is genuinely different in this copy
is not a rename, and it is the whole of the rest of this file.

Everything below marked **measured** was measured on the Mac lane on
2026-09-05, on David's Intel Mac, against this application.

---

## 1. The one that changed the product: Apple silicon only

`RELEASE.md` sent this lane to build a universal binary, the way
slipcase-desktop does. **It cannot be built, from any machine.**

`ort` links a prebuilt ONNX Runtime, and its dist list for macOS - `dist.tsv`
in `ort-sys` 2.0.0-rc.13 - carries two rows, both `aarch64-apple-darwin`. There
is no `x86_64-apple-darwin` row. Microsoft's own releases, which pyke's builds
are made from, stopped shipping `onnxruntime-osx-x86_64` and
`onnxruntime-osx-universal2` at 1.28.0, the version `ort` pins: `gh release
view v1.28.0 -R microsoft/onnxruntime` lists `onnxruntime-osx-arm64` and
nothing else for the platform, and 1.28.2 and 1.29.0 are the same. So the
Intel slice does not exist to join, and the alternative - building ONNX
Runtime from source for x86_64 - is the project of its own that the Windows
lane already declined for the static CRT.

Two consequences, and the second is the one to hold on to.

**The Store build is arm64 only.** App Store Connect reads the architectures
out of the binary and lists the application as needing a Mac with Apple
silicon; an Intel Mac browsing the Store does not see a Get button. Apple sold
its last Intel Mac in 2023 and has said macOS 26 is the last release for them,
so this is where every Mac application is going, and this one arrives there
first for want of a library rather than by choice.

**The machine that packages it cannot run it.** David's Mac is Intel. The
release build cross-compiles here in four minutes and links cleanly, and
nothing on this machine can execute the result. So the lane produces a
package it has never launched, and that fact shapes everything else in this
directory: `check-install.sh` exists to be carried to the machine that can;
`.github/workflows/macos.yml` runs on an arm64 runner and is, until a person
sits at an Apple silicon Mac, the only place the shipped architecture converts
anything; and the `intel-mac` feature in `Cargo.toml` exists so that the
window, the sandbox and the bundle can still be measured on the machine at
hand.

**What `intel-mac` is.** A build with `ort`'s `load-dynamic` feature on, which
links no ONNX Runtime and looks for a `libonnxruntime.dylib` at run time that
no Intel Mac has. Everything docling.rs converts without a model still
converts; a PDF or an image fails in its own row with the loader's message, and
the status line says at startup that the build has no runtime in it. It is
never a release build: `build-app.sh --store` refuses an executable with no
`OrtGetApiBase` defined in it, and refuses an x86_64 one before that.

    MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --features intel-mac
    ./packaging/macos/build-app.sh --binary target/release/duckling \
        --sign "Apple Development: David Anderson (Y79D796839)"

**The floor is 13.4, and it is ONNX Runtime's.** `otool -l` on the
`libonnxruntime.a` that `ort` fetches reports `minos 13.4`; pdfium's arm64 slice
reports 13.0; nothing else in the tree asks for more than 11. So
`LSMinimumSystemVersion` is 13.4 and the release build is made with
`MACOSX_DEPLOYMENT_TARGET=13.4`, which `build-app.sh --store` checks against
the executable. Cargo's default for the target is 11.0, and a bundle
declaring 13.4 over an executable claiming 11.0 is a promise to a person that
the bundle then breaks. slipcase-desktop's floor is 12.0 for its own reason
and the two need not agree.

**CoreML is linked in unasked**, the same shape as DirectML on Windows: the
dist `ort` selects is `aarch64-apple-darwin+coreml`, so the executable links
`CoreML.framework` and carries the CoreML execution provider while docling.rs
runs the CPU provider and this application never selects another. On this
platform it costs a framework import and some object code rather than an 18 MB
DLL, so it is noted here and carried in `DESIGN.md` §9 under the same upstream
thread rather than given a section.

## 2. Where the models and pdfium go, because a bundle is not a directory

Linux and Windows put `models/` and `pdfium/` beside the executable. A bundle
cannot: `codesign` treats everything under `Contents/MacOS` as nested code and
will not seal 734 MB of ONNX weights there as resources, and a shared library
the Store accepts has to be nested code under `Contents/Frameworks`, signed
with the bundle's identity. So the layout is

    Duckling.app/Contents/MacOS/duckling
    Duckling.app/Contents/Frameworks/libpdfium.dylib
    Duckling.app/Contents/Resources/models/...
    Duckling.app/Contents/Resources/duckling.icns

and `locate_assets` in `src/lib.rs` looks in `../Resources/models` and
`../Frameworks` after looking beside the executable. docling.rs takes
`PDFIUM_DYNAMIC_LIB_PATH` as a directory holding the library under its platform
name, and `Frameworks/libpdfium.dylib` is that. pdfium is fetched universal and
thinned to the executable's architecture, because an x86_64 slice in an
arm64-only bundle is 7 MB nothing loads.

**Measured:** the bundle is 805 MB, the models 734 MB of it, the executable 66
MB, pdfium 7 MB thinned. The package `productbuild` makes of it is what §7
below records. `cp -c` clones the models on APFS, so staging costs eighteen
seconds and no disk.

## 3. The sandbox, and the folder a file arrived without

Every Store binary is sandboxed, and `Duckling.entitlements` asks for the
sandbox and user-selected files and nothing else. What that grant covers is
the thing to understand, because this application writes beside its inputs.

A file a person drops on the window or picks in Add files is granted on its
own. Its folder is not. slipcase-desktop measured exactly this on its save
path - "the grant a person gives through the open panel covers the file and
not its directory" - and the consequence here is that *Beside each file* over
a single dropped PDF would fail at the write, after the models had run, with
an error a person cannot act on. A folder dropped or picked in Add folder is
granted whole, and so is a destination folder chosen for *Into a folder*, so
neither of those paths is affected.

So `src/main.rs` asks, once per folder, before anything is sent: `can_write_in`
in `src/lib.rs` creates and removes one empty entry in each folder a queued
file sits in, and for each folder that refuses, the standard open panel is put
up at that folder with the message *Allow Duckling to write beside the files
in ...: choose that folder*. Choosing it is the sandbox's own way of extending
a grant, and it holds for the rest of the session. The probe is asked again
afterwards rather than the answer trusted; files whose folder is still not
writable stay queued, and the status line says so and names *Into a folder*
as the other way out. The panel is macOS only, because on the other two
platforms a folder that refuses a write is a permissions problem that a panel
would not fix and would misdescribe.

This is a design decision taken on the lane without David, because the
alternative was a Store build whose first drop fails, and it is the pattern
Apple designed the open panel for. It is reversible in one function, and it is
the first thing the Apple silicon walkthrough should look at.

**Measured, on the `intel-mac` build signed with an Apple Development
identity, under a real sandbox.** A file given on its own: the write probe is
refused, the panel appears at the file's folder with the message, choosing
the folder makes the conversion write `field-notes.dclg` beside
`field-notes.docx`, and the written file carries `com.apple.quarantine` the
way everything a sandboxed process writes does. Cancelling the panel leaves
the row Queued with the status line saying *1 left queued until their folder
is allowed, or choose Into a folder*. A destination chosen through *Into a
folder* is granted by the same panel and needs no second one. And a file
given as a command-line argument - `open --args` - cannot even be read,
*Operation not permitted*, because an argument grants nothing; that is the
sandbox working, it reaches no person, and CI's unsandboxed bundle is the
only place the argument route is used. What is not yet measured is the same
on the arm64 build, which is `CHECKLIST.md` item 19.

## 4. No document types, and what that costs a person

The desktop entry lists fifteen types and the MSIX one association over
seventeen extensions, so a file manager on Linux or Windows offers Duckling
under Open With. `Info.plist.in` declares nothing, and Finder does not.

It is not for want of a declaration: `CFBundleDocumentTypes` with
`LSHandlerRank` Alternate over the same types would be the exact counterpart,
and would claim nothing as default. It is that a document opened through Open
With reaches a Mac application as an Apple Event, not as an argument, and
`main.rs` reads arguments. slipcase-desktop receives that event in
`src/opened_document.rs`, the one module in that crate that writes `unsafe`,
and `CLAUDE.md` here makes adding one a decision to take with David. Declaring
the types without the handler is worse than neither: Finder would offer
Duckling, a person would choose it, and AppKit would refuse the document with a
dialog blaming the application. So it is neither, in this release, and the
changelog's Open With claim is scoped to Windows on purpose.

What a person loses: the right-click route. Drops, the Add buttons and the
Dock still work, which is how the application expects to be used. What
reinstating it costs: the module from slipcase-desktop with its header changed,
`deny(unsafe_code)` lifted for that one file, the `objc2` features it needs,
and a list of types in the plist. `DESIGN.md` §9 carries it as an open thread.

## 5. The private-symbol check, and the one name it lets through

`build-app.sh` refuses to bundle an executable or a library that imports a
symbol from a system framework which that framework's own public headers do not
declare. slipcase-desktop wrote it after a review cycle lost to
`_CGSSetWindowBackgroundBlurRadius`, which `winit` 0.30.13 declares whether or
not it is called, and `Cargo.toml`'s `[patch.crates-io]` is the same pin that
repository carries until a winit release gates it.

**Measured:** without the pin, the executable carries `CGSMainConnectionID` and
`CGSSetWindowBackgroundBlurRadius` and the check refuses it; with the pin, both
are gone and `CGShieldingWindowLevel`, which winit also uses, is declared in
`CGDirectDisplay.h` and passes. pdfium imports 159 symbols from libSystem,
CoreGraphics and CoreFoundation and every one is declared.

**One symbol is allowed by name, and this is the first copy of the check to
need that.** `___CFConstantStringClassReference` is what clang emits for every
`CFSTR("...")` literal. CoreFoundation's `.tbd` exports it, no header has
declared it since the macro became a compiler builtin, and every Objective-C
program ever shipped carries it. It reaches this executable through the CoreML
provider objects inside ONNX Runtime, which slipcase-desktop's binary has no
counterpart of. It is let through with its reason in the script, the way the
Windows kit's findings are baselined in `build-msix.ps1`, and nothing else is.

## 6. Signing, inside out

`build-app.sh --sign` signs `libpdfium.dylib` first with the identity alone,
then the bundle with the identity and the entitlements. Not `--deep`: Apple
deprecated it because it signs whatever it finds with the outer code's
entitlements, and a library carrying the sandbox entitlement is wrong. The
Store path does the same with `--options runtime` on both and the profile's
two identifiers added to the bundle's entitlements, then `productbuild` wraps
it and `lsregister -u` withdraws whatever claim a development build at the same
path left, for the reason slipcase-desktop measured on 2026-09-04: a Store
build sitting in `dist/` is what `open -a Duckling` would reach, and the kernel
kills it.

The arm64 slice of pdfium arrives from bblanchon carrying the ad-hoc signature
Apple's linker gives every arm64 binary. It verifies, and it is not a signature
the Store accepts; `check-install.sh` asks for the bundle's own team on it.

## 7. What is not yet measured, and where it gets measured

- **The Store package**, which needs the provisioning profile no lane can
  make: `RELEASE.md` says what David creates and `SUBMITTING.local.md`, which
  is not committed, names the account half. An unsigned `productbuild` of the
  bundle here comes to the size recorded in `packaging/store-listing.md`.
- **A conversion on arm64**, which `macos.yml` does on every push through the
  demo documents, and which a person does on an Apple silicon Mac against the
  TestFlight build. `CHECKLIST.md`.
- **The folder panel on the arm64 build**, §3 having measured it on the
  Intel one; the code is the same and the sandbox is the same, and the
  walkthrough is where that gets said rather than assumed.

## The icon

One drawing, `packaging/linux/icons/duckling.svg`, which `packaging/README.md`
names as the source for every platform. `build-app.sh` renders the ten sizes
`iconutil` wants with `sips`, rewriting the SVG's declared size before each
rendering so that every size is a true rendering rather than an upscale of a
64-pixel bitmap; slipcase-desktop measured both ways. Segler's macOS note about
three `.icns` does not apply: that application owns two document types and
draws each, and this one owns none.
