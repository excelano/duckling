# Changelog

What changed for a person who installed Duckling, one section per version.
The store release notes and the apt changelog are written from this file, and
every claim here is checked against the built application rather than
remembered. `git log` is the record of why the code is the way it is; this is
not that.

## [0.1.0] (unreleased)

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
