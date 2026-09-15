# Packaging

One directory per platform, plus `debian` for the way Linux is distributed, and
the files shared by all of them: `fetch-models.sh`, which puts the pinned models
and pdfium under `.models/` and `.pdfium/` at the repository root and is what
every package copies from; `version.sh`, the only thing that reads the version
out of `Cargo.toml`; `store-listing.md` and `store-listing.de-de.md`, the text
both stores are given; and `privacy-entry.html`, the privacy section pasted
into the legal page. `DESIGN.md` §8 has the reasoning behind each package's
shape.

## What every package carries

The executable, and beside it `models/` and `pdfium/`, the PDF and image
pipeline. The application finds them by looking beside its own executable
(`locate_assets` in `src/lib.rs`), so every platform's package puts them where
it looks: `/usr/lib/duckling/` on Linux with a symlink on `PATH`, the
application directory in an MSIX, and in a bundle `Contents/Resources/models`
and `Contents/Frameworks`, the second place `locate_assets` looks. There is no
download at run time and no code for one.

## linux

The desktop entry, which lists the document types Duckling reads so a file
manager offers it under Open With without making it the default for any of
them, and the icon. Install into a prefix, which defaults to `~/.local`:

    ./packaging/linux/install.sh
    ./packaging/linux/install.sh --prefix /usr/local     # for everyone
    ./packaging/linux/uninstall.sh

The script installs the executable with the models beside it under
`PREFIX/lib/duckling` and a symlink at `PREFIX/bin/duckling`, found by asking
`cargo metadata` where the target directory is.

`check-libraries.sh` runs the window under Wayland and under X11, records every
shared object the process mapped, and refuses any whose package `Depends` in
`debian/control.in` does not transitively reach. Run it after touching a
dependency; it needs a display, so it is a command and never a test. It queues
a file and presses nothing, so pdfium and the models stay unloaded: those are
the package's own files and not a `Depends` question.

## debian

The package the Excelano apt repository ships:

    ./packaging/fetch-models.sh
    cargo build --release
    ./packaging/debian/build-deb.sh

It writes `dist/duckling_VERSION_ARCH.deb`, compressed with xz at its highest
level because most of the contents are ONNX weights that barely compress, and
prints what the executable links beside what the package declares. The
executable links libc, libgcc and libstdc++; the display stack, the graphics
driver loader and the keyboard map libraries are opened by name at run time,
so `Depends` is written by hand and `check-libraries.sh` keeps it true.

One package, `duckling`, with the models under `/usr/lib/duckling` beside the
executable that finds them there. It carries no maintainer scripts:
`desktop-file-utils` and `hicolor-icon-theme` own the dpkg triggers on the
directories it writes into. `copyright` is DEP-5 because the package carries
three licences: Duckling's MIT, the models' (Docling's MIT and PaddleOCR's
Apache-2.0), and pdfium's BSD. `.github/workflows/linux.yml` runs lintian at
error and warning on every push, with the three `embedded-library` tags on
pdfium overridden in `debian/lintian-overrides`, which says why.

## The icon

`linux/icons/duckling.svg` is the source for every platform: a yellow duckling
on the fleet's blue square, full bleed and unframed, because a store applies
its own corner rounding and a drawing carrying a smaller shape or an outline
into that frame reads as a sticker. Check any change at 16, 32 and 128 pixels
on light and dark grounds. `macos/build-app.sh` renders the `.icns` from it
with `sips` at build time; `windows/make-ico` writes the `.ico`, the four PNGs
the MSIX manifest names and the Store listing logo, and `windows.yml` rebuilds
those on every push and refuses a difference, because they are committed
artifacts.

`icons/` holds the icon in two shapes, `duckling-square` and
`duckling-rounded`, each as an SVG and as PNGs at 256, 512, 1024, 1080 and
2160, for whichever a submission form wants: a store that masks what it is
given (the iOS and iPadOS Store, Icon Composer) wants the square, and a form
that draws what it is handed wants the rounded one. `windows/make-ico` writes
the directory and clips the rounded shape from the same source; neither is
edited by hand. The corner is 22.37% of the side drawn as a circular arc, which
does not tell apart from Apple's continuous curve below about 512 pixels.
Nothing in `icons/` ships: the deb installs named files out of `linux/icons`,
`build-msix.ps1` copies `windows/assets/*.png`, and no code reads one at run
time.

## windows

The MSIX the Microsoft Store distributes, and a script pair that installs the
same application without one:

    ./packaging/fetch-models.sh                      # in Git Bash
    cargo build --release
    powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -SelfSign
    powershell -ExecutionPolicy Bypass -File packaging\windows\install.ps1

Five DLLs ship inside the package beside the executable, four Visual C++
runtime files and DirectML, because `+crt-static` will not link the prebuilt
ONNX Runtime; `runtime-files.ps1` finds them for both install routes and
`check-imports.ps1` refuses any import that is neither in-box nor one of them.
Duckling claims no file type, so the manifest's one association carries no
display name and no logo, the scripts never write an extension's default
value, and `uninstall.ps1` never removes a `UserChoice`. `windows/README.md`
has the lane.

## macos

The application bundle the Mac App Store distributes:

    ./packaging/fetch-models.sh
    MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --target aarch64-apple-darwin
    ./packaging/macos/build-app.sh                         # dist/Duckling.app, unsigned
    ./packaging/macos/build-app.sh --store PROFILE         # dist/Duckling.pkg, what is uploaded

The build is Apple silicon only, because no prebuilt ONNX Runtime exists for
an Intel Mac; an Intel lane machine packages what it cannot run, `macos.yml`
runs it, and the `intel-mac` feature builds a runtime-less application for
measuring the rest. The models are resources and pdfium is a framework,
because a signed bundle will not carry them beside the executable. The sandbox
grants a file and not its folder, so the application asks for the folder
before writing beside a file that arrived alone. No document types are
declared, so no Open With on this platform. `check-install.sh` asks an
installed bundle what it is on the machine it is on, and `screenshot.sh`
photographs the window at a size App Store Connect accepts; both want an Apple
silicon Mac to say anything about a conversion. `macos/README.md` has the lane.
