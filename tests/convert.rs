//! The worker end to end: a request in, a file on disk and an event out.
//! Fixtures are the docling.rs conformance corpus, which lives in a clone
//! beside this repository on David's machine and nowhere in CI; every test
//! drawing on it skips, loudly, when it is absent. The PDF tests also need
//! the models under `.models/` and pdfium under `.pdfium/`, which
//! `packaging/fetch-models.sh` puts there.
//!
//! The tests at the end draw on `packaging/demo/documents` instead, which is
//! in the tree, so they run wherever the models are - and on the Apple
//! silicon runner they are the only conversion the release architecture ever
//! gets before a person walks it through, since the Mac lane is an Intel
//! machine the release build cannot run on.
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
    if !pipeline_available() {
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

#[test]
fn pdf_to_archive_carries_one_page_image_per_page() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    if !pipeline_available() {
        return;
    }
    let out = fresh_dir("pdf-dclx");
    let outcome = convert(
        &corpus.join("pdf/sources/normal_4pages.pdf"),
        OutputFormat::DoclangArchive,
        &out,
    )
    .unwrap();
    assert!(outcome.notes.is_empty(), "{:?}", outcome.notes);
    let names = zip_names(&std::fs::read(&outcome.output).unwrap());
    assert_eq!(
        outcome.preview.matches("<page_break/>").count(),
        3,
        "three breaks for four pages"
    );
    for n in 1..=4 {
        assert!(names.contains(&format!("pages/{n}.png")), "{names:?}");
    }
    assert!(!names.contains(&"pages/5.png".to_owned()));
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn docx_with_pictures_writes_assets_beside_bare_doclang() {
    let Some(corpus) = corpus() else {
        eprintln!("skipped: no docling.rs corpus");
        return;
    };
    let out = fresh_dir("dclg-assets");
    let outcome = convert(
        &corpus.join("docx/sources/word_sample.docx"),
        OutputFormat::Doclang,
        &out,
    )
    .unwrap();
    let xml = std::fs::read_to_string(&outcome.output).unwrap();
    let named: Vec<&str> = xml
        .split("<src uri=\"")
        .skip(1)
        .filter_map(|rest| rest.split('"').next())
        .filter(|u| u.starts_with("assets/"))
        .collect();
    assert!(
        !named.is_empty(),
        "word_sample.docx carries pictures; the markup names none:\n{}",
        &xml[..600.min(xml.len())]
    );
    for name in named {
        let path = out.join(name);
        assert!(path.is_file(), "{} named but not written", path.display());
        assert!(
            std::fs::read(&path).unwrap().starts_with(b"\x89PNG"),
            "{name} is not PNG"
        );
    }
    std::fs::remove_dir_all(&out).unwrap();
}

fn zip_names(bytes: &[u8]) -> Vec<String> {
    let mut names = Vec::new();
    let mut i = 0;
    while i + 46 <= bytes.len() {
        if bytes[i..i + 4] == [0x50, 0x4b, 0x01, 0x02] {
            let n = u16::from_le_bytes([bytes[i + 28], bytes[i + 29]]) as usize;
            names.push(String::from_utf8_lossy(&bytes[i + 46..i + 46 + n]).into_owned());
            i += 46 + n;
        } else {
            i += 1;
        }
    }
    names
}

/// The invented documents under `packaging/demo`, which are in the tree.
fn demo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("packaging/demo/documents")
}

/// Whether the PDF pipeline can run here: the models fetched, and an ONNX
/// Runtime in the binary to run them, which the `intel-mac` build has not.
fn pipeline_available() -> bool {
    if cfg!(feature = "intel-mac") {
        eprintln!("skipped: built without ONNX Runtime");
        return false;
    }
    let fetched = Path::new(".models/layout_heron_int8.onnx").exists();
    if !fetched {
        eprintln!("skipped: models not fetched");
    }
    fetched
}

#[test]
fn demo_word_file_converts_with_its_table() {
    let out = fresh_dir("demo-docx");
    let outcome = convert(
        &demo().join("field-notes.docx"),
        OutputFormat::Markdown,
        &out,
    )
    .unwrap();
    let text = std::fs::read_to_string(&outcome.output).unwrap();
    assert!(text.contains('|'), "no table in the Markdown:\n{text}");
    std::fs::remove_dir_all(&out).unwrap();
}

#[test]
fn demo_digital_pdf_converts_through_the_layout_model() {
    if !pipeline_available() {
        return;
    }
    let out = fresh_dir("demo-pdf");
    let outcome = convert(
        &demo().join("site-survey-report.pdf"),
        OutputFormat::Markdown,
        &out,
    )
    .unwrap();
    let text = std::fs::read_to_string(&outcome.output).unwrap();
    assert!(text.contains("## "), "no headings:\n{text}");
    assert!(text.contains('|'), "no table:\n{text}");
    std::fs::remove_dir_all(&out).unwrap();
}

/// The one document in the set that proves the models are there: no text
/// layer, so it comes back through OCR or not at all.
#[test]
fn demo_scanned_pdf_comes_back_through_ocr() {
    if !pipeline_available() {
        return;
    }
    let out = fresh_dir("demo-scan");
    let outcome = convert(
        &demo().join("scanned-notice.pdf"),
        OutputFormat::Markdown,
        &out,
    )
    .unwrap();
    let text = std::fs::read_to_string(&outcome.output)
        .unwrap()
        .to_lowercase();
    assert!(
        text.contains("gauge board") && text.contains("meadow gate"),
        "the notice did not come back through OCR:\n{text}"
    );
    std::fs::remove_dir_all(&out).unwrap();
}
