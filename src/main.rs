//! Duckling, the window. Presented to a person as **Duckling**; the crate and
//! the binary are `duckling`.
//!
//! One window: a toolbar that says what to convert into and where, a queue
//! that says what is being converted and how it went, and a preview of the
//! selected result. Everything the window shows is a `Job` from the library
//! and everything it does is a `Request` to the worker; the window holds no
//! conversion state of its own.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

#![deny(unsafe_code)]
// Without this, Windows gives a GUI application a console window behind it,
// which a file manager launching Duckling would put on the screen. The
// certification kit does not object and a person does, and
// `packaging/windows/build-msix.ps1` refuses a binary that lacks it rather than
// wait to be told again. The attribute is ignored everywhere else, and it is
// off in a debug build because that is where a panic message still has
// somewhere to go.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod system_theme;

/// The messages this window draws, in the language the desktop asks for.
///
/// Declared here and not in `src/lib.rs`, because every sentence a person
/// reads is produced in this file: the library holds the queue, the worker and
/// the output rules, and says nothing to anybody.
mod i18n {
    potext::catalog!();
}
use i18n::t;
use potext::fill;

/// Every language this application is translated into.
const CATALOGUES: &[(&str, &str)] = &[
    ("de", include_str!("../po/de.po")),
    // Debug builds alone, so a release carries nothing of it. `po/pseudo.sh`
    // says what it finds and why it is run before any German rather than after.
    #[cfg(debug_assertions)]
    ("en-x-pseudo", include_str!("../po/en-x-pseudo.po")),
];

use std::path::{Path, PathBuf};

use duckling::{
    detect, walk, Destination, Event, Job, JobId, JobState, OutputFormat, Rejection, Request,
    Worker,
};
use eframe::egui::{self, Align2, Color32, FontId, RichText};

/// Reverse-DNS on macOS, the desktop entry's basename on Linux, the window
/// class a Wayland compositor matches an icon against.
const APP_ID: &str = "duckling";

/// The window's icon on Windows, which has no `.desktop` entry to find one in.
///
/// `APP_ID` above is how Linux answers this question and it does nothing here:
/// `with_app_id` is Wayland's `xdg_toplevel.set_app_id`, and neither egui,
/// eframe nor winit turns it into anything on Windows. Windows takes a window's
/// icon from a resource compiled into the executable, and compiling one needs
/// `rc.exe` or `windres`, which `packaging/windows/README.md` keeps out of the
/// build. So the icon is carried as bytes and handed to the window at run time,
/// which needs no build step at all. slipcase-desktop measured all of this; the
/// file is built from the same drawing every platform's icon comes from.
#[cfg(target_os = "windows")]
const WINDOW_ICON: &[u8] = include_bytes!("../packaging/windows/duckling.ico");

/// The icon at the largest size the drawing carries without being upscaled.
///
/// A window gets one image and Windows scales it to 16 in the title bar and 32
/// in the task bar, doubling both at 200%. 64 is a whole multiple of those
/// four, so each is an integer downsample of the same drawing. It is not a
/// whole multiple of what the intermediate scalings ask for - 125% wants 20 and
/// 40, 150% wants 24 and 48 - and those are resampled; slipcase-desktop looked
/// at both and the cost is nothing a person notices, which is why 64 stays the
/// choice: it is the largest entry no scaling has to enlarge.
#[cfg(target_os = "windows")]
fn window_icon() -> Option<egui::IconData> {
    let directory = ico::IconDir::read(std::io::Cursor::new(WINDOW_ICON)).ok()?;
    let entry = directory.entries().iter().find(|e| e.width() == 64)?;
    let image = entry.decode().ok()?;
    Some(egui::IconData {
        rgba: image.rgba_data().to_vec(),
        width: image.width(),
        height: image.height(),
    })
}

/// What an output format is called in the language the window is drawn in.
///
/// `duckling::OutputFormat::label` stays the canonical English: it is the
/// library's name for a format and the library draws nothing. Most of these are
/// the names of formats and a name is not translated — a German window says
/// DOCX and JSON too — but they go through the catalogue anyway so that the one
/// with an ordinary noun in it, *DocLang archive*, can be German without a
/// special case, and so a translator decides rather than this function.
fn format_label(format: OutputFormat) -> &'static str {
    match format {
        OutputFormat::Doclang => t("DocLang"),
        OutputFormat::Markdown => t("Markdown"),
        OutputFormat::Json => t("JSON"),
        OutputFormat::DoclangArchive => t("DocLang archive"),
        OutputFormat::Latex => t("LaTeX"),
        OutputFormat::Odt => t("ODT"),
        OutputFormat::Docx => t("DOCX"),
    }
}

fn main() -> eframe::Result {
    // Before anything that could put a sentence in front of somebody, which
    // here includes the dialog at the bottom of this function: a window that
    // will not open has to say so in the language the desktop asked for.
    i18n::activate(CATALOGUES);

    let viewport = egui::ViewportBuilder::default()
        .with_app_id(APP_ID)
        .with_title("Duckling")
        .with_inner_size([1100.0, 700.0])
        .with_min_inner_size([720.0, 420.0]);

    // Shadowed rather than made mutable, so that no platform without an icon to
    // set carries an unused `mut`.
    #[cfg(target_os = "windows")]
    let viewport = match window_icon() {
        Some(icon) => viewport.with_icon(icon),
        None => viewport,
    };

    let options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };
    let paths: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    // Before any thread exists; see the function's own comment.
    let models = duckling::locate_assets();
    let result = eframe::run_native(
        "Duckling",
        options,
        Box::new(move |cc| {
            system_theme::follow(&cc.egui_ctx);
            let ctx = cc.egui_ctx.clone();
            let worker = Worker::spawn(move || ctx.request_repaint());
            let mut app = App::new(worker);
            if models.is_none() {
                app.status =
                    t("No models found beside the application; PDFs and images will not convert")
                        .to_owned();
            }
            app.add_paths(&paths);
            // The build `Cargo.toml` describes under `intel-mac`, and this is
            // the one place it shows: the models may well be there, and
            // nothing can run them. After the paths, so that it is what a
            // person sees rather than what the count overwrote.
            #[cfg(feature = "intel-mac")]
            {
                app.status =
                    t("Built without ONNX Runtime: PDFs and images will not convert").to_owned();
            }
            Ok(Box::new(app))
        }),
    );

    // **A window that fails to open must say so, and until 2026-09-05 this one
    // did not.** `windows_subsystem = "windows"` above means the process has no
    // console, so returning the error from `main` prints it to a stderr that
    // does not exist: the application starts, fails, and vanishes with nothing
    // on the screen and nothing in a log. David met exactly that on an old
    // Surface, and the report was "no error, just no app" - which is the worst
    // possible bug report to receive and was entirely our fault for making it
    // the only one available.
    //
    // `rfd` is already a dependency, for the Add files dialog, and its message
    // dialog needs no feature and no unsafe. It is used only here: every other
    // failure in this application has a row in the queue or the status line to
    // land in, and this is the one that happens before either exists.
    //
    // Printed as well as shown, because on Linux and macOS a terminal is often
    // where this is being read from, and a dialog there is the redundant half
    // rather than the useless one.
    if let Err(e) = &result {
        eprintln!("duckling: the window could not be opened: {e}");
        rfd::MessageDialog::new()
            .set_level(rfd::MessageLevel::Error)
            .set_title(t("Duckling could not start"))
            .set_description(fill(
                t("The window could not be opened.\n\n{reason}\n\nThis is usually a graphics driver the window system could not use. Duckling needs no particular graphics card, but it does need one the system can talk to."),
                &[("reason", &e.to_string())],
            ))
            .show();
    }
    result
}

struct App {
    worker: Worker,
    jobs: Vec<Job>,
    next_id: u64,
    format: OutputFormat,
    destination: Destination,
    /// The folder last chosen, kept when the destination switches back to
    /// beside-the-source so that switching again does not ask twice.
    folder: Option<PathBuf>,
    selected: Option<JobId>,
    status: String,
}

impl App {
    fn new(worker: Worker) -> Self {
        App {
            worker,
            jobs: Vec::new(),
            next_id: 1,
            format: OutputFormat::default(),
            destination: Destination::BesideSource,
            folder: None,
            selected: None,
            status: String::new(),
        }
    }

    /// Queue files, and the convertible files under folders. Paths that are
    /// already queued or converting are not queued twice; a finished one is,
    /// because asking again is how a person converts into a second format.
    fn add_paths(&mut self, paths: &[PathBuf]) {
        let mut added = 0usize;
        let mut rejected: Vec<Rejection> = Vec::new();
        for path in paths {
            if path.is_dir() {
                for file in walk(path) {
                    added += usize::from(self.add_file(&file));
                }
                continue;
            }
            match detect(path) {
                Ok(_) => added += usize::from(self.add_file(path)),
                Err(r) => rejected.push(r),
            }
        }
        self.status = match (added, rejected.len()) {
            (0, 0) => t("Nothing to add").to_owned(),
            (n, 0) => fill(t("Added {n}"), &[("n", &n.to_string())]),
            (n, k) => {
                let mut exts: Vec<String> = rejected
                    .iter()
                    .filter_map(|r| match r {
                        Rejection::UnknownExtension(e) => Some(format!(".{e}")),
                        Rejection::NoExtension => None,
                    })
                    .collect();
                exts.sort();
                exts.dedup();
                // Two whole sentences rather than a suffix spliced onto one:
                // a translator given a fragment cannot place it, and German
                // would not put the list where English does.
                if exts.is_empty() {
                    fill(
                        t("Added {n}; skipped {k} docling.rs does not read"),
                        &[("n", &n.to_string()), ("k", &k.to_string())],
                    )
                } else {
                    fill(
                        t("Added {n}; skipped {k} docling.rs does not read ({extensions})"),
                        &[
                            ("n", &n.to_string()),
                            ("k", &k.to_string()),
                            ("extensions", &exts.join(", ")),
                        ],
                    )
                }
            }
        };
    }

    fn add_file(&mut self, path: &Path) -> bool {
        let Ok(format) = detect(path) else {
            return false;
        };
        let pending = self.jobs.iter().any(|j| {
            j.source == path && matches!(j.state, JobState::Queued | JobState::Converting { .. })
        });
        if pending {
            return false;
        }
        let id = JobId(self.next_id);
        self.next_id += 1;
        self.jobs.push(Job {
            id,
            source: path.to_path_buf(),
            format,
            state: JobState::Queued,
        });
        if self.selected.is_none() {
            self.selected = Some(id);
        }
        true
    }

    fn convert_queued(&mut self) {
        #[cfg(target_os = "macos")]
        let withheld = self.folders_without_access();
        #[cfg(not(target_os = "macos"))]
        let withheld: Vec<PathBuf> = Vec::new();

        let mut sent = 0usize;
        let mut waiting = 0usize;
        for job in self
            .jobs
            .iter()
            .filter(|j| matches!(j.state, JobState::Queued))
        {
            if job
                .source
                .parent()
                .is_some_and(|dir| withheld.iter().any(|w| w == dir))
            {
                waiting += 1;
                continue;
            }
            self.worker.submit(Request {
                id: job.id,
                source: job.source.clone(),
                format: self.format,
                destination: self.destination.clone(),
            });
            sent += 1;
        }
        self.status = match (sent, waiting) {
            (_, 0) => fill(
                t("Converting {count} to {format}"),
                &[("count", &sent.to_string()), ("format", format_label(self.format))],
            ),
            (0, n) => fill(
                t("{n} left queued until their folder is allowed, or choose Into a folder"),
                &[("n", &n.to_string())],
            ),
            (_, n) => fill(
                t("Converting {count} to {format}; {n} left queued until their folder is allowed, or choose Into a folder"),
                &[
                    ("count", &sent.to_string()),
                    ("format", format_label(self.format)),
                    ("n", &n.to_string()),
                ],
            ),
        };
    }

    /// The folders of queued files that this process may not write into,
    /// after asking the person for each one once.
    ///
    /// The App Sandbox grants a file that was dropped or picked on its own,
    /// and not the folder around it, so a conversion written beside such a
    /// file fails at the write. A folder that was dropped or picked is
    /// granted whole and never reaches the panel. The panel is the sandbox's
    /// own way of extending a grant: choosing the folder in it makes the
    /// folder writable for the rest of the session. The person may choose
    /// somewhere else or cancel, and the probe is asked again afterwards
    /// rather than the answer trusted, so what comes back is what is still
    /// not writable and those files stay queued rather than fail.
    /// `DESIGN.md` §8 records the measurement this rests on.
    #[cfg(target_os = "macos")]
    fn folders_without_access(&mut self) -> Vec<PathBuf> {
        if !matches!(self.destination, Destination::BesideSource) {
            return Vec::new();
        }
        let mut folders: Vec<PathBuf> = self
            .jobs
            .iter()
            .filter(|j| matches!(j.state, JobState::Queued))
            .filter_map(|j| j.source.parent().map(Path::to_path_buf))
            .collect();
        folders.sort();
        folders.dedup();
        folders.retain(|dir| !duckling::can_write_in(dir));
        for dir in &folders {
            rfd::FileDialog::new()
                .set_title(fill(
                    t("Allow Duckling to write beside the files in {folder}: choose that folder"),
                    &[("folder", &dir.display().to_string())],
                ))
                .set_directory(dir)
                .set_can_create_directories(false)
                .pick_folder();
        }
        folders.retain(|dir| !duckling::can_write_in(dir));
        folders
    }

    fn apply_events(&mut self) {
        for event in self.worker.poll() {
            match event {
                Event::Started(id) => self.set_state(
                    id,
                    JobState::Converting {
                        pages_done: 0,
                        pages_total: 0,
                    },
                ),
                Event::Progress {
                    id,
                    pages_done,
                    pages_total,
                } => self.set_state(
                    id,
                    JobState::Converting {
                        pages_done,
                        pages_total,
                    },
                ),
                Event::Finished(id, Ok(outcome)) => {
                    self.status = fill(
                        t("Wrote {file}"),
                        &[("file", &outcome.output.display().to_string())],
                    );
                    self.set_state(id, JobState::Done(outcome));
                }
                Event::Finished(id, Err(message)) => {
                    if let Some(job) = self.jobs.iter().find(|j| j.id == id) {
                        self.status = fill(
                            t("{file}: {reason}"),
                            &[("file", &job.file_name()), ("reason", &message)],
                        );
                    }
                    self.set_state(id, JobState::Failed(message));
                }
            }
        }
    }

    fn set_state(&mut self, id: JobId, state: JobState) {
        if let Some(job) = self.jobs.iter_mut().find(|j| j.id == id) {
            job.state = state;
        }
    }

    fn pick_files(&mut self) {
        if let Some(paths) = rfd::FileDialog::new().pick_files() {
            self.add_paths(&paths);
        }
    }

    fn pick_folder_to_add(&mut self) {
        if let Some(dir) = rfd::FileDialog::new().pick_folder() {
            self.add_paths(&[dir]);
        }
    }

    fn pick_destination_folder(&mut self) {
        let mut dialog = rfd::FileDialog::new();
        if let Some(dir) = &self.folder {
            dialog = dialog.set_directory(dir);
        }
        if let Some(dir) = dialog.pick_folder() {
            self.folder = Some(dir.clone());
            self.destination = Destination::Folder(dir);
        }
    }

    fn toolbar(&mut self, ui: &mut egui::Ui) {
        ui.horizontal_wrapped(|ui| {
            if ui.button(t("Add files…")).clicked() {
                self.pick_files();
            }
            if ui.button(t("Add folder…")).clicked() {
                self.pick_folder_to_add();
            }
            ui.separator();
            ui.label(t("Convert to"));
            egui::ComboBox::from_id_salt("format")
                .selected_text(format_label(self.format))
                .show_ui(ui, |ui| {
                    for format in OutputFormat::ALL {
                        ui.selectable_value(&mut self.format, format, format_label(format));
                    }
                });
            ui.separator();
            let beside = matches!(self.destination, Destination::BesideSource);
            if ui.radio(beside, t("Beside each file")).clicked() {
                self.destination = Destination::BesideSource;
            }
            if ui.radio(!beside, t("Into a folder")).clicked() {
                match &self.folder {
                    Some(dir) => self.destination = Destination::Folder(dir.clone()),
                    None => self.pick_destination_folder(),
                }
            }
            if let Destination::Folder(dir) = &self.destination {
                let shown = dir.display().to_string();
                if ui
                    .button(RichText::new(&shown).monospace())
                    .on_hover_text(t("Choose another folder"))
                    .clicked()
                {
                    self.pick_destination_folder();
                }
            }
            ui.separator();
            let queued = self
                .jobs
                .iter()
                .filter(|j| matches!(j.state, JobState::Queued))
                .count();
            let convert = egui::Button::new(RichText::new(t("Convert")).strong());
            if ui.add_enabled(queued > 0, convert).clicked() {
                self.convert_queued();
            }
            let finished = self
                .jobs
                .iter()
                .any(|j| matches!(j.state, JobState::Done(_) | JobState::Failed(_)));
            if ui
                .add_enabled(finished, egui::Button::new(t("Clear finished")))
                .clicked()
            {
                self.jobs
                    .retain(|j| matches!(j.state, JobState::Queued | JobState::Converting { .. }));
                if self
                    .selected
                    .is_some_and(|id| !self.jobs.iter().any(|j| j.id == id))
                {
                    self.selected = self.jobs.first().map(|j| j.id);
                }
            }
        });
    }

    fn queue(&mut self, ui: &mut egui::Ui) {
        if self.jobs.is_empty() {
            ui.centered_and_justified(|ui| {
                ui.label(
                    RichText::new(t("Drop files or folders here, or use Add files."))
                        .size(18.0)
                        .weak(),
                );
            });
            return;
        }
        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                egui::Grid::new("jobs")
                    .num_columns(3)
                    .striped(true)
                    .spacing([16.0, 6.0])
                    .show(ui, |ui| {
                        ui.label(RichText::new(t("File")).strong());
                        ui.label(RichText::new(t("Read as")).strong());
                        ui.label(RichText::new(t("Status")).strong());
                        ui.end_row();
                        let mut select = None;
                        for job in &self.jobs {
                            let selected = self.selected == Some(job.id);
                            if ui
                                .selectable_label(selected, job.file_name())
                                .on_hover_text(job.source.display().to_string())
                                .clicked()
                            {
                                select = Some(job.id);
                            }
                            ui.label(job.format.as_str());
                            match &job.state {
                                JobState::Queued => {
                                    ui.label(RichText::new(t("Queued")).weak());
                                }
                                JobState::Converting {
                                    pages_done,
                                    pages_total,
                                } => {
                                    if *pages_total > 0 {
                                        let frac = *pages_done as f32 / *pages_total as f32;
                                        ui.add(
                                            egui::ProgressBar::new(frac).desired_width(160.0).text(
                                                fill(
                                                    t("{done} of {total} pages"),
                                                    &[
                                                        ("done", &pages_done.to_string()),
                                                        ("total", &pages_total.to_string()),
                                                    ],
                                                ),
                                            ),
                                        );
                                    } else {
                                        ui.spinner();
                                    }
                                }
                                JobState::Done(outcome) => {
                                    let name = outcome
                                        .output
                                        .file_name()
                                        .map(|n| n.to_string_lossy().into_owned())
                                        .unwrap_or_default();
                                    ui.label(
                                        RichText::new(fill(t("Wrote {file}"), &[("file", &name)]))
                                            .color(ui.visuals().strong_text_color()),
                                    );
                                }
                                JobState::Failed(message) => {
                                    ui.label(
                                        RichText::new(t("Failed"))
                                            .color(ui.visuals().error_fg_color),
                                    )
                                    .on_hover_text(message);
                                }
                            }
                            ui.end_row();
                        }
                        if let Some(id) = select {
                            self.selected = Some(id);
                        }
                    });
            });
    }

    fn preview(&mut self, ui: &mut egui::Ui) {
        let Some(job) = self
            .selected
            .and_then(|id| self.jobs.iter().find(|j| j.id == id))
        else {
            ui.centered_and_justified(|ui| {
                ui.label(RichText::new(t("Select a file to see its result.")).weak());
            });
            return;
        };
        ui.heading(job.file_name());
        ui.label(
            RichText::new(job.source.display().to_string())
                .weak()
                .small(),
        );
        ui.add_space(6.0);
        match &job.state {
            JobState::Queued => {
                ui.label(t("Queued. Press Convert."));
            }
            JobState::Converting { .. } => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label(t("Converting…"));
                });
            }
            JobState::Failed(message) => {
                ui.label(
                    RichText::new("Failed")
                        .color(ui.visuals().error_fg_color)
                        .strong(),
                );
                ui.label(message);
            }
            JobState::Done(outcome) => {
                let output = outcome.output.clone();
                ui.horizontal_wrapped(|ui| {
                    ui.label(RichText::new(output.display().to_string()).monospace());
                });
                ui.horizontal(|ui| {
                    if ui.button(t("Open")).clicked() {
                        if let Err(e) = opener::open(&output) {
                            self.status =
                                fill(t("Could not open: {reason}"), &[("reason", &e.to_string())]);
                        }
                    }
                    if ui.button(t("Show in folder")).clicked() {
                        if let Err(e) = opener::reveal(&output) {
                            self.status =
                                fill(t("Could not show: {reason}"), &[("reason", &e.to_string())]);
                        }
                    }
                    if outcome.status == docling::ConversionStatus::PartialSuccess {
                        ui.label(
                            RichText::new(t("Converted with parts skipped"))
                                .color(ui.visuals().warn_fg_color),
                        );
                    }
                });
                for note in &outcome.notes {
                    ui.label(RichText::new(note).color(ui.visuals().warn_fg_color));
                }
                if outcome.preview_truncated {
                    ui.label(
                        RichText::new(t("Preview shows the beginning; the file has the rest."))
                            .weak()
                            .small(),
                    );
                }
                if let Some(note) = self.format_of(&output).preview_note() {
                    ui.label(RichText::new(note).weak().small());
                }
                ui.add_space(4.0);
                egui::ScrollArea::both()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        let mut text = outcome.preview.as_str();
                        ui.add(
                            egui::TextEdit::multiline(&mut text)
                                .code_editor()
                                .desired_width(f32::INFINITY),
                        );
                    });
            }
        }
    }

    fn format_of(&self, output: &Path) -> OutputFormat {
        let ext = output
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or_default();
        OutputFormat::ALL
            .into_iter()
            .find(|f| f.extension() == ext)
            .unwrap_or(self.format)
    }

    fn status_bar(&self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            let count =
                |pred: fn(&JobState) -> bool| self.jobs.iter().filter(|j| pred(&j.state)).count();
            let queued = count(|s| matches!(s, JobState::Queued));
            let converting = count(|s| matches!(s, JobState::Converting { .. }));
            let done = count(|s| matches!(s, JobState::Done(_)));
            let failed = count(|s| matches!(s, JobState::Failed(_)));
            ui.label(
                RichText::new(fill(
                    t("{queued} queued · {converting} converting · {done} done · {failed} failed"),
                    &[
                        ("queued", &queued.to_string()),
                        ("converting", &converting.to_string()),
                        ("done", &done.to_string()),
                        ("failed", &failed.to_string()),
                    ],
                ))
                .weak(),
            );
            ui.separator();
            ui.label(&self.status);
        });
    }

    fn drops(&mut self, ctx: &egui::Context) {
        let hovering = ctx.input(|i| !i.raw.hovered_files.is_empty());
        if hovering {
            let rect = ctx.content_rect();
            let painter = ctx.layer_painter(egui::LayerId::new(
                egui::Order::Foreground,
                egui::Id::new("drop"),
            ));
            painter.rect_filled(rect, 0.0, Color32::from_black_alpha(110));
            painter.text(
                rect.center(),
                Align2::CENTER_CENTER,
                t("Drop to add"),
                FontId::proportional(28.0),
                Color32::WHITE,
            );
        }
        let dropped: Vec<PathBuf> = ctx.input(|i| {
            i.raw
                .dropped_files
                .iter()
                .map(|f| f.path().to_path_buf())
                .collect()
        });
        if !dropped.is_empty() {
            self.add_paths(&dropped);
        }
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        self.apply_events();
        // egui 0.36 folded `TopBottomPanel` and `SidePanel` into one `Panel`.
        egui::Panel::top("toolbar").show(ui, |ui| {
            ui.add_space(4.0);
            self.toolbar(ui);
            ui.add_space(4.0);
        });
        egui::Panel::bottom("status").show(ui, |ui| self.status_bar(ui));
        egui::Panel::right("preview")
            .resizable(true)
            .default_size(460.0)
            .show(ui, |ui| self.preview(ui));
        egui::CentralPanel::default().show(ui, |ui| self.queue(ui));
        self.drops(&ctx);
    }
}
