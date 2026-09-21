# Duckling design

What is true of the application, section by section. `CLAUDE.md` is the short
guide; this is the long one.

## 1. What this repository is

A desktop application that converts documents with docling.rs. One crate,
`duckling`, with a library half (`src/lib.rs`: the queue, the worker, the
output rules) that knows nothing about a window, and a binary half
(`src/main.rs`: the window) that renders it. The application is presented as
**Duckling**.

The converter is `docling`, docling.rs, from crates.io at a published version
and never a path dependency in a committed manifest; the office writer is
`waddle-core`, the same way. Duckling adds no conversion logic. It composes the
two, and where a conversion is wrong the issue goes to whichever of them it
belongs to.

## 2. Dependencies

**docling.rs with the PDF pipeline.** The fleet's preference is pure Rust;
`~/notes/pure_rust_preference.md` holds the stance, and this is the repository
it was written for, because this product depends on C. Without the `pdf`
feature a PDF converts through docling.rs's text-layer path: flat paragraphs in
reading order, no headings, no tables, nothing from a scanned page. The feature
brings three C dependencies: ONNX Runtime, which `ort` fetches as a prebuilt
static library at build time and links into the executable; pdfium, a shared
library loaded by name at run time; and oniguruma, under the tokenizer
docling-pdf carries for enrichment models this application never runs, which
`onig_sys` compiles from C source. So the build needs a C compiler on every
lane, and the executable links `libstdc++` beyond libc, libgcc and libm.

**The models ship in the package.** The set is the one docling.rs resolves at
run time, pinned by URL and SHA-256 in `packaging/fetch-models.sh`, so the
application has no download code, no failure state for one, no privacy line
about fetching, and works offline from the first launch. The URL is a dated
release on this repository and not upstream's, because upstream publishes its
models to one tag it overwrites: a hash pinned against a moving reference
breaks on somebody else's schedule, and a build cache hides the change until
the day it does not. Taking a new upstream set is a new dated release, new
hashes, and a look at what the change does to conversion quality.

**The layout model ships int8 alone.** The fp32 file is loaded only by
`predict_fp32_fallback`, which re-runs a page whose int8 detections cover less
than half its text cells, and without it that call returns `Ok(None)` and the
page keeps the int8 result, which docling.rs supports. It is not shipped
because it is 172 MB for a guard that did not fire once over the 2,018 pages
of docling.rs's PDF corpus. The exposure this accepts is that the guard is
written for a class of machine rather than a class of page — docling-pdf's own
comment has a different processor's quantized kernels flipping a whole page's
detections — so a count taken here cannot speak for a processor this one
cannot reproduce, and a report of collapsed layout on a machine that is
otherwise fine is what puts the file back.

**TableFormer ships the decoder the pipeline resolves and the encoder that
resolves everywhere.** The decoder is `decoder_kv.onnx`, first candidate
upstream hosts, and nothing behind it in that preference order. The encoder is
the fp32 file rather than the fp16 repack docling-pdf ranks ahead of it on the
CPU path, because `prefer_fp32()` drops fp16 from the candidates entirely: a
build that ever compiles in a GPU execution provider would resolve to a file
no package carries and lose ML table structure behind one stderr note, which
is a silent loss rather than a broken build. That costs 54 MB, and the two
produce byte-identical output over the whole corpus, so the fp32 file buys the
configuration and not the conversion. `tests/convert.rs` asks docling.rs's `model_inventory`
which file each stage resolved to and names the file each must be, so a
release that reordered a preference, promoted a candidate above the shipped
file, or withdrew an export fails the test before it fails a conversion.

**On Windows, `+crt-static` cannot be used and five DLLs ship in the package.**
The prebuilt ONNX Runtime `ort` fetches for `x86_64-pc-windows-msvc` is
compiled against the dynamic CRT, so the link against the static one fails;
the four Visual C++ runtime DLLs ship beside the executable instead, where the
loader finds them first, as pdfium already does. The same dist carries the
DirectML execution provider, so `directml.dll` is a hard import although
docling.rs runs the CPU provider, and the dist's own copy ships as the fifth.
The C in this application is therefore ONNX Runtime, pdfium and oniguruma, and
on Windows DirectML as well; `packaging/windows/check-imports.ps1` keeps the
shipped list at five and refuses a sixth. `packaging/windows/README.md` has the
lane.

**On macOS the build is Apple silicon only.** No prebuilt ONNX Runtime exists
for `x86_64-apple-darwin`, at `ort` or at Microsoft since the version `ort`
pins, and building one from source is a project of its own; App Store Connect
lists the application for Apple silicon from the binary. The Mac the lane runs
on is Intel, so `.github/workflows/macos.yml` on an arm64 runner is where the
shipped architecture converts anything, and the `intel-mac` feature in
`Cargo.toml` builds the application with no ONNX Runtime in it for measuring
the window, the sandbox and the bundle on that machine. The floor is macOS
13.4, the library's. CoreML is linked in unasked, the DirectML shape again at
a fraction of the size. `packaging/macos/README.md` has the lane.

**The framework is egui, through eframe**, the same as slipcase-desktop and
segler, so that one set of platform lessons serves three applications and the
packaging clones. The Linux system-theme module is slipcase-desktop's. `rfd`
for dialogs with its defaults, whose `gtk3` feature stays off. `opener` with
`reveal`, for showing a converted file in the file manager.

**docling.rs features that stay off.** `asr` wants Whisper models for a use,
transcribing audio, that this application does not claim; `vlm` wants a remote
endpoint; `fetch-images` wants the network for HTML images; `chunking` is a
RAG concern. Each is a feature flag away, and each is a listing claim to make
on purpose.

## 3. The product

A native application that installs from a store, weighs what its models weigh
and nothing more, works offline from the first launch, reads the forty-odd
formats docling.rs reads including the ones nothing else touches (Visio,
iWork, RTF, the binary Office formats, email, Lotus), and writes more than
Markdown. The DocLang output makes it Segler's sibling: convert with Duckling,
review and correct with Segler.

## 4. Shape

One window, four regions. The **toolbar** says what the next Convert will do:
the output format, whether output goes beside each source or into one folder,
and whether a PDF is read from its text layer only. Nothing converts until
Convert is pressed, so the choices apply to a whole batch and a person can
change their mind after queuing. A folder destination is chosen once and
remembered. The **queue** is the batch: file, the format docling.rs took it
for from its extension, and its state. Files arrive from the command line,
from drops on the window, or from the two Add buttons. A dropped folder
contributes every file under it that docling.rs reads, in name order, files
before subfolders, and says nothing about the files it does not read, because
a folder drop is a request for what can be converted; a single dropped file
that cannot be read is reported in the status line by extension, because that
person asked about that file. A file already queued or converting is not
queued twice; a finished one is, since asking again is how a person converts
into a second format. The **preview** shows the selected job: the output path
with Open and Show in folder, and the written text in a read-only monospace
editor capped at 256 KB with a line saying so when the file is longer. A
DocLang archive previews as the `document.xml` inside it and an office package
as the document rendered to Markdown, since a person cannot read a zip. The
**status line** counts the queue by state and carries the last thing that
happened.

**Ten outputs, and DocLang is the default.** The library writes the bare
markup, the archive is that markup plus two fixed OPC parts, and Segler opens
both, so bare DocLang, `.dclg`, is the first entry and the default: it is the
format the two applications share, and the smaller and more readable of the
two spellings. Three of the ten are offered only for the input they are a
sibling of: ODS when every file in the queue is XLSX, XLSX when every file is
ODS, ODP when every file is PPTX, because the three write one sheet per table
or one slide per level-1 heading and a book converted to XLSX is an empty
sheet. The rule is `common_input` and `OutputFormat::offered_for` in
`src/lib.rs`, an affordance in the picker rather than a check in the engine,
so the tests can ask for pairings the window would not offer; when the queue
stops warranting the selected format the picker falls back to the default and
the status line says why, checked once a frame before anything is drawn. The
slide leg is one-way: waddle writes ODP and no PPTX.

**The archive carries page images and the pictures, and bare DocLang gets its
pictures beside it.** The specification's archive is `document.xml` plus
optional `pages/N.png` and `assets/`, and Segler shows the page images beside
the document. docling.rs's archive writer emits the markup alone, but the
markup names each image-bearing picture as `assets/image_NNNNNN_<sha256>.png`,
and its page renderer and zip packer are public. So `src/doclang.rs` pairs
every asset name with the picture bytes whose hash it carries, re-encoded to
PNG because the name says so; for an archive it renders a PDF's pages through
pdfium at the pipeline's own scale, or takes an image input as its one page,
and packs the OPC parts, the markup, the pages and the assets; for a bare
`.dclg` it writes the assets into `assets/` beside the file,
content-addressed. A page render that fails is a note on the result.

**The office packages come from waddle.** docling.rs writes no office format;
`waddle-core` takes the `DoclingDocument` the engine produced and returns an
OpenDocument or OOXML package that docling.rs's own reader for that format
reads back, as far as the reader allows. The output is plain by design: the
model carries no styles, page geometry or fonts. The pictures go into the
package rather than beside the file, because the document the engine holds
already carries them. What the package cannot hold, waddle reports and
Duckling shows as notes on the result, one line per kind with a count.

**One pipeline option reaches the window: text layer only.** Every other knob
docling.rs offers stays where it is, because a window with a preferences panel
is a different application from this one. This one earns a checkbox because
the cost it removes is measured in minutes: a long digital PDF takes minutes
through the models and seconds off its text layer. It is framed as speed and
not as accuracy, and what it gives up is headings, tables and any page that
needs OCR. `no_ocr` is a builder rather than a setter, so the engine rebuilds
its pipeline when the mode changes; a text-only pipeline loads no model, so
switching to it is free and switching back pays the load once. A file with no
text layer reads as nothing in this mode, which is correct and looks like a
failure, so the result carries a note saying which it is.

**docling.rs writes no page breaks for a PDF, and Duckling inserts them.** Its
markup for a PDF carries `PageInfo` nodes and no `<page_break/>`, where the
reference archive in its own corpus carries one per page boundary, and the
specification ties page images to segments split on breaks. So before either
DocLang output Duckling puts a break before every page after the first when
the converter marked pages and wrote no breaks; the spreadsheet, slide and RTF
backends write their own and are left alone. Otherwise Duckling passes the
markup through as the engine writes it; a converter that rewrote the engine's
output would be hiding what upstream needs to hear. A conversion docling.rs
reports as partial says so beside the buttons.

**Conversion happens on one worker thread**, which owns the converter and a
warm PDF pipeline, so the models load once per session. The window and the
worker speak through two channels, requests one way and events the other, and
the worker wakes the window after each event so that a repaint costs nothing
while nothing happens. A backend that panics on a malformed file fails that
job and rebuilds the engine; it does not take the window down. Moving the
worker into a child process, should crash isolation ever prove necessary, is
a change at that boundary and nowhere else.

## 5. Writing output

**Never overwrite.** A converter that writes beside its source is one
extension away from replacing a person's file: Markdown converted to Markdown
targets its own source, and a `report.md` already beside `report.pdf` is
somebody's work. The rule is a browser download's: the first free name among
`report.md`, `report (1).md`, `report (2).md`. It is tested, including the
Markdown-to-Markdown case, and nothing writes around it. **Write beside, then
rename.** A crash mid-write leaves a `.part` file and never a half file under
the final name.

## 6. States to design, not to crash on

A file with no extension, or one docling.rs does not read: rejected at
queueing, by extension, in the status line. A file that cannot be read:
failed, with the error. A PDF when pdfium or a model is missing beside the
executable, which a packaged build never is: failed, with docling.rs's own
message naming the file it wanted. A backend panic: failed, with the panic's
text. A conversion docling.rs marks partial: done, marked. A file longer than
the preview cap: previewed to the cap, marked.

## 7. Walkthroughs

Every slice that touches the window gets a walkthrough at the keyboard,
against the packaged application. A
screenshot from a lane proves that a code path draws and nothing more.

## 8. Packaging

One directory per platform under `packaging/`, cloned from `excelano/segler`,
which cloned it from `excelano/slipcase-desktop`; `packaging/README.md` says
what is there and each platform's README has its lane.

**The models and pdfium sit beside the executable, and the executable finds
them there.** docling.rs looks under the working directory, then under two
environment variables, then beside the executable under the dotted names
`.models/` and `.pdfium/`. A package cannot use dotted names in an application
directory, so `locate_assets` in `src/lib.rs` runs once at startup, before any
thread exists, and names `models/` and `pdfium/` beside the canonicalized
executable through the two variables when they are there, or a bundle's
`Contents/Resources/models` and `Contents/Frameworks`, the two places a signed
bundle allows. A checkout with `.models/` in its working directory is left
alone, and so is an environment somebody set by hand.

**One package, and the models are in it.** Debian proper would split the
arch-independent data into `duckling-data`; the fleet's rule is one package
for one product, and `/usr/lib/duckling` is a private application directory
where that data may live. pdfium is a prebuilt monolith with FreeType, Little
CMS and OpenJPEG compiled in, Debian has no pdfium to depend on, and building
one against the system libraries is a project of its own, so
`packaging/debian/lintian-overrides` records the three `embedded-library`
errors with the reason.

**Duckling claims no file type, on any platform.** It owns no format. The
desktop entry lists fifteen of the types it reads and the MSIX one association
over the same types, each with no display name and no logo because every one
of them is somebody else's to name and to draw, so a file manager offers
Duckling under Open With for a PDF without making it the default. Nothing on
Windows writes an extension's default value, and `uninstall.ps1` never removes
a `UserChoice`: that key is always somebody else's decision. The bundle
declares no `CFBundleDocumentTypes` at all, because an opened document reaches
a Mac application as an Apple Event rather than an argument, receiving one is
the `unsafe` module slipcase-desktop carries, and `CLAUDE.md` makes that a
decision to take with David; declaring the types without the handler would
have Finder offer Duckling and AppKit refuse the document. So there is no Open
With on macOS, and the listing's Open With claim is scoped to Windows.

**The sandbox grants a file, not its folder, and the application asks for the
folder.** The open panel's grant covers the file and not its directory, and
Duckling's default writes beside its input, so a single dropped PDF converted
beside itself would fail at the write, after the models had run.
`can_write_in` in `src/lib.rs` probes each queued file's folder with one empty
entry, and for each that refuses, `src/main.rs` puts up the standard open
panel at that folder with a message saying why; choosing it extends the grant
for the session, which is the panel's purpose under the sandbox. Files whose
folder is still refused stay queued and the status line says so, naming *Into
a folder* as the other way out. A dropped or picked folder is granted whole
and never sees the panel, and neither does a chosen destination. macOS only;
elsewhere a folder that refuses a write is a permissions problem a panel would
misdescribe.

**The Mac bundle carries slipcase-desktop's review lessons.** The winit pin in
`Cargo.toml` keeps a private CoreGraphics symbol that review refuses under
Guideline 2.5.1 out of the executable, and the private-symbol check in
`build-app.sh` refuses a binary that imports any symbol a framework's public
headers do not declare.

## 9. The language a person reads

German where the desktop asks for German, English everywhere else, through
the `potext` crate and the catalogues in `po/`. `po/update-po.sh` is the only
way they move and `po/pseudo.sh` writes the pseudolocale that finds a string
which never went through `t`. **A message is looked up by its English text,
never by a key**, so a call site reads as the sentence a person sees and an
untranslated one is the original rather than a placeholder. **A translation
that has gone stale is not shown:** `msgmerge` marks a reworded message
`#, fuzzy`, `potext` refuses to load one, and the window falls back to
English until somebody has read the new sentence.

**The catalogue is declared in `src/main.rs` and not in `src/lib.rs`**, which
is §4's rule about the interface being a renderer holding for language too:
every sentence a person reads is produced in the window, and the library says
nothing to anybody. A second front end would translate its own words rather
than inherit these.

**What the file says stays as the file says it.** The format a row was read as
is `detect`'s answer and is drawn as it stands; an extension in the
skipped-file list is an extension. `OutputFormat::label` stays the canonical
English in the library, and the window translates a format name where it
draws one: most are names of formats and do not move, but *DocLang archive*
has an ordinary noun in it and is *DocLang-Archiv* in German, and sending all
of them through the catalogue lets a translator decide that. The line after
adding files is two whole messages, chosen by whether the skipped list is
empty, rather than one sentence with an extension list spliced onto its end,
which a translator cannot place. The line printed to stderr when the window
will not open stays English: it goes to a terminal and into a bug report, and
one wording is what makes it searchable; the dialog beside it, which is what a
person sees, is translated.
