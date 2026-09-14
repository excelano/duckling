//! Duckling's job model: what to convert, into what, where to, and the worker
//! that does it. Nothing in this file knows about a window. The application
//! in `main.rs` renders `Job`s and sends `Request`s; if a native front-end
//! ever replaces the egui one, this is what it talks to.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

#![forbid(unsafe_code)]

pub mod doclang;

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;
use std::thread;

/// docling.rs's own name for what a file reads as. Re-exported because it is
/// in this crate's public surface — [`Job::format`], [`common_input`] and
/// [`OutputFormat::sibling_input`] all speak it.
pub use docling::InputFormat;
use docling::{ConversionStatus, DoclingDocument, DocumentConverter, Pipeline, SourceDocument};

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
/// A Mac bundle is the one layout where "beside" is not a directory the
/// package may fill. `codesign` treats everything under `Contents/MacOS` as
/// code to be signed, so 613 MB of model weights cannot sit there, and a
/// shared library the Store will accept has to be nested code under
/// `Contents/Frameworks`. So the second place looked is the bundle's:
/// `../Resources/models` and `../Frameworks`, where `build-app.sh` puts them.
/// docling.rs takes the pdfium variable as a directory holding the library
/// under its platform name, which `Frameworks/libpdfium.dylib` is.
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
    let flat = (beside.join("models"), beside.join("pdfium"));
    let bundle = beside.parent().map(|contents| {
        (
            contents.join("Resources").join("models"),
            contents.join("Frameworks"),
        )
    });
    let (models, pdfium) = if flat.0.is_dir() {
        flat
    } else {
        bundle.filter(|(models, _)| models.is_dir())?
    };
    // Edition 2021: `set_var` is a safe function, and no other thread exists
    // yet to observe the environment changing under it.
    std::env::set_var("DOCLING_RS_MODELS_DIR", &models);
    if pdfium.is_dir() && std::env::var_os("PDFIUM_DYNAMIC_LIB_PATH").is_none() {
        std::env::set_var("PDFIUM_DYNAMIC_LIB_PATH", &pdfium);
    }
    Some(models)
}

/// Whether this process may create a file in `dir` right now, learnt by
/// creating one and removing it.
///
/// Asked before a conversion is sent to be written beside its source, and
/// asked at all because of the macOS sandbox: a file a person drops or picks
/// on its own is granted on its own, and its folder is not, so the write
/// beside it fails after the conversion rather than before. A folder a
/// person dropped or picked is granted whole. The probe is the write the
/// conversion is about to make, one directory entry long, under a name
/// nothing else uses and with `create_new` so it can never touch a file that
/// exists. Anything that stops the probe stops the conversion, so a `false`
/// here is a `false` however it came about.
pub fn can_write_in(dir: &Path) -> bool {
    let probe = dir.join(format!(".duckling-probe-{}", std::process::id()));
    let created = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
        .is_ok();
    if created {
        let _ = std::fs::remove_file(&probe);
    }
    created
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
    /// OpenDocument Text, written by waddle from the document docling.rs read.
    Odt,
    /// OpenDocument Spreadsheet, one sheet per table. Offered for a queue of
    /// XLSX and nothing else; see [`OutputFormat::sibling_input`].
    Ods,
    /// OpenDocument Presentation, a slide per level-1 heading. Offered for a
    /// queue of PPTX.
    Odp,
    /// Word, written by waddle from the same document.
    Docx,
    /// Excel, the OOXML twin of [`OutputFormat::Ods`]. Offered for a queue of
    /// ODS.
    Xlsx,
}

impl OutputFormat {
    /// Every format, in the order the picker shows them: the ODF family
    /// together, then the OOXML pair, so a sibling conversion appears beside
    /// its own ecosystem rather than at the end.
    pub const ALL: [OutputFormat; 10] = [
        OutputFormat::Doclang,
        OutputFormat::Markdown,
        OutputFormat::Json,
        OutputFormat::DoclangArchive,
        OutputFormat::Latex,
        OutputFormat::Odt,
        OutputFormat::Ods,
        OutputFormat::Odp,
        OutputFormat::Docx,
        OutputFormat::Xlsx,
    ];

    pub fn label(self) -> &'static str {
        match self {
            OutputFormat::Doclang => "DocLang",
            OutputFormat::Markdown => "Markdown",
            OutputFormat::Json => "JSON",
            OutputFormat::DoclangArchive => "DocLang archive",
            OutputFormat::Latex => "LaTeX",
            OutputFormat::Odt => "ODT",
            OutputFormat::Ods => "ODS",
            OutputFormat::Odp => "ODP",
            OutputFormat::Docx => "DOCX",
            OutputFormat::Xlsx => "XLSX",
        }
    }

    pub fn extension(self) -> &'static str {
        match self {
            OutputFormat::Doclang => "dclg",
            OutputFormat::Markdown => "md",
            OutputFormat::Json => "json",
            OutputFormat::DoclangArchive => "dclx",
            OutputFormat::Latex => "tex",
            OutputFormat::Odt => "odt",
            OutputFormat::Ods => "ods",
            OutputFormat::Odp => "odp",
            OutputFormat::Docx => "docx",
            OutputFormat::Xlsx => "xlsx",
        }
    }

    /// What the preview shows for a format that is not text, said above it.
    pub fn preview_note(self) -> Option<&'static str> {
        match self {
            OutputFormat::DoclangArchive => Some("The archive's document.xml:"),
            OutputFormat::Odt
            | OutputFormat::Ods
            | OutputFormat::Odp
            | OutputFormat::Docx
            | OutputFormat::Xlsx => {
                Some("The document as Markdown; the package holds it as written:")
            }
            OutputFormat::Doclang
            | OutputFormat::Markdown
            | OutputFormat::Json
            | OutputFormat::Latex => None,
        }
    }

    /// The one input format this output is a sibling conversion of: the same
    /// document in the other office ecosystem. `None` for the formats offered
    /// whatever the queue holds.
    ///
    /// Exhaustive on purpose. A format added later has to answer this
    /// question rather than fall through to "always offered".
    pub const fn sibling_input(self) -> Option<InputFormat> {
        match self {
            OutputFormat::Doclang
            | OutputFormat::Markdown
            | OutputFormat::Json
            | OutputFormat::DoclangArchive
            | OutputFormat::Latex
            | OutputFormat::Odt
            | OutputFormat::Docx => None,
            OutputFormat::Ods => Some(InputFormat::Xlsx),
            OutputFormat::Xlsx => Some(InputFormat::Ods),
            // The slide leg is one-way: waddle writes ODP and no PPTX.
            OutputFormat::Odp => Some(InputFormat::Pptx),
        }
    }

    /// Whether the picker may offer this format for a queue that reads as
    /// `queue`, which is [`common_input`]'s answer. A sibling needs a queue
    /// that is not empty and whose every file is its input format.
    ///
    /// An affordance in the picker and never a check in the engine:
    /// [`Engine`] converts whatever a [`Request`] asks for, which is what
    /// lets the tests ask for combinations the window would not offer.
    pub fn offered_for(self, queue: Option<InputFormat>) -> bool {
        match self.sibling_input() {
            None => true,
            Some(needed) => queue == Some(needed),
        }
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
    /// What the conversion could not do as well as it wanted, in words a
    /// person can act on. Empty when nothing was lost.
    pub notes: Vec<String>,
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

/// The one format every file in the queue reads as, when the queue is not
/// empty and they all agree; `None` for an empty or a mixed queue.
///
/// Every job counts whatever state it is in: a batch that has finished
/// converting is still a queue of spreadsheets, and the picker should not
/// change under a person because the work completed.
pub fn common_input(jobs: &[Job]) -> Option<InputFormat> {
    let mut all = jobs.iter().map(|job| job.format);
    let first = all.next()?;
    all.all(|format| format == first).then_some(first)
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
            self.document(format, &request.source, &bytes, &name, progress)
        }));
        let (mut document, status) = match converted {
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

        let mut notes = Vec::new();
        let rendered = match request.format {
            OutputFormat::Doclang | OutputFormat::DoclangArchive => {
                doclang::insert_page_breaks(&mut document);
                let xml = document.export_to_doclang();
                let assets = doclang::assets(&document, &xml);
                if request.format == OutputFormat::Doclang {
                    let text = format!("{xml}\n");
                    Rendered {
                        bytes: text.clone().into_bytes(),
                        preview: text,
                        beside: assets,
                    }
                } else {
                    let pages = match self.page_images(format, &bytes) {
                        Ok(pages) => pages,
                        Err(e) => {
                            notes.push(format!("No page images in the archive: {e}"));
                            Vec::new()
                        }
                    };
                    Rendered {
                        bytes: doclang::archive(&xml, &pages, &assets),
                        preview: xml,
                        beside: Vec::new(),
                    }
                }
            }
            OutputFormat::Odt
            | OutputFormat::Ods
            | OutputFormat::Odp
            | OutputFormat::Docx
            | OutputFormat::Xlsx => {
                let written = match request.format {
                    OutputFormat::Odt => waddle_core::odt::write(&document),
                    OutputFormat::Ods => waddle_core::ods::write(&document),
                    OutputFormat::Odp => waddle_core::odp::write(&document),
                    OutputFormat::Docx => waddle_core::docx::write(&document),
                    OutputFormat::Xlsx => waddle_core::xlsx::write(&document),
                    other => unreachable!("{other:?} is not a waddle target"),
                }
                .map_err(|e| e.to_string())?;
                // What the package could not carry, one line per kind with a
                // count, in waddle's own words.
                let mut kinds: Vec<(String, usize)> = Vec::new();
                for warning in &written.warnings {
                    let line = warning.to_string();
                    match kinds.iter_mut().find(|(l, _)| *l == line) {
                        Some((_, n)) => *n += 1,
                        None => kinds.push((line, 1)),
                    }
                }
                for (line, count) in kinds {
                    notes.push(if count > 1 {
                        format!("Not carried into the package: {line} ({count})")
                    } else {
                        format!("Not carried into the package: {line}")
                    });
                }
                Rendered {
                    bytes: written.bytes,
                    preview: document.export_to_markdown(),
                    beside: Vec::new(),
                }
            }
            other => render(&document, other),
        };
        let target = available_path(&request.destination.target(&request.source, request.format));
        // Assets first, so that a document that names them never exists
        // without them. Content-addressed names, so an existing file of the
        // same name holds the same bytes and overwriting it changes nothing.
        if let Some(dir) = target.parent() {
            for (name, bytes) in &rendered.beside {
                let path = dir.join(name);
                if let Some(parent) = path.parent() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| format!("cannot create {}: {e}", parent.display()))?;
                }
                std::fs::write(&path, bytes)
                    .map_err(|e| format!("cannot write {}: {e}", path.display()))?;
            }
        }
        write_atomically(&target, &rendered.bytes)
            .map_err(|e| format!("cannot write {}: {e}", target.display()))?;

        let (preview, preview_truncated) = cap_preview(rendered.preview);
        Ok(Outcome {
            output: target,
            status,
            preview,
            preview_truncated,
            notes,
        })
    }

    /// One PNG per page, for the archive. A PDF is rendered through pdfium at
    /// the pipeline's own scale, on this thread, which is the only thread
    /// that touches pdfium. An image is its own single page.
    fn page_images(&mut self, format: InputFormat, bytes: &[u8]) -> Result<doclang::Pages, String> {
        match format {
            InputFormat::Pdf => docling::render_pdf_pages(bytes, None, None, 2.0)
                .map(|pages| pages.into_iter().map(|p| p.png).collect())
                .map_err(|e| e.to_string()),
            InputFormat::Image => doclang::as_png(bytes)
                .map(|png| vec![png])
                .ok_or_else(|| "the image could not be decoded".to_owned()),
            _ => Ok(Vec::new()),
        }
    }

    fn document(
        &mut self,
        format: InputFormat,
        path: &Path,
        bytes: &[u8],
        name: &str,
        progress: impl Fn(usize, usize) + Send + Sync + 'static,
    ) -> Result<(DoclingDocument, ConversionStatus), String> {
        match format {
            InputFormat::Pdf => {
                let pipeline = self.pipeline()?;
                pipeline.set_progress(Some(Arc::new(progress)));
                let result = pipeline.convert(bytes, None, name);
                pipeline.set_progress(None);
                result
                    .map(|doc| (doc, ConversionStatus::Success))
                    .map_err(|e| e.to_string())
            }
            InputFormat::Image => self
                .pipeline()?
                .convert_image(bytes, name)
                .map(|doc| (doc, ConversionStatus::Success))
                .map_err(|e| e.to_string()),
            _ => {
                let mut source = SourceDocument::from_bytes(name, format, bytes.to_vec());
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

/// What a conversion produced: the file, its preview, and any files that
/// belong beside it (a bare DocLang's `assets/`).
struct Rendered {
    bytes: Vec<u8>,
    preview: String,
    beside: Vec<(String, Vec<u8>)>,
}

/// The text formats. DocLang in both spellings is rendered in `convert`,
/// because it needs the source bytes for page images.
fn render(document: &DoclingDocument, format: OutputFormat) -> Rendered {
    let text = match format {
        OutputFormat::Markdown => document.export_to_markdown(),
        OutputFormat::Json => document.export_to_json(),
        OutputFormat::Latex => document.export_to_latex(),
        OutputFormat::Doclang
        | OutputFormat::DoclangArchive
        | OutputFormat::Odt
        | OutputFormat::Ods
        | OutputFormat::Odp
        | OutputFormat::Docx
        | OutputFormat::Xlsx => {
            unreachable!("DocLang and the office packages are rendered in Engine::convert")
        }
    };
    Rendered {
        bytes: text.clone().into_bytes(),
        preview: text,
        beside: Vec::new(),
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

    fn job(id: u64, format: InputFormat, state: JobState) -> Job {
        Job {
            id: JobId(id),
            source: PathBuf::from(format!("/a/{id}.x")),
            format,
            state,
        }
    }

    #[test]
    fn only_the_three_sibling_conversions_name_an_input() {
        assert_eq!(OutputFormat::Ods.sibling_input(), Some(InputFormat::Xlsx));
        assert_eq!(OutputFormat::Xlsx.sibling_input(), Some(InputFormat::Ods));
        assert_eq!(OutputFormat::Odp.sibling_input(), Some(InputFormat::Pptx));
        let named = OutputFormat::ALL
            .into_iter()
            .filter(|f| f.sibling_input().is_some())
            .count();
        assert_eq!(named, 3, "only the siblings depend on the queue");
    }

    #[test]
    fn the_default_format_is_always_offered() {
        // What `revalidate_format` falls back to has to be legal for any
        // queue, or the fallback could not settle.
        assert_eq!(OutputFormat::default().sibling_input(), None);
        assert!(OutputFormat::default().offered_for(None));
    }

    #[test]
    fn the_queue_reads_as_one_format_only_when_they_all_agree() {
        assert_eq!(common_input(&[]), None);
        assert_eq!(
            common_input(&[job(1, InputFormat::Xlsx, JobState::Queued)]),
            Some(InputFormat::Xlsx)
        );
        assert_eq!(
            common_input(&[
                job(1, InputFormat::Xlsx, JobState::Queued),
                job(
                    2,
                    InputFormat::Xlsx,
                    JobState::Converting {
                        pages_done: 0,
                        pages_total: 0,
                    },
                ),
            ]),
            Some(InputFormat::Xlsx)
        );
        assert_eq!(
            common_input(&[
                job(1, InputFormat::Xlsx, JobState::Queued),
                job(2, InputFormat::Pdf, JobState::Queued),
            ]),
            None,
            "a mixed queue reads as nothing"
        );
    }

    #[test]
    fn a_finished_queue_still_reads_as_what_it_holds() {
        // The picker must not change under somebody because the work ended.
        let done = [
            job(1, InputFormat::Pptx, JobState::Failed("no".into())),
            job(
                2,
                InputFormat::Pptx,
                JobState::Converting {
                    pages_done: 3,
                    pages_total: 3,
                },
            ),
        ];
        assert_eq!(common_input(&done), Some(InputFormat::Pptx));
        assert!(OutputFormat::Odp.offered_for(common_input(&done)));
    }

    #[test]
    fn a_queue_offers_the_seven_plus_its_own_sibling() {
        let offered = |jobs: &[Job]| -> Vec<OutputFormat> {
            let queue = common_input(jobs);
            OutputFormat::ALL
                .into_iter()
                .filter(|f| f.offered_for(queue))
                .collect()
        };
        assert_eq!(offered(&[]).len(), 7, "an empty queue offers the seven");
        let xlsx = [job(1, InputFormat::Xlsx, JobState::Queued)];
        assert!(offered(&xlsx).contains(&OutputFormat::Ods));
        assert!(!offered(&xlsx).contains(&OutputFormat::Xlsx));
        assert!(!offered(&xlsx).contains(&OutputFormat::Odp));
        let ods = [job(1, InputFormat::Ods, JobState::Queued)];
        assert!(offered(&ods).contains(&OutputFormat::Xlsx));
        let pptx = [job(1, InputFormat::Pptx, JobState::Queued)];
        assert!(offered(&pptx).contains(&OutputFormat::Odp));
        let mixed = [
            job(1, InputFormat::Xlsx, JobState::Queued),
            job(2, InputFormat::Pdf, JobState::Queued),
        ];
        assert_eq!(offered(&mixed).len(), 7);
    }

    #[test]
    fn every_format_is_in_all_and_owns_its_extension() {
        // `App::format_of` maps a finished file back by extension, so a
        // collision would give a row the wrong preview note.
        assert_eq!(OutputFormat::ALL.len(), 10);
        for (i, a) in OutputFormat::ALL.iter().enumerate() {
            for b in &OutputFormat::ALL[i + 1..] {
                assert_ne!(a.extension(), b.extension(), "{a:?} and {b:?} collide");
                assert_ne!(a, b, "{a:?} is in ALL twice");
            }
        }
    }

    #[test]
    fn the_new_packages_take_their_own_extension() {
        for (format, name) in [
            (OutputFormat::Ods, "/a/b/report.ods"),
            (OutputFormat::Odp, "/a/b/report.odp"),
            (OutputFormat::Xlsx, "/a/b/report.xlsx"),
        ] {
            let target = Destination::BesideSource.target(Path::new("/a/b/report.pdf"), format);
            assert_eq!(target, PathBuf::from(name));
        }
    }

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
    fn the_write_probe_leaves_nothing_behind() {
        let dir = std::env::temp_dir().join(format!("duckling-test-probe-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(can_write_in(&dir));
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
        assert!(!can_write_in(&dir.join("absent")));
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
