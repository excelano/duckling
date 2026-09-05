# Packaging

`DESIGN.md` §8. One directory per platform, plus `debian` for the way Linux is
distributed, and four files shared by all of them: `fetch-models.sh`, which
puts the pinned models and pdfium under `.models/` and `.pdfium/` at the
repository root and is what every package copies from; `version.sh`, the only
thing that reads the version out of `Cargo.toml`; `preflight.sh`, which asks
everything that must be true before a release at once; and
`store-listing.md`, the text both stores are given.

The shape is `excelano/slipcase-desktop`'s through `excelano/segler`, and
where a file here says something was measured, it was measured there first
unless the file says otherwise.

## What every package carries

The executable, and beside it `models/` and `pdfium/`: about 740 MB that are
the PDF and image pipeline. The application finds them by looking beside its
own executable (`locate_assets` in `src/lib.rs`), so every platform's package
puts them in the same place relative to it: `/usr/lib/duckling/` on Linux
with a symlink on `PATH`, the application directory in an MSIX, `Contents/MacOS`
in a bundle. There is no download at run time and no code for one.

## linux

The freedesktop half: the desktop entry, which lists the document types
Duckling reads so a file manager offers it under Open With, and the icon.
Install it into a prefix, which defaults to `~/.local`:

    ./packaging/linux/install.sh
    ./packaging/linux/install.sh --prefix /usr/local     # for everyone
    ./packaging/linux/uninstall.sh

The script installs the executable with the models beside it under
`PREFIX/lib/duckling` and a symlink at `PREFIX/bin/duckling`, found by asking
`cargo metadata` where the target directory is.

Duckling registers no media type of its own. It owns no format; it reads
other people's. The entry lists fifteen of the types it reads, the ones a
person is likely to right-click, and a file manager adds Duckling to those
types' Open With menus without making it the default for any of them.

`check-libraries.sh` runs the window under Wayland and under X11, records
every shared object the process mapped, and refuses any whose package
`Depends` in `debian/control.in` does not transitively reach. Run it after
touching a dependency. It needs a display, so it is a command and never a
test. It queues a file and presses nothing, so pdfium and the models stay
unloaded: those are the package's own files and not a `Depends` question.

## debian

The package the Excelano apt repository ships:

    ./packaging/fetch-models.sh
    cargo build --release
    ./packaging/debian/build-deb.sh

It writes `dist/duckling_VERSION_ARCH.deb`, compressed with xz at its highest
level because three quarters of the contents are ONNX weights that barely
compress, and then prints what the executable links beside what the package
declares. The executable links libc, libgcc and libstdc++; the display
stack, the graphics driver loader and the keyboard map libraries are opened
by name at run time, so `Depends` is written by hand and `check-libraries.sh`
keeps it true.

One package, `duckling`. The models are arch-independent data in an
arch-dependent package, which Debian proper would split into `duckling-data`;
they sit under `/usr/lib/duckling` beside the executable that finds them
there, which is a private application directory and what the fleet's
one-package rule wants. The package carries no maintainer scripts:
`desktop-file-utils` and `hicolor-icon-theme` own the dpkg triggers on the
directories it writes into.

`copyright` is DEP-5 because the package carries three licences: Duckling's
MIT, the models' (Docling's MIT and PaddleOCR's Apache-2.0), and pdfium's
BSD. `.github/workflows/linux.yml` runs lintian at error and warning on
every push, with the three `embedded-library` tags on pdfium overridden in
`debian/lintian-overrides`, which says why.

## The icon

`linux/icons/duckling.svg`: a yellow duckling in the fleet's blue roundel,
so the three Excelano applications share a disc on a launcher and this one
is the colour a rubber duck is. David chose it on 2026-09-05 from a sheet
of three shapes and then three colours; the file's own comment records what
the others cost. Checked at 16,
32 and 128 pixels on light and dark grounds before committing, and any
change should be. The SVG is the source for every platform: macOS wants
`.icns` and Windows `.ico`, both converted from it, and slipcase-desktop's
`make-ico` is the converter for the second.

## windows, macos

Not here yet. Each is cloned from segler's directory of the same name by the
lane that can build and test it, and `RELEASE.md` says what each lane needs
to know before starting, which for Duckling is more than a rename.
