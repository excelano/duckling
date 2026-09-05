# Duckling

Duckling converts documents into Markdown, JSON, DocLang or LaTeX, on your
own machine, with nothing sent anywhere. Drop in Word, PowerPoint, Excel,
PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, email, Visio and some forty
other formats, choose what to convert to and where to put it, and press
Convert. Scanned PDFs and images are read by layout and OCR models that ship
inside the application, so there is nothing to download after installing.

The converter is [docling.rs](https://github.com/docling-project/docling.rs),
the Rust port of IBM's Docling. Duckling is the window around it, and adds
no conversion logic of its own.

## Build

```
./packaging/fetch-models.sh     # once; about 750 MB of models and pdfium
cargo build --release
```

A Rust toolchain builds the application. The PDF pipeline links ONNX Runtime,
which arrives as a prebuilt static library, and loads pdfium at run time from
`.pdfium/lib` beside the working directory or the executable. `DESIGN.md` §2
says what that dependency costs and why it is taken.

## Run

```
cargo run --release -- [FILE|FOLDER ...]
```

Files and folders given on the command line, dropped on the window, or
picked with the buttons are queued. A folder contributes every file under it
that docling.rs can read. Nothing is converted until Convert is pressed, so
the format and destination chosen at that moment apply to the whole batch.
Output goes beside each source file or into one folder, and an existing file
is never overwritten: a second `report.md` becomes `report (1).md`.

## Where things are

`src/lib.rs` is the job model and the conversion worker, with no knowledge of
a window. `src/main.rs` is the window. `packaging/` holds what turns a build
into a package for each platform. `DESIGN.md` is where every decision and its
reasoning live; `CLAUDE.md` is the short guide for a session working here.

## License

MIT, like docling.rs. The models Duckling ships are docling's, under their
own licenses, listed in `packaging/fetch-models.sh` by origin.
