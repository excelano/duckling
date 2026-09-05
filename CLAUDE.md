# CLAUDE.md

Guidance for Claude Code working in `duckling`. Short because `DESIGN.md` is
where the reasoning lives; read that before touching anything.

---

## What this is

A desktop application that converts documents with docling.rs. Presented to a
person as **Duckling**; the crate and the binary are `duckling`. One window:
a queue, a format and destination, a Convert button, a preview of the result.

**It converts nothing itself.** Every conversion is `docling`'s. Where
behaviour is missing, it goes upstream as an issue, the way slipcase-desktop
did with `slpc`, rather than being worked around here.

**Three documents, three authorities.** docling.rs's `README.md` and
`docs/MIGRATION.md` are the authority on what converts and how well.
`DESIGN.md` here is the authority on this application. `git log` is the record
of why everything is the way it is, and it is written to be read.

A clone of docling.rs is at `~/clones/docling.rs` on David's machine; its
`tests/data/<format>/sources/` is the corpus the end-to-end tests draw on.

---

## Commands

    ./packaging/fetch-models.sh               # once, pinned, idempotent
    cargo build
    cargo test                                # unit tests; the end-to-end
                                              # tests skip without the corpus
    cargo clippy --all-targets -- -D warnings # must be silent
    cargo fmt --check
    cargo run -- [FILE|FOLDER ...]

**Seeing the window from here.** Launch under XWayland and capture its own
window: `env -u WAYLAND_DISPLAY DISPLAY=:0 setsid target/debug/duckling DIR &`,
find it with `xwininfo -root -tree | grep '"duckling"'`, then
`xwd -id ID | convert xwd:- shot.png`. Drive it with `xdotool`. The build
directory is the shared one in `~/.cargo/config.toml`, not `target/`. That
proves a code path draws; it does not stand in for David's keyboard
walkthrough, which every slice that touches the window gets.

---

## Rules

**The UI is a renderer.** The queue, the worker, the output rules and the
collision rule live in `src/lib.rs`, which does not know egui exists. Logic in
`src/main.rs` that another front-end would need is in the wrong file.

**Never overwrite.** A converter that writes beside its source is one wrong
extension away from replacing somebody's file. `available_path` numbers a
taken name and it is tested; nothing writes around it.

**The models ship in the package.** Every platform's package carries
`.models/` and `.pdfium/` beside the executable, fetched by
`packaging/fetch-models.sh` from pinned URLs with pinned hashes. There is no
download at run time and no code for one. DESIGN.md §2.

**C is taken here, deliberately and once.** ONNX Runtime and pdfium are the
whole of it, and `DESIGN.md` §2 records what they cost. The fleet's stance is
in `~/notes/pure_rust_preference.md`; adding a third C dependency is a
decision to take with David.

**Unsafe has no home.** `src/lib.rs` is `forbid`; `src/main.rs` is `deny`,
which a platform arm may lift for one module the way slipcase-desktop's
document-open handler on macOS does. Adding one is a decision to take with
David.

---

## Conventions

Every source file carries `Author: David M. Anderson` and `Built with AI
assistance (Claude, Anthropic)` in its header comment. Commits carry a
`Co-Authored-By` trailer for the Claude model in use and a `Signed-off-by`
trailer for David, and no session URL.

Packaging is cloned from `excelano/slipcase-desktop` through `excelano/segler`,
one directory per platform; `packaging/README.md` says what is there. CI is
the fleet's `excelano/.github` Rust workflow.
