//! The worker end to end: a request in, a file on disk and an event out.
//! Fixtures are the docling.rs conformance corpus, which lives in a clone
//! beside this repository on David's machine and nowhere in CI; every test
//! here skips, loudly, when it is absent. The PDF test also needs the
//! models under `.models/` and pdfium under `.pdfium/`, which
//! `packaging/fetch-models.sh` puts there.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use duckling::{Destination, Event, JobId, OutputFormat, Request, Worker};

fn corpus() -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    let dir = Path::new(&home).join("clones/docling.rs/tests/data");
    dir.is_dir().then_some(dir)
}

fn fresh_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("duckling-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Submit one request and wait for its outcome.
fn convert(source: &Path, format: OutputFormat, into: &Path) -> Result<duckling::Outcome, String> {
    let worker = Worker::spawn(|| {});
    worker.submit(Request {
        id: JobId(1),
        source: source.to_path_buf(),
        format,
        destination: Destination::Folder(into.to_path_buf()),
    });
    let deadline = Instant::now() + Duration::from_secs(300);
    loop {
        for event in worker.poll() {
            if let Event::Finished(JobId(1), result) = event {
                return result;
            }
        }
        assert!(Instant::now() < deadline, "no outcome within five minutes");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn docx_to_markdown_writes_a_file_with_the_table() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    let out = fresh_dir("docx");
    let outcome = convert(
        &corpus.join("docx/sources/word_tables.docx"),
        OutputFormat::Markdown,
        &out,
    )
    .unwrap();
    assert_eq!(outcome.output, out.join("word_tables.md"));
    let text = std::fs::read_to_string(&outcome.output).unwrap();
    assert!(text.contains('|'), "no table in the Markdown");
    assert_eq!(text, outcome.preview);
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn xlsx_to_doclang_writes_an_archive_and_previews_the_xml() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    let out = fresh_dir("xlsx");
    let outcome = convert(
        &corpus.join("xlsx/sources/xlsx_05_table_with_title.xlsx"),
        OutputFormat::DoclangArchive,
        &out,
    )
    .unwrap();
    let bytes = std::fs::read(&outcome.output).unwrap();
    assert_eq!(&bytes[..2], b"PK", "a .dclx is a zip");
    assert!(
        outcome.preview.contains("<doclang"),
        "preview is the DocLang XML"
    );
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn docx_to_doclang_writes_the_markup_bare() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    let out = fresh_dir("dclg");
    let outcome = convert(
        &corpus.join("docx/sources/word_tables.docx"),
        OutputFormat::Doclang,
        &out,
    )
    .unwrap();
    assert_eq!(outcome.output, out.join("word_tables.dclg"));
    let text = std::fs::read_to_string(&outcome.output).unwrap();
    assert!(text.contains("<doclang"), "{}", &text[..80.min(text.len())]);
    assert!(text.ends_with('\n'));
    assert_eq!(text, outcome.preview);
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn an_unreadable_extension_fails_rather_than_panics() {
    let out = fresh_dir("unknown");
    let source = out.join("thing.xyz");
    std::fs::write(&source, b"?").unwrap();
    let err = convert(&source, OutputFormat::Markdown, &out).unwrap_err();
    assert!(err.contains(".xyz"), "{err}");
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn pdf_through_the_pipeline_finds_headings() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    if !Path::new(".models/layout_heron_int8.onnx").exists() {
        eprintln!("skipped: models not fetched");
        return;
    }
    let out = fresh_dir("pdf");
    let outcome = convert(
        &corpus.join("pdf/sources/normal_4pages.pdf"),
        OutputFormat::Markdown,
        &out,
    )
    .unwrap();
    let text = std::fs::read_to_string(&outcome.output).unwrap();
    assert!(
        text.contains("## "),
        "the layout model should have produced headings:\n{text}"
    );
    std::fs::remove_dir_all(&out).unwrap();
}
