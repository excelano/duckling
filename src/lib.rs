//! Duckling's job model: what to convert, into what, where to, and the worker
//! that does it. Nothing in this file knows about a window. The application
//! in `main.rs` renders `Job`s and sends `Request`s; if a native front-end
//! ever replaces the egui one, this is what it talks to.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

#![forbid(unsafe_code)]

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;
use std::thread;

use docling::{
    ConversionStatus, DoclingDocument, DocumentConverter, InputFormat, Pipeline, SourceDocument,
};

/// Point docling.rs at the models and pdfium a package installed beside the
/// executable, when they are there and nothing has said otherwise.
///
/// docling.rs looks for `.models/` and `.pdfium/lib/` under the working
/// directory, then under `$DOCLING_RS_MODELS_DIR` and `$PDFIUM_DYNAMIC_LIB_PATH`,
/// then beside the executable under the same dotted names. A package cannot
/// use the dotted names: Debian wants an application's private data under
/// `/usr/lib/duckling/` without hidden directories, and a Windows or Mac
/// package has the same reasons to name them plainly. So a package installs
/// `models/` and `pdfium/` beside the executable, and this names them
/// through the two variables, which docling.rs reads before it looks beside
/// the executable itself.
///
/// Called once at startup, before the worker thread exists. An environment
/// already set, by a developer pointing at another model set, is left alone;
/// so is a working directory carrying `.models/`, which is how a checkout
/// runs. Returns where the models were found, for the status line.
pub fn locate_assets() -> Option<PathBuf> {
    if Path::new(".models").is_dir() {
        return Some(PathBuf::from(".models"));
    }
    if let Some(dir) = std::env::var_os("DOCLING_RS_MODELS_DIR") {
        return Some(PathBuf::from(dir));
    }
    let beside = std::env::current_exe()
        .ok()
        .and_then(|p| p.canonicalize().ok())
        .and_then(|p| p.parent().map(Path::to_path_buf))?;
    let models = beside.join("models");
    let pdfium = beside.join("pdfium");
    if !models.is_dir() {
        return None;
    }
    // Edition 2021: `set_var` is a safe function, and no other thread exists
    // yet to observe the environment changing under it.
    std::env::set_var("DOCLING_RS_MODELS_DIR", &models);
    if pdfium.is_dir() && std::env::var_os("PDFIUM_DYNAMIC_LIB_PATH").is_none() {
        std::env::set_var("PDFIUM_DYNAMIC_LIB_PATH", &pdfium);
    }
    Some(models)
}

/// Identifies a job across the window and the worker. Never reused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct JobId(pub u64);

/// What a conversion writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OutputFormat {
    /// DocLang markup, bare: a `.dclg`. The default, and what Segler opens.
    #[default]
    Doclang,
    Markdown,
    /// docling's own JSON, the lossless form of a `DoclingDocument`.
    Json,
    /// The same markup as `document.xml` inside an OPC zip, a `.dclx`. Nothing
    /// else goes in it today; DESIGN.md §9 says what could.
    DoclangArchive,
    Latex,
}

impl OutputFormat {
    pub const ALL: [OutputFormat; 5] = [
        OutputFormat::Doclang,
        OutputFormat::Markdown,
        OutputFormat::Json,
        OutputFormat::DoclangArchive,
        OutputFormat::Latex,
    ];

    pub fn label(self) -> &'static str {
        match self {
            OutputFormat::Doclang => "DocLang",
            OutputFormat::Markdown => "Markdown",
            OutputFormat::Json => "JSON",
            OutputFormat::DoclangArchive => "DocLang archive",
            OutputFormat::Latex => "LaTeX",
        }
    }

    pub fn extension(self) -> &'static str {
        match self {
            OutputFormat::Doclang => "dclg",
            OutputFormat::Markdown => "md",
            OutputFormat::Json => "json",
            OutputFormat::DoclangArchive => "dclx",
            OutputFormat::Latex => "tex",
        }
    }

    /// Whether the written file is text a person can read in the preview.
    pub fn is_text(self) -> bool {
        !matches!(self, OutputFormat::DoclangArchive)
    }
}

/// Where converted files go.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Destination {
    /// Next to the source, with the output extension.
    BesideSource,
    Folder(PathBuf),
}

impl Destination {
    /// The path a conversion of `source` will be written to, before the
    /// collision rule in [`available_path`] is applied.
    pub fn target(&self, source: &Path, format: OutputFormat) -> PathBuf {
        let stem = source
            .file_stem()
            .map(|s| s.to_os_string())
            .unwrap_or_else(|| "document".into());
        let mut name = stem;
        name.push(".");
        name.push(format.extension());
        match self {
            Destination::BesideSource => source.with_file_name(name),
            Destination::Folder(dir) => dir.join(name),
        }
    }
}

/// The first of `path`, `stem (1).ext`, `stem (2).ext`, … that does not exist.
/// A converter that writes beside its source must never overwrite: the source
/// itself may carry the output extension (Markdown to Markdown), and a
/// `report.md` that already sits beside `report.pdf` is somebody's work.
pub fn available_path(path: &Path) -> PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let ext = path
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    (1..)
        .map(|n| path.with_file_name(format!("{stem} ({n}){ext}")))
        .find(|p| !p.exists())
        .expect("an unbounded range always yields")
}

/// One file in the queue, as the window shows it.
#[derive(Debug, Clone)]
pub struct Job {
    pub id: JobId,
    pub source: PathBuf,
    /// What docling.rs took the file for, from its extension.
    pub format: InputFormat,
    pub state: JobState,
}

impl Job {
    pub fn file_name(&self) -> String {
        self.source
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.source.display().to_string())
    }
}

#[derive(Debug, Clone)]
pub enum JobState {
    Queued,
    /// Pages done and pages selected, for PDFs; `(0, 0)` for everything else.
    Converting {
        pages_done: usize,
        pages_total: usize,
    },
    Done(Outcome),
    Failed(String),
}

/// What a finished conversion left behind.
#[derive(Debug, Clone)]
pub struct Outcome {
    pub output: PathBuf,
    pub status: ConversionStatus,
    /// The written text, capped at [`PREVIEW_CAP`] bytes, or for a binary
    /// output the DocLang XML inside it. `preview_truncated` says which.
    pub preview: String,
    pub preview_truncated: bool,
}

/// The preview is a courtesy, not a viewer; a 40 MB JSON export stays on disk.
pub const PREVIEW_CAP: usize = 256 * 1024;

/// What the window asks the worker to do.
#[derive(Debug, Clone)]
pub struct Request {
    pub id: JobId,
    pub source: PathBuf,
    pub format: OutputFormat,
    pub destination: Destination,
}

/// What the worker tells the window.
#[derive(Debug)]
pub enum Event {
    Started(JobId),
    Progress {
        id: JobId,
        pages_done: usize,
        pages_total: usize,
    },
    Finished(JobId, Result<Outcome, String>),
}

/// Why a path was not queued.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rejection {
    NoExtension,
    UnknownExtension(String),
}

impl fmt::Display for Rejection {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Rejection::NoExtension => write!(f, "no file extension"),
            Rejection::UnknownExtension(ext) => write!(f, "not a format docling.rs reads: .{ext}"),
        }
    }
}

/// The input format for a path, by extension, as docling.rs decides it.
pub fn detect(path: &Path) -> Result<InputFormat, Rejection> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or(Rejection::NoExtension)?;
    InputFormat::from_extension(ext).ok_or_else(|| Rejection::UnknownExtension(ext.to_owned()))
}

/// Every convertible file under `dir`, depth first, files before
/// subdirectories, each level in name order. Files docling.rs does not read
/// are skipped silently: a folder drop is a request for what can be
/// converted, not a report on what cannot.
pub fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        let mut entries: Vec<_> = entries.flatten().map(|e| e.path()).collect();
        entries.sort();
        let (dirs, files): (Vec<_>, Vec<_>) = entries.into_iter().partition(|p| p.is_dir());
        found.extend(files.into_iter().filter(|p| detect(p).is_ok()));
        // Pushed in reverse so that popping visits them in name order.
        stack.extend(dirs.into_iter().rev());
    }
    found
}

/// The conversion thread. One per application; it owns the converter and the
/// warm PDF pipeline, so the models load once per session rather than once
/// per file. Dropping the worker closes the request channel and the thread
/// finishes its current job and exits.
pub struct Worker {
    requests: Sender<Request>,
    events: Receiver<Event>,
}

impl Worker {
    /// `wake` is called after every event is sent, so a window can ask for a
    /// repaint; it must be cheap and must not block.
    pub fn spawn(wake: impl Fn() + Send + Sync + 'static) -> Self {
        let (requests, request_rx) = mpsc::channel::<Request>();
        let (event_tx, events) = mpsc::channel::<Event>();
        thread::Builder::new()
            .name("duckling-convert".into())
            .spawn(move || run(request_rx, event_tx, wake))
            .expect("spawning the conversion thread");
        Worker { requests, events }
    }

    pub fn submit(&self, request: Request) {
        // A send fails only if the thread is gone, and then there is nobody
        // to tell; the window learns it from the silence.
        let _ = self.requests.send(request);
    }

    /// Every event that has arrived since the last call.
    pub fn poll(&self) -> Vec<Event> {
        self.events.try_iter().collect()
    }
}

fn run(
    requests: Receiver<Request>,
    events: Sender<Event>,
    wake: impl Fn() + Send + Sync + 'static,
) {
    let wake: Arc<dyn Fn() + Send + Sync> = Arc::new(wake);
    let mut engine = Engine::default();
    for request in requests {
        let id = request.id;
        let _ = events.send(Event::Started(id));
        wake();
        let progress = {
            let events = events.clone();
            let wake = Arc::clone(&wake);
            move |done: usize, total: usize| {
                let _ = events.send(Event::Progress {
                    id,
                    pages_done: done,
                    pages_total: total,
                });
                wake();
            }
        };
        let result = engine.convert(&request, progress);
        let _ = events.send(Event::Finished(id, result));
        wake();
    }
}

/// The converter and the PDF pipeline, created on first use so that a session
/// converting only Word files never loads a model.
#[derive(Default)]
struct Engine {
    converter: Option<DocumentConverter>,
    pipeline: Option<Pipeline>,
}

impl Engine {
    fn convert(
        &mut self,
        request: &Request,
        progress: impl Fn(usize, usize) + Send + Sync + 'static,
    ) -> Result<Outcome, String> {
        let format = detect(&request.source).map_err(|r| r.to_string())?;
        let bytes = std::fs::read(&request.source).map_err(|e| format!("cannot read: {e}"))?;
        let name = request
            .source
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "document".into());

        // A backend that panics on a malformed file takes the job down, not
        // the application. The engine is rebuilt afterwards because a panic
        // may have left the pipeline's shared state poisoned.
        let converted = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.document(format, &request.source, bytes, &name, progress)
        }));
        let (document, status) = match converted {
            Ok(Ok(pair)) => pair,
            Ok(Err(e)) => return Err(e),
            Err(panic) => {
                *self = Engine::default();
                let what = panic
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_else(|| "unknown panic".into());
                return Err(format!("the converter failed on this file: {what}"));
            }
        };

        let (bytes, preview_source) = render(&document, request.format);
        let target = available_path(&request.destination.target(&request.source, request.format));
        write_atomically(&target, &bytes)
            .map_err(|e| format!("cannot write {}: {e}", target.display()))?;

        let (preview, preview_truncated) = cap_preview(preview_source);
        Ok(Outcome {
            output: target,
            status,
            preview,
            preview_truncated,
        })
    }

    fn document(
        &mut self,
        format: InputFormat,
        path: &Path,
        bytes: Vec<u8>,
        name: &str,
        progress: impl Fn(usize, usize) + Send + Sync + 'static,
    ) -> Result<(DoclingDocument, ConversionStatus), String> {
        match format {
            InputFormat::Pdf => {
                let pipeline = self.pipeline()?;
                pipeline.set_progress(Some(Arc::new(progress)));
                let result = pipeline.convert(&bytes, None, name);
                pipeline.set_progress(None);
                result
                    .map(|doc| (doc, ConversionStatus::Success))
                    .map_err(|e| e.to_string())
            }
            InputFormat::Image => self
                .pipeline()?
                .convert_image(&bytes, name)
                .map(|doc| (doc, ConversionStatus::Success))
                .map_err(|e| e.to_string()),
            _ => {
                let mut source = SourceDocument::from_bytes(name, format, bytes);
                source.path = Some(path.to_path_buf());
                let converter = self.converter.get_or_insert_with(DocumentConverter::new);
                converter
                    .convert(source)
                    .map(|r| (r.document, r.status))
                    .map_err(|e| e.to_string())
            }
        }
    }

    fn pipeline(&mut self) -> Result<&mut Pipeline, String> {
        if self.pipeline.is_none() {
            self.pipeline = Some(Pipeline::new().map_err(|e| e.to_string())?);
        }
        Ok(self.pipeline.as_mut().expect("just set"))
    }
}

/// The bytes to write, and the text to preview.
fn render(document: &DoclingDocument, format: OutputFormat) -> (Vec<u8>, String) {
    match format {
        OutputFormat::Markdown => {
            let text = document.export_to_markdown();
            (text.clone().into_bytes(), text)
        }
        OutputFormat::Json => {
            let text = document.export_to_json();
            (text.clone().into_bytes(), text)
        }
        OutputFormat::Latex => {
            let text = document.export_to_latex();
            (text.clone().into_bytes(), text)
        }
        OutputFormat::Doclang => {
            let text = format!("{}\n", document.export_to_doclang());
            (text.clone().into_bytes(), text)
        }
        OutputFormat::DoclangArchive => (
            docling::dclx::to_dclx_bytes(document),
            document.export_to_doclang(),
        ),
    }
}

fn cap_preview(text: String) -> (String, bool) {
    if text.len() <= PREVIEW_CAP {
        return (text, false);
    }
    let mut end = PREVIEW_CAP;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    (text[..end].to_owned(), true)
}

/// Write beside the target and rename into place, so a crash mid-write leaves
/// no half file under the final name.
fn write_atomically(target: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut part = target.as_os_str().to_os_string();
    part.push(".part");
    let part = PathBuf::from(part);
    std::fs::write(&part, bytes)?;
    std::fs::rename(&part, target).inspect_err(|_| {
        let _ = std::fs::remove_file(&part);
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn beside_source_swaps_the_extension() {
        let target =
            Destination::BesideSource.target(Path::new("/a/b/report.pdf"), OutputFormat::Markdown);
        assert_eq!(target, PathBuf::from("/a/b/report.md"));
    }

    #[test]
    fn folder_keeps_the_stem() {
        let folder = Destination::Folder("/out".into());
        let source = Path::new("/a/b/report.pdf");
        assert_eq!(
            folder.target(source, OutputFormat::Doclang),
            PathBuf::from("/out/report.dclg")
        );
        assert_eq!(
            folder.target(source, OutputFormat::DoclangArchive),
            PathBuf::from("/out/report.dclx")
        );
    }

    #[test]
    fn a_taken_name_gets_a_number() {
        let dir = std::env::temp_dir().join(format!("duckling-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let first = dir.join("report.md");
        std::fs::write(&first, "x").unwrap();
        assert_eq!(available_path(&first), dir.join("report (1).md"));
        std::fs::write(dir.join("report (1).md"), "x").unwrap();
        assert_eq!(available_path(&first), dir.join("report (2).md"));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn markdown_to_markdown_never_overwrites_the_source() {
        let dir = std::env::temp_dir().join(format!("duckling-test-src-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let source = dir.join("notes.md");
        std::fs::write(&source, "# hi").unwrap();
        let target =
            available_path(&Destination::BesideSource.target(&source, OutputFormat::Markdown));
        assert_ne!(target, source);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn walk_yields_files_in_name_order_then_subfolders() {
        let dir = std::env::temp_dir().join(format!("duckling-test-walk-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("b-sub")).unwrap();
        std::fs::create_dir_all(dir.join("a-sub")).unwrap();
        for name in ["z.md", "a.docx", "skip.exe", "b-sub/n.pdf", "a-sub/m.html"] {
            std::fs::write(dir.join(name), "x").unwrap();
        }
        let names: Vec<String> = walk(&dir)
            .iter()
            .map(|p| {
                p.strip_prefix(&dir)
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/")
            })
            .collect();
        assert_eq!(names, ["a.docx", "z.md", "a-sub/m.html", "b-sub/n.pdf"]);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn detection_follows_the_extension() {
        assert_eq!(detect(Path::new("x.docx")), Ok(InputFormat::Docx));
        assert_eq!(detect(Path::new("x")), Err(Rejection::NoExtension));
        assert!(matches!(
            detect(Path::new("x.exe")),
            Err(Rejection::UnknownExtension(_))
        ));
    }

    #[test]
    fn preview_cap_respects_char_boundaries() {
        let text = "é".repeat(PREVIEW_CAP);
        let (preview, truncated) = cap_preview(text);
        assert!(truncated);
        assert!(preview.len() <= PREVIEW_CAP);
        assert!(preview.chars().all(|c| c == 'é'));
    }
}
