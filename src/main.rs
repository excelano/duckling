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

mod system_theme;

use std::path::{Path, PathBuf};

use duckling::{
    detect, walk, Destination, Event, Job, JobId, JobState, OutputFormat, Rejection, Request,
    Worker,
};
use eframe::egui::{self, Align2, Color32, FontId, RichText};

/// Reverse-DNS on macOS, the desktop entry's basename on Linux, the window
/// class a Wayland compositor matches an icon against.
const APP_ID: &str = "duckling";

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_app_id(APP_ID)
            .with_title("Duckling")
            .with_inner_size([1100.0, 700.0])
            .with_min_inner_size([720.0, 420.0]),
        ..Default::default()
    };
    let paths: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    // Before any thread exists; see the function's own comment.
    let models = duckling::locate_assets();
    eframe::run_native(
        "Duckling",
        options,
        Box::new(move |cc| {
            system_theme::follow(&cc.egui_ctx);
            let ctx = cc.egui_ctx.clone();
            let worker = Worker::spawn(move || ctx.request_repaint());
            let mut app = App::new(worker);
            if models.is_none() {
                app.status =
                    "No models found beside the application; PDFs and images will not convert"
                        .to_owned();
            }
            app.add_paths(&paths);
            Ok(Box::new(app))
        }),
    )
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
            (0, 0) => "Nothing to add".to_owned(),
            (n, 0) => format!("Added {n}"),
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
                format!(
                    "Added {n}; skipped {k} docling.rs does not read{}",
                    if exts.is_empty() {
                        String::new()
                    } else {
                        format!(" ({})", exts.join(", "))
                    }
                )
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
        let mut sent = 0usize;
        for job in self
            .jobs
            .iter()
            .filter(|j| matches!(j.state, JobState::Queued))
        {
            self.worker.submit(Request {
                id: job.id,
                source: job.source.clone(),
                format: self.format,
                destination: self.destination.clone(),
            });
            sent += 1;
        }
        self.status = format!("Converting {sent} to {}", self.format.label());
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
                    self.status = format!("Wrote {}", outcome.output.display());
                    self.set_state(id, JobState::Done(outcome));
                }
                Event::Finished(id, Err(message)) => {
                    if let Some(job) = self.jobs.iter().find(|j| j.id == id) {
                        self.status = format!("{}: {message}", job.file_name());
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
            if ui.button("Add files…").clicked() {
                self.pick_files();
            }
            if ui.button("Add folder…").clicked() {
                self.pick_folder_to_add();
            }
            ui.separator();
            ui.label("Convert to");
            egui::ComboBox::from_id_salt("format")
                .selected_text(self.format.label())
                .show_ui(ui, |ui| {
                    for format in OutputFormat::ALL {
                        ui.selectable_value(&mut self.format, format, format.label());
                    }
                });
            ui.separator();
            let beside = matches!(self.destination, Destination::BesideSource);
            if ui.radio(beside, "Beside each file").clicked() {
                self.destination = Destination::BesideSource;
            }
            if ui.radio(!beside, "Into a folder").clicked() {
                match &self.folder {
                    Some(dir) => self.destination = Destination::Folder(dir.clone()),
                    None => self.pick_destination_folder(),
                }
            }
            if let Destination::Folder(dir) = &self.destination {
                let shown = dir.display().to_string();
                if ui
                    .button(RichText::new(&shown).monospace())
                    .on_hover_text("Choose another folder")
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
            let convert = egui::Button::new(RichText::new("Convert").strong());
            if ui.add_enabled(queued > 0, convert).clicked() {
                self.convert_queued();
            }
            let finished = self
                .jobs
                .iter()
                .any(|j| matches!(j.state, JobState::Done(_) | JobState::Failed(_)));
            if ui
                .add_enabled(finished, egui::Button::new("Clear finished"))
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
                    RichText::new("Drop files or folders here, or use Add files.")
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
                        ui.label(RichText::new("File").strong());
                        ui.label(RichText::new("Read as").strong());
                        ui.label(RichText::new("Status").strong());
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
                                    ui.label(RichText::new("Queued").weak());
                                }
                                JobState::Converting {
                                    pages_done,
                                    pages_total,
                                } => {
                                    if *pages_total > 0 {
                                        let frac = *pages_done as f32 / *pages_total as f32;
                                        ui.add(
                                            egui::ProgressBar::new(frac).desired_width(160.0).text(
                                                format!("{pages_done} of {pages_total} pages"),
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
                                        RichText::new(format!("Wrote {name}"))
                                            .color(ui.visuals().strong_text_color()),
                                    );
                                }
                                JobState::Failed(message) => {
                                    ui.label(
                                        RichText::new("Failed").color(ui.visuals().error_fg_color),
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
                ui.label(RichText::new("Select a file to see its result.").weak());
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
                ui.label("Queued. Press Convert.");
            }
            JobState::Converting { .. } => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Converting…");
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
                    if ui.button("Open").clicked() {
                        if let Err(e) = opener::open(&output) {
                            self.status = format!("Could not open: {e}");
                        }
                    }
                    if ui.button("Show in folder").clicked() {
                        if let Err(e) = opener::reveal(&output) {
                            self.status = format!("Could not show: {e}");
                        }
                    }
                    if outcome.status == docling::ConversionStatus::PartialSuccess {
                        ui.label(
                            RichText::new("Converted with parts skipped")
                                .color(ui.visuals().warn_fg_color),
                        );
                    }
                });
                if outcome.preview_truncated {
                    ui.label(
                        RichText::new("Preview shows the beginning; the file has the rest.")
                            .weak()
                            .small(),
                    );
                }
                if !self.format_of(&output).is_text() {
                    ui.label(RichText::new("The archive's document.xml:").weak().small());
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
                RichText::new(format!(
                    "{queued} queued · {converting} converting · {done} done · {failed} failed"
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
                "Drop to add",
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
