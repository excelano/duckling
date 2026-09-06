# Duckling — design

The reasoning behind the application, in the order the decisions were made,
each dated. `CLAUDE.md` is the short guide; this is the long one. `git log`
is the record of how each section came to say what it says.

## 1. What this repository is

A desktop application that converts documents with docling.rs. One crate,
`duckling`, with a library half (`src/lib.rs`: the queue, the worker, the
output rules) that knows nothing about a window, and a binary half
(`src/main.rs`: the window) that renders it. The application is presented
as **Duckling**. The name was reserved on the Microsoft Store on 2026-09-04
before the survey in `§3` found `duckling-ui/duckling`, a browser front-end
for the Python Docling, and David kept it: the reservation is his, and
Segler went through the same reasoning about a collision and kept its name.

The converter is `docling`, docling.rs, from crates.io at a published
version and never a path dependency in a committed manifest. Duckling adds no
conversion logic. Where a conversion is wrong, the issue goes upstream.

## 2. Dependencies

**docling.rs with the PDF pipeline, and what that costs.** Decided
2026-09-04. The fleet's preference is pure Rust; `~/notes/pure_rust_preference.md`
holds the stance, and this is the repository it was written for, because
this product depends on C. Without the `pdf` feature a PDF converts through
docling.rs's text-layer path: flat paragraphs in reading order, no headings,
no tables, nothing from a scanned page. The two Microsoft Store applications
Duckling competes with both run layout models, so a Duckling without them
would be the weaker product on the format people most want converted.

What the feature brings, measured on Linux on 2026-09-04: ONNX Runtime,
which `ort` fetches as a prebuilt static library at build time and links
into the executable; pdfium, a shared library loaded by name at run time;
and oniguruma, the regular-expression library under the HuggingFace
tokenizer that docling-pdf carries for its code and formula enrichment
models, which `onig_sys` compiles from C source with the system compiler.
So the build needs a C compiler on every lane, and the executable links
`libstdc++` beyond libc, libgcc and libm, which is ONNX Runtime's. The cost
of the first is trusting a download at build time rather than a build from
source, and it is the same download docling.rs's own binaries are built
from; the cost of the third is a compiler on the build machine for a
library this application never calls, since it ships no enrichment models.
Measured by `cargo tree -i onig_sys` and by the `.a` files under the build
directory; `ring`, which the shared build directory also held, is another
repository's and not in this tree.

**The models ship in the package.** Decided 2026-09-04 after the
alternatives were priced. The standard pipeline loads its models in tiers:
layout for any PDF or image, the OCR recognizer lazily on the first page
without a text layer, TableFormer on the first table. Three quarters of the
weight is TableFormer, and a design that bundled the rest and fetched
TableFormer on demand was drawn in full, with the prompt at the result row
and the reconversion after. David chose to bundle everything: the package is
larger than WhatsApp's and smaller than a game's, and the application then
has no download code, no failure state for one, no privacy line about
fetching, and works offline from the first launch. The model set is
docling.rs's own default, pinned by URL and SHA-256 in
`packaging/fetch-models.sh`, and the int8 and fp32 variants both ship
because the pipeline runs int8 first and retries a page on fp32 when int8
finds no text on it.

Measured 2026-09-04: `.models/` is 735 MB and `.pdfium/` 7 MB on Linux. The
files the pipeline opened converting a four-page digital PDF with tables are
recorded in `§7`; trimming to that set is available if a platform's package
size ever matters, and is not done now.

**What that costs on Windows is more than it costs on Linux, and it was
measured on 2026-09-05 rather than predicted.** Two of the three findings were
open questions in `RELEASE.md` and the third was not foreseen at all.

The first: **`+crt-static` cannot be used.** Every other application in the
fleet links the Visual C++ runtime into the executable, because that runtime is
not part of Windows and a binary that imports it installs on a clean machine and
will not start - which is how slipcase-desktop 0.1.1 failed Microsoft Store
policy 10.2.4.1. The prebuilt ONNX Runtime `ort` fetches for
`x86_64-pc-windows-msvc` was compiled against the dynamic CRT, so its objects
reach the C library through `__imp_` import thunks the static CRT does not
define, and the link fails with 63 unresolved externals - `strtoll`, `erff`,
`nearbyintf`, `fopen_s`. The alternatives were building ONNX Runtime from source
against the static CRT, which is a project of its own and a second thing
downloaded at build time replaced by a heavier one, and declaring the VCLibs
framework dependency, which the Store resolves but which leaves the side-loaded
route uncovered. David chose the third on 2026-09-05: **the runtime ships inside
the package**, four DLLs of 0.73 MB together, beside the executable where the
loader finds them first, exactly as pdfium already does. Slipcase's rejection
was for a DLL *outside* the package.

The second: **DirectML arrives whether it is wanted or not.** The Windows dist
`ort` selects is `ms@1.28.0/x86_64-pc-windows-msvc+directml`, so the DirectML
execution provider is linked in and `directml.dll` becomes a hard import,
although docling.rs runs the CPU provider and this application never selects
another. In-box DirectML began at Windows 10 10.0.18362 and the package declares
a floor of 10.0.17763, and the copy on the lane machine is 1.0.200713 against
the 1.15.4 that pyke ships beside the library actually linked. So the dist's own
copy ships too, 18.5 MB, which pairs the library with the DLL it was built
against. That it is linked at all is cost for nothing, and `§9` carries it as a
thread to take upstream.

The third is not a finding but what the first two do to the paragraph above.
The C in this application was ONNX Runtime, pdfium and oniguruma; on Windows it
is those three **and DirectML**, and the executable needs five DLLs beside it
rather than none. `packaging/windows/README.md` holds every measurement and
`packaging/windows/check-imports.ps1` is the guard that keeps the list at five
and refuses a sixth. `CLAUDE.md` says a third C dependency is a decision to take
with David; this is the fourth arriving inside the first, which is not the shape
that rule anticipated, and taking it was still David's on 2026-09-05.

**What it costs on macOS is a whole architecture, and that was measured on
2026-09-05 on the Mac lane rather than predicted.** `RELEASE.md` sent the lane
to build the universal binary slipcase-desktop ships. It cannot be built from
any machine: `ort`'s dist list for macOS carries only `aarch64-apple-darwin`,
and Microsoft's own releases, which those builds are made from, stopped
shipping an Intel or a universal macOS library at 1.28.0, the version `ort`
pins. Building ONNX Runtime from source for x86_64 is the same project of its
own the Windows lane declined. So **the Mac App Store build is Apple silicon
only**, and App Store Connect lists it that way from the binary. Apple sold its
last Intel Mac in 2023 and has named macOS 26 the last release for them, so
this is where every Mac application is going; this one arrives first for want
of a library rather than by choice. The cost that bites is that David's Mac is
Intel: the lane cross-compiles and packages a build it can never run, so
`.github/workflows/macos.yml` on an arm64 runner is where the shipped
architecture first converts anything, and a person's walkthrough needs a
borrowed machine or TestFlight. An `intel-mac` feature in `Cargo.toml` builds
the application with no ONNX Runtime in it, for measuring the window, the
sandbox and the bundle on the machine at hand; PDFs and images fail in their
rows and everything else converts. `packaging/macos/README.md` §1 has every
measurement. Two smaller costs came with it: the floor is macOS 13.4, because
that is what the library `ort` fetches was built for; and CoreML is linked in
unasked, the DirectML story again at a fraction of the size, carried in `§9`
under the same thread.

**The framework is egui, through eframe**, the same as slipcase-desktop and
segler, so that one set of platform lessons serves three applications and
the packaging clones. The Linux system-theme module is slipcase-desktop's,
copied unchanged apart from its header. `rfd` for dialogs with its defaults,
whose `gtk3` feature stays off. `opener` with `reveal`, for showing a
converted file in the file manager.

**Not taken.** docling.rs's `asr` feature wants Whisper models that are
another 150 MB for a use, transcribing audio, that this application does not
claim. `vlm` wants a remote endpoint. `fetch-images` wants the network for
HTML images. `chunking` is a RAG concern. Each is a feature flag away if a
release wants it, and each is a listing claim to make on purpose.

## 3. The product, and the survey that preceded it

Surveyed 2026-09-04 before anything was built, because a name reserved on a
store is not a reason to ship into a space somebody else already fills. No
application on the Microsoft Store or the Mac App Store is built on Docling,
and nothing anywhere is built on docling.rs. The Microsoft Store has Md Forge
(free, 213 MB, released June 2026, engine unstated), a Marker wrapper called
PDF to Markdown last updated in 2024, and a pandoc wrapper. GitHub has nine
Docling GUIs, every one a Python script needing a virtual environment, the
best at five stars, and five MarkItDown GUIs of the same shape, the best at
129 stars. The Mac App Store has nothing that converts Office or PDF to
Markdown at all.

So the product is the thing none of those are: a native application that
installs from a store, weighs what its models weigh and nothing more, works
offline from the first launch, reads the forty-odd formats docling.rs reads
including the ones nothing else touches (Visio, iWork, RTF, the binary
Office formats, email, Lotus), and writes more than Markdown. The DocLang
archive output makes it Segler's sibling: convert with Duckling, review and
correct with Segler.

## 4. Shape

One window, four regions, settled with the first build on 2026-09-04.

The **toolbar** says what the next Convert will do: the output format, and
whether output goes beside each source or into one folder. Nothing converts
until Convert is pressed, so the choices apply to a whole batch and a person
can change their mind after queuing. A folder destination is chosen once and
remembered, so switching away and back does not ask again.

The **queue** is the batch: file, the format docling.rs took it for from its
extension, and its state. Files arrive from the command line, from drops on
the window, or from the two Add buttons. A dropped folder contributes every
file under it that docling.rs reads, in name order, files before
subfolders, and says nothing about the files it does not read, because a
folder drop is a request for what can be converted. A single dropped file
that cannot be read is reported in the status line by extension, because
that person asked about that file. A file already queued or converting is
not queued twice; a finished one is, since asking again is how a person
converts into a second format.

The **preview** shows the selected job: the output path with Open and Show
in folder, and the written text in a read-only monospace editor capped at
256 KB with a line saying so when the file is longer. A DocLang archive is a
zip, so its preview is the `document.xml` inside.

**Five outputs, and DocLang is the default.** Decided 2026-09-04 after the
first build offered four with the archive as the only DocLang form, because
that is all the docling.rs command-line tool offers. The library writes the
bare markup, the archive is that markup plus two fixed OPC parts, and Segler
opens both, so bare DocLang, `.dclg`, is the first entry and the default:
it is the format the two applications share, and it is the smaller and
more readable of the two spellings. The archive stays for whatever
downstream wants the packaged form.

**The archive carries page images and the pictures, and bare DocLang gets
its pictures beside it.** Decided 2026-09-05; David: "Yes, I want the
images." The specification's archive is `document.xml` plus optional
`pages/N.png` and `assets/`, and Segler shows the page images beside the
document. docling.rs's archive writer emits the markup alone, but its
markup already names each image-bearing picture as
`assets/image_NNNNNN_<sha256>.png`, and its page renderer and zip packer
are public. So `src/doclang.rs` does three things the engine leaves to the
caller. It pairs every asset name in the markup with the picture bytes
whose hash it carries, re-encoded to PNG because the name says so. For an
archive it renders a PDF's pages through pdfium at the pipeline's own
scale, or takes an image input as its one page, and packs the two fixed
OPC parts, the markup, the pages and the assets, dropping any page past the
last segment. For a bare `.dclg` it writes the assets into `assets/` beside
the file, content-addressed, so an existing file of the same name holds the
same bytes. A page render that fails is a note on the result, not a failed
conversion.

**docling.rs writes no page breaks for a PDF, and Duckling inserts them.**
Measured 2026-09-05 on `normal_4pages.pdf`: docling.rs's markup carries
four `PageInfo` nodes and no `<page_break/>`, where the reference archive
in its own corpus carries three. The specification ties page images to
segments split on breaks, so without them an archive may carry one page.
Before either DocLang output, Duckling puts a break before every page after
the first when the converter marked pages and wrote no breaks; the
spreadsheet, slide and RTF backends write their own and are left alone.
This is a conformance gap in docling.rs against its own reference, not
raised upstream yet; David decides. A second one surfaced the same way:
docling.rs writes a table's `<caption>` before its four `<location>`s,
the specification's head order puts location first, and Segler's
validator says so on every captioned table from a PDF. Duckling passes
the markup through as the engine writes it; a converter that rewrote the
engine's output would be hiding what upstream needs to hear. A conversion docling.rs
reports as partial says so beside the buttons.

The **status line** counts the queue by state and carries the last thing that
happened.

**Conversion happens on one worker thread**, which owns the converter and a
warm PDF pipeline, so the models load once per session rather than once per
file. The window and the worker speak through two channels: requests one way,
events (started, page progress, finished) the other, and the worker wakes the
window after each event so that a repaint costs nothing while nothing
happens. A backend that panics on a malformed file fails that job and
rebuilds the engine; it does not take the window down. Moving the worker into
a child process, should crash isolation from pdfium or ONNX Runtime ever
prove necessary, is a change at that boundary and nowhere else.

## 5. Writing output

**Never overwrite.** A converter that writes beside its source is one
extension away from replacing a person's file: Markdown converted to
Markdown targets its own source, and a `report.md` already beside
`report.pdf` is somebody's work. The rule is a browser download's: the first
free name among `report.md`, `report (1).md`, `report (2).md`. It is tested,
including the Markdown-to-Markdown case, and nothing writes around it.

**Write beside, then rename.** A crash mid-write leaves a `.part` file and
never a half file under the final name.

## 6. States to design, not to crash on

A file with no extension, or one docling.rs does not read: rejected at
queueing, by extension, in the status line. A file that cannot be read:
failed, with the error. A PDF when pdfium or a model is missing beside the
executable, which a packaged build never is: failed, with docling.rs's own
message naming the file it wanted. A backend panic: failed, with the panic's
text. A conversion docling.rs marks partial: done, marked. A file longer
than the preview cap: previewed to the cap, marked.

## 7. Walkthroughs

**First, 2026-09-04, at the keyboard under XWayland on Linux.** Six files in
a folder with a subfolder and a stray `.exe`: a workbook, a Word file with
tables, a Markdown file, a four-page Korean PDF, a slide deck, and a scanned
PDF. All six converted; the `.exe` was skipped without comment; the Markdown
file became `notes (1).md` beside its untouched source; the scanned page
came back as its sentence through OCR; the Korean PDF came back with its
headings. Two things found. The folder walk yielded files in reverse name
order, from iterating a reversed list; fixed and tested the same hour. And
the preview drew every Korean character as a box, because egui ships Latin
fonts only. The file on disk is right; the preview is not, for any script
outside Latin, Greek and Cyrillic. Open thread below.

What the pipeline opens, read from docling.rs 1.36's source rather than
traced, since `strace` is not on this machine: the layout model is
`layout_heron_int8.onnx` first and `layout_heron.onnx` only as the retry for
a page int8 found no text on; the English OCR pair `ocr_rec_en.onnx` and
`en_dict.txt` by default, the `ocr_rec.onnx` pair only when the language is
set to Chinese; TableFormer's `encoder.onnx`, `bbox.onnx` with its data
file, and for the decoder the first present of `decoder_kv_int8` (not
hosted), `decoder_kv` (hosted, so this one), `decoder_int8`, `decoder`. So
`decoder_int8.onnx` and `decoder.onnx` with its data file, about 120 MB
together, ship as fallbacks that a package built from this script never
reaches. Trimming them is the first cut if size ever matters.

## 8. Packaging

Cloned from `excelano/segler`, which cloned it from `excelano/slipcase-desktop`,
one directory per platform, with what is Duckling's own stated here and in
`RELEASE.md`.

**The models and pdfium sit beside the executable, and the executable finds
them there.** docling.rs looks under the working directory, then under two
environment variables, then beside the executable under the dotted names
`.models/` and `.pdfium/`. A package cannot use dotted names in an
application directory, so `locate_assets` in `src/lib.rs` runs once at
startup, before any thread exists, and names `models/` and `pdfium/` beside
the canonicalized executable through the two variables when they are there.
A checkout with `.models/` in its working directory is left alone, and so is
an environment somebody set by hand. On Linux the layout is
`/usr/lib/duckling/{duckling,models,pdfium}` with `/usr/bin/duckling` a
symlink, which is the layout docling.rs's own installer produces; the
Windows lane puts the same two directories beside its executable, and the Mac
lane could not, for the reason below.

**One package, and the models are in it.** Debian proper would split 740 MB
of arch-independent data into `duckling-data`; the fleet's rule is one
package for one product, and `/usr/lib/duckling` is a private application
directory where that data may live. The `.deb` is compressed with xz at its
highest level, which costs minutes and saves little, because ONNX weights
barely compress. Whether the Excelano apt host serves a file that size is
measured on the first release, and `RELEASE.md` says what happens if it does
not.

**Three lintian overrides, the fleet's first.** pdfium is a prebuilt
monolith with FreeType, Little CMS and OpenJPEG compiled in, and lintian
says so as three errors. Debian has no pdfium to depend on and building one
against the system libraries is a project of its own, so
`packaging/debian/lintian-overrides` records the three with the reason and
the package passes at error and warning. slipcase-desktop and segler carry
no overrides; this one is a decision taken on 2026-09-04, and the file says
so.

**No media type of its own.** Duckling owns no format. The desktop entry
lists fifteen of the types it reads, so a file manager offers it under Open
With for a PDF or a Word file without making it the default for either.

**The Windows lane, run 2026-09-05.** What was recorded here as unsolved is
solved, and two of the three answers were not the expected ones. `+crt-static`
cannot be used and four Visual C++ runtime DLLs ship in the package instead;
DirectML is linked in unasked and its own DLL ships too; `pdfium.dll` is loaded
by name and never appears in the import table, so the import check passes as
written, which was the one prediction that held. `§2` has the reasoning and
`packaging/windows/README.md` has every measurement.

The package is 605 MB packed from 821 MB staged, and `models/` and `pdfium/`
sit beside `duckling.exe` in the application directory, which is the layout
`locate_assets` already wanted. Installed from that package and launched from
the apps folder, a PDF converted: layout ran, headings and picture regions came
back, bare DocLang was written with its `assets/` beside it.

**Duckling claims no file type on Windows either, and both install routes were
measured saying so.** The MSIX declares one `uap:FileTypeAssociation` over
seventeen extensions - the fifteen media types the desktop entry lists, with
`.htm` and `.markdown` as second spellings - with no `DisplayName` and no
`Logo`, because every one of those types is somebody else's to name and to
draw. The side-loaded scripts write `Applications\duckling.exe` with
`SupportedTypes` and an `OpenWithList` entry per extension. Neither writes an
extension's default value, and neither can: a packaged association only ever
joins `OpenWithProgids`. So a person gets Duckling under Open With for a PDF and
keeps whatever opens their PDFs, which is what the desktop entry asks a file
manager for. It also means `uninstall.ps1` must not remove a `UserChoice` the
way segler's does - segler claims its two types and Duckling claims none, so
that key is always somebody else's decision.

**The Mac lane, run 2026-09-05, on an Intel Mac that cannot run what it
built.** Cloned from slipcase-desktop's directory of the same name, which has
been through Mac App Store review and a rejection under Guideline 2.5.1; the
winit pin that rejection produced is in `Cargo.toml` and the private-symbol
check it produced is in `build-app.sh`, which found the two `CGS` symbols
without the pin and nothing with it. `§2` has the finding that shaped the
lane, and three more are recorded here because each is a decision.

**The models are resources and pdfium is a framework.** A bundle is not a
directory the package may fill beside the executable: `codesign` treats
everything under `Contents/MacOS` as code, and a shared library the Store
accepts is nested code under `Contents/Frameworks`. So the layout is
`Contents/Resources/models`, `Contents/Frameworks/libpdfium.dylib` thinned to
the executable's architecture, and `locate_assets` looks there after looking
beside. Measured: 805 MB of bundle, 594 MB of package.

**The sandbox grants a file, not its folder, and the application asks for the
folder.** slipcase-desktop measured that the open panel's grant covers the
file and not its directory, and Duckling's default writes beside its input.
So a single dropped PDF converted beside itself would have failed at the
write, after the models had run. `can_write_in` in `src/lib.rs` probes each
queued file's folder with one empty entry, and for each that refuses,
`src/main.rs` puts up the standard open panel at that folder with a message
saying why; choosing it extends the grant for the session, which is the panel's
purpose under the sandbox. Files whose folder is still refused stay queued and
the status line says so, naming *Into a folder* as the other way out. A
dropped or picked folder is granted whole and never sees the panel, and
neither does a chosen destination. Measured 2026-09-05 on the `intel-mac` build
signed with an Apple Development identity: the panel appears, choosing the
folder makes the write succeed, cancelling leaves the file queued, and a file
given as a command-line argument cannot even be read - *Operation not
permitted* - which is the sandbox working as designed and a route no person
takes. macOS only; on the other two platforms a folder that refuses a write is
a permissions problem a panel would misdescribe. Taken on the lane without
David because the alternative was a Store build whose first drop fails, and
reversible in one function.

**No document types on this platform, so no Open With.** The desktop entry and
the MSIX association list the types Duckling reads at Alternate rank, and the
bundle's counterpart would be `CFBundleDocumentTypes` at the same rank. It is
not declared, because an opened document reaches a Mac application as an Apple
Event rather than an argument, receiving one is the `unsafe` module
slipcase-desktop carries, and `CLAUDE.md` makes that a decision to take with
David. Declaring the types without the handler would have Finder offer
Duckling and AppKit refuse the document with a dialog blaming it. So neither,
and the changelog's Open With claim stays scoped to Windows. `§9`.

## 9. Open threads

**The preview has no font for most of the world's scripts.** egui bundles
Latin, Greek and Cyrillic. A converted Korean, Arabic, Hindi or Japanese
document previews as boxes while the file is right. The fix is a font with
coverage, either shipped (Noto Sans CJK is tens of megabytes per script) or
found on the system at start (every platform has one, under different names
and paths). Decide from use; the file being right is what matters first.

**Whether Convert should be the only trigger.** A person who drops one file
and wants Markdown beside it presses one more button than they might expect.
The batch argument in `§4` is why it is there; the first hands-on use by
somebody who is not David is where the question gets answered.

**Trimming the model set.** `§2` ships docling.rs's default set. If a
platform's package size ever matters, `§7` records what a conversion
actually opened.

**Open With on macOS.** `§8` says why the bundle declares no document types:
the Apple Event handler that would receive the document is an `unsafe` module,
slipcase-desktop's `src/opened_document.rs`, and adding one here is David's
call. The cost of taking it is that module with its header changed,
`deny(unsafe_code)` lifted for the one file, the `objc2` features it needs,
and a list of types in `Info.plist.in`; the gain is the right-click route a
Linux or Windows file manager already offers. Drops, the Add buttons and the
Dock work without it.

**Intel Macs.** `§2` records that no prebuilt ONNX Runtime exists for
`x86_64-apple-darwin` at pyke or at Microsoft since 1.28. If either ships one
again, or if a build from source is ever worth its weight, `build-app.sh`
gains back the `--universal` its parent has and `Info.plist.in` says nothing
about architecture, which it already does not. Until then the Store lists the
application for Apple silicon and David's own Mac runs the `intel-mac` build.

**DirectML is linked into the Windows build for nothing, and upstream should
hear it - and CoreML into the Mac build.** Found 2026-09-05 on the Windows lane and recorded in `§2`: the
prebuilt ONNX Runtime `ort` selects for this target carries the DirectML
execution provider, so `directml.dll` is a hard import and 18.5 MB of DLL ships
in the package, while docling.rs runs the CPU provider and this application
never selects another. The Mac lane found the same shape on 2026-09-05: the
one dist `ort` offers for Apple silicon is `+coreml`, so `CoreML.framework` is
imported and the provider's objects are in the executable for nothing. The
question is `ort`'s or docling.rs's rather than this repository's - whether a
dist without either can be asked for - and it is the same shape as the two
docling.rs conformance findings in `§4`: measured here, not worked around
here, and David decides when it goes.
