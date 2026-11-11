# The demo documents

Invented documents under `documents/`, and `make-demo-docs.py`, which authors
them and says what each one contains. They are what the store listing
screenshots are taken against, on every platform, so that the Microsoft Store
and the Mac App Store show the same queue.

## Why they are ours rather than the corpus

docling.rs's own `tests/data/<format>/sources/`, which the end-to-end tests
draw on, are real third-party documents - arXiv papers, somebody's handbook -
and putting their content in a commercial store listing is a license question.

These are invented. **Alder Creek Field Station does not exist**, and neither do
its readings. The subject was chosen for what it gives a converter to do rather
than for what it says: water-quality monitoring produces tables of numbers,
which is what shows off table extraction, and it cannot embarrass anyone in a
screenshot the way invented business figures could. Nothing here imitates a real
organization, and there is deliberately no invoice, receipt or anything else
that would be a fabricated record if it escaped the listing.

The documents agree with each other. The same sites and the same readings
appear in the report, the notes, the workbook and the deck, so a person reading
two of them in one screenshot finds one body of work rather than unrelated
samples.

## What each one is for

**`scanned-notice.pdf` is the only one that proves anything about the package.**
Every other document converts through a pure-Rust backend and would convert on a
machine with no `.models/` beside the executable. That one has no text layer, so
it comes back as text or it does not come back at all - it is the listing's
"scanned PDFs are read by models that ship inside the app" made checkable.

**`site-survey-report.pdf` is the one to photograph mid-conversion.** It is the
only one long enough that the queue shows a page count while the layout model
works.

The rest are breadth: `store-listing.toml` claims some forty formats, and more
rows in the queue show that the claim is about more than PDF.

## Regenerating them

    python -m venv .venv
    .venv/Scripts/pip install -r requirements.txt
    .venv/Scripts/python make-demo-docs.py

`Scripts` on Windows, `bin` elsewhere. The dependencies are pinned so that a
regeneration produces the same documents; a diff under `documents/` should mean
somebody changed the script, not that a library moved.

**Nothing in the build, the test suite or CI runs any of this**, which is the
same standing `packaging/windows/make-ico` has - off to one side, so that what
it needs never reaches the shipped binary.

**It is Python in a Rust repository** because the machine that writes them has
no Office, no LibreOffice and no pandoc, and Rust
has no PowerPoint writer worth taking a dependency on; Python has a mature
library per format. The documents are committed precisely so that this trade is
paid once, by whoever regenerates them, and never by anyone building or
packaging the application.
