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
| Short description | 1,000 | — |
| Subtitle | — | 30 |
| Promotional text | — | 170 |
| Keywords | 7 terms | 100 characters |

## App name

    Microsoft Store   Duckling
    Mac App Store     not yet reserved - David creates the record; SUBMITTING.local.md

The Microsoft Store reservation is the bare name, taken before the survey in
`DESIGN.md` §3, and Product identity assigned `Excelano.Duckling` under it. App
Store Connect has not been asked; if it refuses the bare name, the fallback is
"Duckling Converter", and this line records which was taken.

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

Documents to Markdown, offline

## Promotional text (Mac App Store, 170)

Drop in Word, PowerPoint, Excel, PDF and forty other formats. Get Markdown, JSON, DocLang or LaTeX back, on your own machine, with nothing sent anywhere.

## Short description (Microsoft Store, 1,000)

Duckling converts documents into the plain, structured text that language models, search indexes and version control want: DocLang, Markdown, docling JSON, a DocLang archive or LaTeX. Drop in Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio and some forty other formats, choose what to convert to and where to put it, and press Convert.

Scanned PDFs and images are read by layout, table and OCR models that ship inside the app, so it works offline from the first launch and nothing you convert leaves your machine. Those models are most of a large download - about 600 MB - and they are why there is nothing to fetch afterwards. Output goes beside each file or into one folder, and an existing file is never overwritten.

The converter is docling.rs, the open-source Rust port of IBM's Docling. Duckling is the window around it.

## App features (Microsoft Store, up to 20 bullets of 200 characters)

    Reads Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio, and some forty formats in all.
    Writes DocLang, Markdown, docling JSON, a DocLang archive, or LaTeX.
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

DocLang, the open document markup for language models, ready to open in Segler, bare or as an archive that carries a page image per page and every picture. Markdown, with headings, lists and tables. Docling's JSON, which keeps everything the converter found. Or LaTeX.

HOW IT WORKS

Drop files or folders on the window. Choose the output format and whether the results go beside each file or into one folder. Press Convert. Each row reports as it goes, page by page for a PDF, and the preview shows every result with a button to open it or show it in its folder. An existing file is never overwritten: a second report.md becomes report (1).md.

A scanned PDF or an image is read by layout, table-structure and OCR models that ship inside the app. They are most of a download of about 600 MB, and they are why nothing has to be fetched afterwards and why the app works with the network off.

WHAT IT DOES NOT DO

No network connection of any kind. No account. No telemetry, no analytics, no crash reporting. Nothing about you or your documents is sent anywhere, because there is nowhere for it to be sent.

It does not edit. Duckling converts; correcting what a model got wrong is Segler's job, and the DocLang output is how the two connect.

OPEN SOURCE

Duckling is open source under the MIT licence, the same as the converter it is built on: github.com/excelano/duckling.

## Keywords

**Mac App Store** (100 characters, comma-separated, no spaces after commas):

    markdown,convert,pdf,word,docx,ocr,docling,doclang,json,latex

**Microsoft Store** (seven terms):

    markdown, convert, PDF, Word, OCR, docling, DocLang

## Screenshots

Not taken yet. Each lane takes its own with its platform's script, against the
packaged application, light theme first because both platforms ship light by
default, with the pointer parked off the window and the window photographed by
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

**Not taken yet, and they cannot be taken on the Mac lane.** App Store Connect
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
