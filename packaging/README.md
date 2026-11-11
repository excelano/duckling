# Packaging

How Duckling is built into what each platform installs. Releases are the apps
in `excelano/shipping`, run from the repository root with `ship.toml`; this
directory is what they build from. `DESIGN.md` §8 has the reasoning behind each
package's shape.

| Path | What it is |
|---|---|
| `fetch-models.sh` | Puts the pinned models under `.models/` at the repository root, which every package copies from |
| `version.sh` | The version in the spellings the platforms want; the only reader of `Cargo.toml`'s |
| `icons/` | The icon square and rounded, with PNG exports for submission forms |
| `linux/` | The desktop entry, the icon, the per-user install, and `check-libraries.sh` |
| `debian/` | `build-deb.sh`, the control file, the changelog, the copyright file and the manual page |
| `windows/` | The MSIX, the side-loaded install and their checks; its README has the lane |
| `macos/` | The bundle and the Store package; its README has the lane |
| `demo/` | The documents the store screenshots show, and the script that writes them |
| `store-listing.toml`, `release-notes.toml` | What the stores show, and what a release tells them changed |
| `submission-notes.md` | What a submission form asks that no file answers |
| `privacy-entry.html` | The section for the privacy page at excelano.com/legal |

## What every package carries

The executable, and beside it `models/`, the PDF and image pipeline. The
application finds them by looking beside its own executable
(`locate_assets` in `src/lib.rs`), so every platform's package puts them where
it looks: `/usr/lib/duckling/` on Linux with a symlink on `PATH`, the
application directory in an MSIX, and in a bundle `Contents/Resources/models`,
the second place `locate_assets` looks. There is no download at run time and no
code for one.

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
a file and presses nothing, so the models stay unloaded: those are the
package's own files and not a `Depends` question.

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
two licenses: Duckling's MIT and the models' (Docling's MIT and PaddleOCR's
Apache-2.0). lintian runs at error and warning on the built package.

## The icon

`linux/icons/duckling.svg` is the source for every platform: a yellow duckling
on the fleet's blue square, full bleed and unframed, because a store applies
its own corner rounding and a drawing carrying a smaller shape or an outline
into that frame reads as a sticker. Check any change at 16, 32 and 128 pixels
on light and dark grounds. `macos/build-app.sh` renders the `.icns` from it
with `sips` at build time; `windows/make-ico` writes the `.ico`, the four PNGs
the MSIX manifest names and the Store listing logo, which are committed
artifacts, so run it again after any change to the drawing.

`icons/` holds the icon in two shapes, `duckling-square` and
`duckling-rounded`, each as an SVG and as PNGs at 256, 512, 1024, 1080 and
2160, for whichever a submission form wants: a store that masks what it is
given (the iOS and iPadOS Store, Icon Composer) wants the square, and a form
that draws what it is handed wants the rounded one, as does the Linux desktop,
which is why `linux/icons/duckling.svg` is the rounded shape. `windows/make-ico` writes
the directory and clips the rounded shape from the same source; neither is
edited by hand. The corner is 22.37% of the side drawn as a circular arc, which
does not tell apart from Apple's continuous curve below about 512 pixels.
Nothing in `icons/` ships: the deb installs named files out of `linux/icons`,
`build-msix.ps1` copies `windows/assets/*.png`, and no code reads one at run
time.
