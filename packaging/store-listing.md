# Store listing text

One draft, used twice. Both stores want the same things at different lengths,
so everything here is written to the shorter limit. Nothing here is submitted
yet; the Windows and Mac lanes copy from this file into their forms and record
in their `SUBMITTING.local.md` what the form did with it.

This is written from `CHANGELOG.md`, not beside it. Every claim below appears
there first, checked against the built application. If the two disagree, the
changelog is right and this is stale.

Limits, so a later edit does not overrun them:

| Field | Microsoft Store | Mac App Store |
| --- | --- | --- |
| App name | unmeasured | 30 |
| Description | 10,000 | 4,000 |
| Short description | 500 | — |
| Subtitle | — | 30 |
| Promotional text | — | 170 |
| Keywords | 7 terms | 100 characters |
| Release notes | unmeasured | unmeasured |

**The API's limit is not the form's, and the API's is the one that binds now.**
Partner Center's form takes 1,000 characters of short description and 0.1.0 went
up with 867. The submission API refuses anything over 500 - *The length of
ShortDescription must be 500 or less* - and it refuses it while copying the
**published** listing into the new draft, so the old text blocked the upload
before the new text was ever sent. Measured 2026-09-09 on this product's first
API submission. Once a product goes up that way its short description lives at
500, and the number in the table above is the API's.

## App name

    Microsoft Store   Duckling
    Mac App Store     Duckling Converter

The Microsoft Store reservation is the bare name, taken before the survey in
`DESIGN.md` §3, and Product identity assigned `Excelano.Duckling` under it. App
Store Connect refused the bare name when David created the record on
2026-09-05, and the fallback was taken: the Mac App Store lists the
application as **Duckling Converter**. The bundle, the window title and every
other surface still say Duckling; only the store's listing name differs, and
the support page says so where it names the stores.

## The download size, which the listing has to say

**605 MB**, measured on the Windows lane 2026-09-05 against
`Duckling-0.1.0.0-x64.msix`, and **594 MB** on the Mac lane the same day
against an unsigned `productbuild` of the arm64 bundle, whose installed size
is 805 MB. `RELEASE.md` said the listing should say it and this is where that
is kept true: three quarters of the package is ONNX weights that barely
compress, and a person deciding whether to install should meet the number in
the description rather than in the progress bar. It appears twice below, in
the short description and in HOW IT WORKS, and both are written to survive
the number changing by a few tens of megabytes without becoming wrong.

**The Mac App Store lists the application for Apple silicon**, and does so
from the binary rather than from anything written here; `DESIGN.md` §2 says
why there is no Intel build. Nothing below says "Apple silicon" because the
Store says it in its own place, and the Windows text is the same text.

## Subtitle (Mac App Store, 30)

Documents to DocLang, offline

## Promotional text (Mac App Store, 170)

Drop in Word, PowerPoint, Excel, PDF and forty other formats. Get DocLang, Markdown, JSON, LaTeX, ODT or DOCX back, on your own machine, with nothing sent anywhere.

## Short description (Microsoft Store, 500)

Duckling converts documents into the plain, structured text that language models and search indexes want: DocLang, Markdown, docling JSON, a DocLang archive, LaTeX, ODT or DOCX. In go Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, email and forty more formats.

Scanned pages are read by OCR models that ship inside the app, so it works offline and nothing leaves your machine. They are most of a download of about 600 MB.

The converter is docling.rs, the Rust port of IBM's Docling.

## App features (Microsoft Store, up to 20 bullets of 200 characters)

    Reads Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio, and some forty formats in all.
    Writes DocLang, Markdown, docling JSON, a DocLang archive, or LaTeX. Or ODT and DOCX, a plain office document with the pictures inside it.
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

DocLang, the open document markup for language models, ready to open in Segler, bare or as an archive that carries a page image per page and every picture. Markdown, with headings, lists and tables. Docling's JSON, which keeps everything the converter found. Or LaTeX. Or an ODT or DOCX office document, plain and well structured, with the pictures inside the file; what that format cannot hold is listed on the result rather than dropped in silence.

HOW IT WORKS

Drop files or folders on the window. Choose the output format and whether the results go beside each file or into one folder. Press Convert. Each row reports as it goes, page by page for a PDF, and the preview shows every result with a button to open it or show it in its folder. An existing file is never overwritten: a second report.md becomes report (1).md.

A scanned PDF or an image is read by layout, table-structure and OCR models that ship inside the app. They are most of a download of about 600 MB, and they are why nothing has to be fetched afterwards and why the app works with the network off.

WHAT IT DOES NOT DO

No network connection of any kind. No account. No telemetry, no analytics, no crash reporting. Nothing about you or your documents is sent anywhere, because there is nowhere for it to be sent.

It does not edit. Duckling converts; correcting what a model got wrong is Segler's job, and the DocLang output is how the two connect.

OPEN SOURCE

Duckling is open source under the MIT licence, the same as the converter it is built on: github.com/excelano/duckling.

## Release notes

*What's new in this version* on the Microsoft Store and *What's New* on the Mac
App Store, one version's text each, written from `CHANGELOG.md` the way
everything else here is and kept latest first. 0.1.0 has none and gets none:
nobody had the application from either store when it went up, so there was
nobody to tell. Neither field's limit has been measured, and the text below is
short enough that it has not had to be.

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

The page at `excelano.com/duckling/` is the support and marketing URL both, the
way segler's and slipcase-desktop's are; its *Support* heading is the anchor
and it offers an address and the GitHub issues. Both pages were read back on
2026-09-06 and both carry their section: the legal page's Duckling privacy
section is `packaging/privacy-entry.html` as pasted, and it is the answer to
the Store's privacy question.

## App Review notes

Duckling converts documents. It reads Word, PowerPoint and Excel files, PDFs, HTML, EPUB, RTF, OpenDocument, Apple Pages, Numbers and Keynote and some forty formats in all, and writes DocLang, Markdown, docling JSON, LaTeX, ODT or DOCX. No account, no sign-in, no test credentials, and no network connection of any kind are needed to test it.

There is nothing a tester must be handed before the window does anything. Duckling claims no file type and opens with an empty queue: drop any Word file or PDF you already have onto the window, or use Add files, pick an output format, and convert. If you would rather have ours, the twelve documents the screenshots were taken from are at https://github.com/excelano/duckling/tree/v0.1.2/packaging/demo/documents — invented for the purpose, MIT licensed like the rest of the repository, and between them they exercise every format claimed above.

The App Sandbox is on with exactly two entitlements: the sandbox itself and read-write access to user-selected files. That grant is what a person gives by dropping a file or a folder on the window, picking one in the Add dialogs, or choosing a destination folder. What it does not cover is the folder around a file that arrived on its own, so Duckling asks for that folder before writing beside such a file rather than failing quietly. There is no network entitlement, no Downloads-folder entitlement, and no temporary exception.

Conversion is local. Documents are read by docling.rs, the open-source Rust port of IBM's Docling, compiled into the application; nothing is uploaded and no model is fetched. The full privacy statement is at https://excelano.com/legal/#duckling and the complete source is at https://github.com/excelano/duckling.

## Notes for certification

What the Microsoft Store shows a certification tester, and what the fenced
block below is. It answers the question this package raises and no other in
the fleet does: five DLLs ship beside the executable, and a tester who looks
will find four Visual C++ runtime files and DirectML.

The message count changes with the binary. Reread it off the kit report
before a submission rather than trusting the number below.

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

Taken on Windows 2026-09-05; the Mac's are in their own section below. Each
lane takes its own with its platform's script, against the packaged
application, light theme first because both platforms ship light by default, with the pointer parked off the window and the window photographed by
its id. The queue should show a mix of formats with a PDF mid-conversion in one
shot and a finished batch with the preview open in another.

On Windows that script is `packaging/windows/screenshot.ps1`, which takes the
documents to queue and writes one PNG at a size the Store accepts. It launches
the *packaged* application, which needs saying because it cannot do it the way
segler's copy does: Duckling registers no file type as its own, so opening a
document opens whatever owns that document, and the executable inside
`WindowsApps` refuses to be run directly. It goes through the apps folder
moniker with arguments instead, which is the same activation path Open With
takes. `packaging/windows/README.md` §5 has the measurement.

**Which documents was the editorial decision, and it is taken.** The obvious
source was docling.rs's own test corpus; David chose on 2026-09-05 to author six
instead, because the corpus files are real third-party documents and their
content in a commercial listing is a licence question better not created.
`packaging/demo/` holds them and the script that makes them, and its README
argues the choice at length. The queue in a screenshot therefore reads:

    site-survey-report.pdf     orientation-deck.pptx
    field-notes.docx           observers-handbook.epub
    sample-log.xlsx            scanned-notice.pdf

Two of those are doing a job. `site-survey-report.pdf` is the only one long
enough to be caught mid-conversion showing a page count, and `scanned-notice.pdf`
is the only one in the set that cannot convert without the models in the
package - so a screenshot of it converted is the offline-OCR claim above,
photographed.

**Which output format is selected matters more than it looks.** DocLang is the
default and the thing no competitor has, but it previews as markup carrying four
`<location>` elements per node - correct, and dense to look at. So: DocLang
selected in the queue shot, where the preview is not the subject, and **Markdown
in the shot with the preview open**, which is also the word people searched for.

## Screenshots (Mac App Store)

**Taken 2026-09-07 on the rented Mac mini M1**, from the `v0.1.0` tag's arm64
bundle signed for development, the same two states as Windows: `01-converting`
with seven done, the scanned PDF spinning and four queued, `field-notes.docx`
selected in DocLang; `02-converted` in Markdown with `site-survey-report.pdf`
selected and `species-list (1).md` in row eleven. 2880x1800 each, the window
at 1440 by 900 points on the display's HiDPI mode (`display-mode.swift`), four
zoom steps, pointer parked, the twelve documents in `/Users/m1/Documents/Alder
Creek`. Uploaded to the en-US desktop screenshot set through the API the same
evening. The sandbox blocks the script's argument route, so the folder went in
through Add folder by hand and the rest was driven over ssh. App Store Connect
accepts 1280x800, 1440x900, 2560x1600 and 2880x1800, and
`packaging/macos/screenshot.sh` takes 1440x900 by default, by window id with
the pointer parked, from a bundle launched with the documents as arguments.
The bundle has to be the arm64 one signed with a Developer ID or Apple
Development identity from the commit being released - a Store package cannot
be launched off the Store - and that bundle runs only on an Apple silicon Mac.
The `intel-mac` build on the lane machine draws the same window and fails
every PDF row, which for a listing whose second shot is a scanned PDF
converted is a picture of the wrong thing. So the two shots below are taken
where the walkthrough is, with the same twelve documents and the same two
states, and this section records which commit they came from once they exist.

## The recipe, so the Mac lane can match

Taken on Windows 2026-09-05. Both 1366x768, the Store's minimum, light theme,
the twelve documents copied to a folder with a short readable path -
`C:\Users\david\Documents\Alder Creek` was used, and the path shows in the
preview, so a scratch directory is the wrong place for them.

**Zoom four steps, which is about 140%, and it is not vanity.** The Store
renders screenshots small and at 100% this application's text is about ten
pixels: legible in the window, not in a thumbnail. Four steps also stops the
preview pane wrapping DocLang into fragments. `screenshot.ps1 -Zoom 4` does it
with egui's own `Ctrl` and `+`, and nothing persists.

| | State to reach |
| --- | --- |
| `01-converting` | Convert to **DocLang**, press Convert, select `field-notes.docx` about a second later, capture at ~2.5s. Four rows still Queued, the scanned PDF spinning, seven done. |
| `02-converted` | Convert to **Markdown**, let the batch finish, select `site-survey-report.pdf`, capture. |

Two details worth keeping if the shots are retaken. In the first, select a
result that came from a Word file rather than from a PDF or the CSV: PDF DocLang
carries the `<location>` elements and the CSV is all table markup, and neither
reads as prose in a narrow pane. In the second, row eleven shows
`species-list.md` becoming `species-list (1).md` - the never-overwrite rule of
`DESIGN.md` 5 demonstrating itself, unplanned, in the picture. Do not lose it.
