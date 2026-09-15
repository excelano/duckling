# Store listing text

The text both stores are given, one draft written to the shorter of the two
limits. Every claim here is checked against the built application. The Windows
and Mac lanes copy from this file into their forms.

| Field | Microsoft Store | Mac App Store |
| --- | --- | --- |
| App name | unmeasured | 30 |
| Description | 10,000 | 4,000 |
| Short description | 500 | not asked |
| Subtitle | not asked | 30 |
| Promotional text | not asked | 170 |
| Keywords | 7 terms | 100 characters |
| Release notes | unmeasured | unmeasured |

The short description's 500 is the submission API's limit, not Partner Center's
form, which takes 1,000. The API refuses a longer text while copying the
published listing into a new draft, so the published text has to fit as well as
the new one.

## App name

    Microsoft Store   Duckling
    Mac App Store     Duckling Converter

Only the Mac App Store's listing name differs; the bundle, the window title and
every other surface say Duckling, and the support page says so where it names
the stores. The Microsoft Store product identity is `Excelano.Duckling`. The Mac
App Store lists the application for Apple silicon from the binary, so nothing
below says so.

## Subtitle (Mac App Store, 30)

Documents to DocLang, offline

## Promotional text (Mac App Store, 170)

Drop in Word, PowerPoint, Excel, PDF and forty other formats. Get DocLang, Markdown, JSON, LaTeX or an office file back, on your own machine, with nothing sent anywhere.

## Short description (Microsoft Store, 500)

Duckling converts documents into the plain, structured text that language models and search indexes want: DocLang, Markdown, docling JSON, a DocLang archive, LaTeX, ODT, ODS, ODP, DOCX or XLSX. In go Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, email and forty more.

Scanned pages are read by OCR models that ship inside the app, so it works offline and nothing leaves your machine. They are most of the download.

The converter is docling.rs, the Rust port of IBM's Docling.

## App features (Microsoft Store, up to 20 bullets of 200 characters)

    Reads Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio, and some forty formats in all.
    Writes DocLang, Markdown, docling JSON, a DocLang archive, or LaTeX. Or ODT, ODS, ODP, DOCX and XLSX, a plain office document with the pictures inside it.
    Converts a spreadsheet or a deck into the other ecosystem: XLSX to ODS, ODS to XLSX, PPTX to ODP, offered when every file in the queue is that kind.
    Text layer only, for a PDF that already has text in it: seconds rather than minutes, without the headings and tables the models find.
    Converts in batches: drop files or a whole folder, choose once, press Convert.
    Scanned PDFs and images read by layout, table-structure and OCR models that ship inside the app. Nothing to download after installing.
    Output beside each file or into one folder, and never over an existing file.
    A preview of every result, with Open and Show in folder.
    Works offline. No account, no telemetry, nothing sent anywhere.
    Open source, on an open-source converter.

## Description (both, written to 4,000)

Documents arrive as Word files, slide decks, workbooks, PDFs and scans. What a language model, a search index or a version-controlled repository wants is plain, structured text. Duckling is the step between.

WHAT GOES IN

Word, PowerPoint and Excel, current and legacy. PDF, digital or scanned. HTML, EPUB, RTF, OpenDocument, Apple Pages, Numbers and Keynote, email, Visio, Markdown, CSV, and some forty formats in all, read by docling.rs, the open-source Rust port of IBM's Docling.

WHAT COMES OUT

DocLang, the open document markup for language models, ready to open in Segler, bare or as an archive that carries a page image per page and every picture. Markdown, with headings, lists and tables. Docling's JSON, which keeps everything the converter found. Or LaTeX. Or an office document - ODT, ODS, ODP, DOCX or XLSX - plain and well structured, with the pictures inside the file; what that format cannot hold is listed on the result rather than dropped in silence.

HOW IT WORKS

Drop files or folders on the window. Choose the output format and whether the results go beside each file or into one folder. Press Convert. Each row reports as it goes, page by page for a PDF, and the preview shows every result with a button to open it or show it in its folder. An existing file is never overwritten: a second report.md becomes report (1).md.

A scanned PDF or an image is read by layout, table-structure and OCR models that ship inside the app. They are most of the download, and they are why nothing has to be fetched afterwards and why the app works with the network off.

WHAT IT DOES NOT DO

No network connection of any kind. No account. No telemetry, no analytics, no crash reporting. Nothing about you or your documents is sent anywhere, because there is nowhere for it to be sent.

It does not edit. Duckling converts; correcting what a model got wrong is Segler's job, and the DocLang output is how the two connect.

OPEN SOURCE

Duckling is open source under the MIT licence, the same as the converter it is built on: github.com/excelano/duckling.

## Release notes

*What's new in this version* on the Microsoft Store and *What's New* on the Mac
App Store, one version's text each, latest first.

### 0.2.0

Duckling writes ODS, ODP and XLSX now, alongside ODT and DOCX. The three are offered for the document each is a sibling of: ODS when every file in the queue is XLSX, XLSX when they are all ODS, ODP when they are all PPTX. A book converted to a spreadsheet is an empty sheet and a list of what was dropped, so it is not offered.

A PDF that already has text in it can be converted from that text alone, with no model loaded: seconds rather than minutes, at the cost of the headings, the tables and anything that needs OCR. The checkbox says so.

The download is 112 MB smaller. And a line that used to fall out of a paragraph and reappear after it now stays where it belongs.

Documents are read by docling.rs 1.51.

### 0.1.2

Duckling speaks German. On a machine set to German the toolbar, the queue, the preview and every line the status bar shows come up in German, and there is nothing to choose: it reads the language the desktop already knows and falls back to English for any other.

What a file is stays as the file says it. The format a row was read as, and the extensions of files the converter does not read, are not translated.

### 0.1.1

Duckling writes ODT and DOCX now, alongside DocLang, Markdown, docling JSON and LaTeX: a plain, well-structured office document made from what the converter read, with the pictures inside the file. What that format cannot hold - a page header, a picture with no image of its own - is listed on the result rather than dropped in silence, and the preview of a package shows the document as Markdown.

Documents are read by docling.rs 1.37.

## URLs

Both forms ask for the same three, and both lanes take them from here:

| Field | URL |
| --- | --- |
| Privacy policy | https://excelano.com/legal/#duckling |
| Support | https://excelano.com/duckling/#support |
| Marketing / website | https://excelano.com/duckling/ |

The page at `excelano.com/duckling/` is the support and marketing URL both; its
*Support* heading is the anchor and it offers an address and the GitHub issues.
The legal page's Duckling privacy section is `packaging/privacy-entry.html` as
pasted, and it is the answer to the Store's privacy question.

## App Review notes

Duckling converts documents. It reads Word, PowerPoint and Excel files, PDFs, HTML, EPUB, RTF, OpenDocument, Apple Pages, Numbers and Keynote and some forty formats in all, and writes DocLang, Markdown, docling JSON, LaTeX, ODT, ODS, ODP, DOCX or XLSX. No account, no sign-in, no test credentials, and no network connection of any kind are needed to test it.

There is nothing a tester must be handed before the window does anything. Duckling claims no file type and opens with an empty queue: drop any Word file or PDF you already have onto the window, or use Add files, pick an output format, and convert. If you would rather have ours, the twelve documents the screenshots were taken from are at https://github.com/excelano/duckling/tree/v0.2.0/packaging/demo/documents — invented for the purpose, MIT licensed like the rest of the repository, and between them they exercise every format claimed above.

The App Sandbox is on with exactly two entitlements: the sandbox itself and read-write access to user-selected files. That grant is what a person gives by dropping a file or a folder on the window, picking one in the Add dialogs, or choosing a destination folder. What it does not cover is the folder around a file that arrived on its own, so Duckling asks for that folder before writing beside such a file rather than failing quietly. There is no network entitlement, no Downloads-folder entitlement, and no temporary exception.

Conversion is local. Documents are read by docling.rs, the open-source Rust port of IBM's Docling, compiled into the application; nothing is uploaded and no model is fetched. The full privacy statement is at https://excelano.com/legal/#duckling and the complete source is at https://github.com/excelano/duckling.

## Notes for certification

What the Microsoft Store shows a certification tester. The message count in
the second paragraph changes with the binary: reread it off the kit report
before a submission.

```
Five DLLs ship inside the package beside duckling.exe: four Visual C++ runtime files and DirectML. The runtime files are app-local because +crt-static cannot link the ONNX Runtime this application uses - the link fails with 63 unresolved externals. DirectML is linked in by the ONNX Runtime distribution whether or not the application asks for it, at the version that library was built against rather than whatever the machine has.

The optional "Blocked executables" test reports 57 matches and the kit's overall result is PASS. Most are the three-letter scan for reg, cmd, csi, cdb and dnx finding those byte sequences inside binary weight data: layout_heron.onnx is 172 MB and contains 20 occurrences of "cmd", fewer than the 82 that uniform random bytes would produce.

The "cmd.exe" strings and CreateProcessW in duckling.exe are the Rust standard library's process module, linked in because the GUI framework uses the webbrowser crate to open hyperlinks; the application contains no call that spawns a process. ShellExecuteW is used deliberately and only on a button press: the preview pane's Open and Show in folder buttons hand the file the user just converted to the shell's default handler.

Duckling converts documents offline, so about 734 MB of the package is ONNX model weights plus pdfium and DirectML. It makes no network connection of any kind and its import table contains no ws2_32, winhttp, wininet or iphlpapi. It claims no file type, so any Word file or PDF exercises it; the twelve documents the screenshots use are at github.com/excelano/duckling/tree/v0.1.1/packaging/demo/documents
```

## The two short fields, and what goes in them

    Copyright and trademark   Excelano LLC
    Additional licence terms  blank - the application is MIT and the
                              repository carries the licence
    Short title               blank - the product name is already one word

## Keywords

**Mac App Store** (100 characters, comma-separated, no spaces after commas):

    markdown,convert,pdf,word,docx,odt,ocr,docling,doclang,json,latex

**Microsoft Store** (seven terms):

    markdown, convert, PDF, Word, OCR, docling, DocLang

## Screenshots

Each lane takes its own with its platform's script, against the packaged
application, light theme, with the pointer parked off the window and the window
photographed by its id. The documents are the ones in `packaging/demo/documents`,
copied to a folder with a short readable path, since the path shows in the
preview. Two shots:

| | State to reach |
| --- | --- |
| `01-converting` | Convert to **DocLang**, press Convert, select `field-notes.docx` about a second later, capture at about 2.5 s: some rows still Queued, the scanned PDF spinning, the rest done. |
| `02-converted` | Convert to **Markdown**, let the batch finish, select `site-survey-report.pdf`, capture. |

DocLang is selected in the first shot, where the preview is not the subject,
because its preview is markup carrying four `<location>` elements per node;
Markdown is selected in the shot with the preview open, and it is the word
people search for. In the first, the selected result comes from a Word file
rather than a PDF or the CSV, since neither of those reads as prose in a narrow
pane. In the second, a row shows `species-list.md` becoming
`species-list (1).md`, the never-overwrite rule of `DESIGN.md` §5 in the
picture; keep it. `site-survey-report.pdf` is the one long enough to be caught
mid-conversion with a page count, and `scanned-notice.pdf` is the one that
cannot convert without the models in the package, so a shot of it converted is
the offline-OCR claim photographed.

Zoom four steps, about 140%, with egui's own `Ctrl` and `+`, which the scripts
do and which nothing persists: the Store renders screenshots small, and at 100%
this application's text is about ten pixels.

**Windows.** `packaging/windows/screenshot.ps1 -Zoom 4` launches the packaged
application through the apps folder moniker with the documents as arguments,
since Duckling claims no file type and the executable under `WindowsApps`
cannot be run directly, and writes 1366x768, the Store's minimum.

**Mac App Store.** App Store Connect accepts 1280x800, 1440x900, 2560x1600 and
2880x1800; `packaging/macos/screenshot.sh` takes 1440x900 by default, from a
bundle launched with the documents as arguments. The bundle has to be the arm64
one signed with a Developer ID or Apple Development identity from the commit
being released, since a Store package cannot be launched off the Store, and it
runs only on an Apple silicon Mac; the sandbox blocks the argument route there,
so the folder goes in through Add folder. The `intel-mac` build fails every PDF
row, which for a listing whose second shot is a scanned PDF converted is a
picture of the wrong thing. Under the display's HiDPI mode
(`packaging/macos/display-mode.swift`) the window at 1440 by 900 points
captures at 2880x1800.
