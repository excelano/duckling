# Changelog

What changed for a person who installed Duckling, one section per version.
The store release notes and the apt changelog are written from this file, and
every claim here is checked against the built application rather than
remembered. `git log` is the record of why the code is the way it is; this is
not that.

`Unreleased` at the top holds what has landed since the last release and
takes a version and a date when one ships, which is what `preflight.sh`
looks for before it will submit.

## [0.2.0] - 2026-09-14

- **Writes ODS, ODP and XLSX as well**, through waddle, and offers each for
  the document it is a sibling of: ODS when every file in the queue is XLSX,
  XLSX when they are all ODS, ODP when they are all PPTX. A book converted to
  a spreadsheet is one empty sheet and a list of what was dropped, so it is
  not offered. The slide leg is one-way, because waddle writes ODP and no
  PPTX. Picking a format the queue stops warranting puts it back to DocLang
  and the status bar says why.
- **Text layer only**, a checkbox for a PDF that already has text in it.
  Clean Code, 460 pages, takes 179 seconds through the models and 1.2 seconds
  from its text layer. What it gives up is the headings — 211 of them in that
  book, none without the models — along with the tables and any page that
  needs OCR. A file with no text layer at all comes back with a line saying
  so, rather than as a silent blank.
- **A line no longer falls out of a paragraph.** On a PDF, roughly every few
  paragraphs, one line was dropped from the paragraph it belonged to and
  written after it, splicing the sentence it left behind. Found from this
  application's own output and fixed upstream; Duckling now reads with
  docling.rs 1.51.
- **The install is about 230 MB smaller**, and nothing converts differently
  for it. Three of the table-structure model files were variants docling.rs
  never opened, because one it prefers ships beside them. The table-structure
  encoder is a further 118 MB smaller than the file that shipped before, the
  same model with padding stripped out of it upstream. On Linux that is
  575 MB installed.

## [0.1.2] - 2026-09-09

- **German.** Duckling comes up in German on a machine set to German — the
  toolbar, the queue, the preview and every line the status bar shows. Nothing
  to choose: it reads the language the desktop already knows, and falls back to
  English for any other.
- What a file is stays as the file says it. The format a row was read as, and
  the extensions of files docling.rs does not read, are not translated; nor are
  the names of most output formats, DOCX and JSON being DOCX and JSON in any
  language.

## [0.1.1] - 2026-09-08

- Writes ODT and DOCX as well, through waddle: a plain, well-structured
  office document from what docling.rs read, with the pictures inside the
  package. What the package could not hold, a page header or a picture
  without its image, is listed on the result. The preview of a package
  shows the document as Markdown.
- Reads with docling.rs 1.37.

## [0.1.0] - 2026-09-06

The first packaged build.

- Converts Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument,
  Apple iWork, email, Visio and some forty other formats, read by docling.rs.
- Writes DocLang, Markdown, docling JSON, a DocLang archive or LaTeX.
  DocLang is the default. A DocLang archive carries a page image per page
  for a PDF or an image and the document's pictures under `assets/`; bare
  DocLang gets its pictures in an `assets/` folder beside it.
- Files and folders arrive from the command line, from a drop on the window,
  or from the Add buttons; a folder contributes every readable file under
  it. Nothing converts until Convert is pressed, so one choice of format and
  destination applies to the whole batch.
- Output beside each source or into one folder, and never over an existing
  file: a second `report.md` becomes `report (1).md`.
- Scanned PDFs and images read by layout, table-structure and OCR models
  that ship inside the package. Nothing is downloaded after installing, and
  the models are why the download is about 600 MB.
- A preview of each result, with Open and Show in folder.
- No network connection of any kind. No account, no telemetry.
- On Windows, Duckling appears under Open With for the document types it
  reads and becomes the default for none of them: a PDF still opens with
  whatever opened it before.
- On macOS, Duckling needs a Mac with Apple silicon. Converting beside a file
  that was added on its own asks for its folder first, because the App
  Sandbox grants the file alone; a folder added whole, or a destination
  folder, is never asked about.
