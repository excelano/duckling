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
    Mac App Store     not yet reserved

The Microsoft Store reservation is the bare name, taken before the survey in
`DESIGN.md` §3. App Store Connect has not been asked; if it refuses the bare
name, the fallback is "Duckling Converter".

## Subtitle (Mac App Store, 30)

Documents to Markdown, offline

## Promotional text (Mac App Store, 170)

Drop in Word, PowerPoint, Excel, PDF and forty other formats. Get Markdown, JSON, DocLang or LaTeX back, on your own machine, with nothing sent anywhere.

## Short description (Microsoft Store, 1,000)

Duckling converts documents into the plain, structured text that language models, search indexes and version control want: DocLang, Markdown, docling JSON, a DocLang archive or LaTeX. Drop in Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio and some forty other formats, choose what to convert to and where to put it, and press Convert.

Scanned PDFs and images are read by layout, table and OCR models that ship inside the app, so it works offline from the first launch and nothing you convert leaves your machine. Output goes beside each file or into one folder, and an existing file is never overwritten.

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

DocLang, the open document markup for language models, ready to open in Segler, bare or as an archive. Markdown, with headings, lists and tables. Docling's JSON, which keeps everything the converter found. Or LaTeX.

HOW IT WORKS

Drop files or folders on the window. Choose the output format and whether the results go beside each file or into one folder. Press Convert. Each row reports as it goes, page by page for a PDF, and the preview shows every result with a button to open it or show it in its folder. An existing file is never overwritten: a second report.md becomes report (1).md.

A scanned PDF or an image is read by layout, table-structure and OCR models that ship inside the app. That is most of the download, and it is why nothing has to be fetched afterwards and why the app works with the network off.

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

Not taken yet. Each lane takes its own with its platform's script cloned from
slipcase-desktop, against the packaged application, light theme first because
both platforms ship light by default, with the pointer parked off the window
and the window photographed by its id. The queue should show a mix of
formats with a PDF mid-conversion in one shot and a finished batch with the
preview open in another.
