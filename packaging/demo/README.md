# The demo documents

Six invented documents, and the script that authors them. They are what the
Store listing screenshots are taken against, on every platform, so that the
Microsoft Store and the Mac App Store show the same queue.

    documents/site-survey-report.pdf     a digital PDF: headings, a table, two pages
    documents/field-notes.docx           Word: headings, a bulleted list, a table
    documents/sample-log.xlsx            a workbook with two sheets
    documents/orientation-deck.pptx      four slides, one of them a table
    documents/observers-handbook.epub    three chapters
    documents/scanned-notice.pdf         one page, no text layer, faintly crooked

## Why they are ours rather than the corpus

The obvious source was docling.rs's own `tests/data/<format>/sources/`, which is
what the end-to-end tests draw on and what `CHECKLIST.md` sends a person to.
David decided against it on 2026-09-05, and the reason is worth keeping: those
are real third-party documents - arXiv papers, somebody's handbook - and putting
their content in a commercial store listing is a licence question that would
have to be answered later, by somebody with less context, probably in a hurry.

These are invented. **Alder Creek Field Station does not exist**, and neither do
its readings. The subject was chosen for what it gives a converter to do rather
than for what it says: water-quality monitoring produces tables of numbers,
which is what shows off table extraction, and it cannot embarrass anyone in a
screenshot the way invented business figures could. Nothing here imitates a real
organisation, and there is deliberately no invoice, receipt or anything else
that would be a fabricated record if it escaped the listing.

The six agree with each other. The same five sites and the same readings appear
in the report, the notes, the workbook and the deck, so a person reading two of
them in one screenshot finds one body of work rather than six unrelated samples.

## What each one is for

**`scanned-notice.pdf` is the only one that proves anything about the package.**
Every other document converts through a pure-Rust backend and would convert on a
machine with no `.models/` beside the executable. That one has no text layer, so
it comes back as text or it does not come back at all - it is the listing's
"scanned PDFs are read by models that ship inside the app" made checkable.
Measured 2026-09-05 against the installed MSIX: two headings and three
paragraphs, with one trailing full stop lost.

**`site-survey-report.pdf` is the one to photograph mid-conversion.** It is the
only one long enough that the queue shows a page count while the layout model
works. Measured the same day: twelve headings, the readings table with its
column heads, and a page break.

The other four are breadth. `store-listing.md` claims some forty formats; four
more rows in the queue is the cheapest honest way to show that the claim is
about more than PDF.

## Regenerating them

    python -m venv .venv
    .venv/Scripts/pip install -r requirements.txt
    .venv/Scripts/python make-demo-docs.py

`Scripts` on Windows, `bin` elsewhere. The dependencies are pinned so that a
regeneration produces the same documents; a diff under `documents/` should mean
somebody changed the script, not that a library moved.

**Nothing in the build, the test suite or CI runs any of this**, which is the
same standing `packaging/windows/make-ico` has - off to one side, so that what
it needs never reaches the shipped binary. Unlike `make-ico` there is no CI
check comparing the committed output against a rebuild: these documents are not
derived from anything else in the tree, so there is nothing for them to drift
against.

**Why it is Python in a Rust repository**, since that is the question a reader
will have. This machine has no Office, no LibreOffice and no pandoc, and Rust
has no PowerPoint writer worth taking a dependency on; Python has a mature
library per format. The documents are committed precisely so that this trade is
paid once, by whoever regenerates them, and never by anyone building or
packaging the application.
