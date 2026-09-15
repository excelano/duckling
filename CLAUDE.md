# CLAUDE.md

Duckling converts documents with docling.rs: one crate, `duckling`, presented as Duckling.
`src/lib.rs` is the queue, the worker and the output rules and knows nothing about a window;
`src/main.rs` is the window. Duckling adds no conversion logic: a wrong conversion is
docling.rs's issue and a wrong office package is `waddle-core`'s. `DESIGN.md` is the authority.

## Commands

    ./packaging/fetch-models.sh                 # once; pinned, idempotent
    cargo build
    cargo test                                  # end-to-end tests skip without a docling.rs checkout
    cargo clippy --all-targets -- -D warnings   # must be silent
    cargo fmt --check
    cargo run -- [FILE|FOLDER ...]
    ./po/update-po.sh                           # after changing any sentence a person reads
    ./po/pseudo.sh                              # then a debug build with POTEXT_LANG=en-x-pseudo

The build directory is the shared one in `~/.cargo/config.toml`, not `target/`. Windows:
`fetch-models.sh` in Git Bash, `cargo build --release`, then `packaging\windows\check-imports.ps1`
and `build-msix.ps1 -SelfSign`. macOS: `MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --target
aarch64-apple-darwin`, then `packaging/macos/build-app.sh`; an Intel Mac adds `--features intel-mac`
to every `cargo` command. Each `packaging/` README has its lane. A screenshot proves a code path
draws; it does not replace David's keyboard walkthrough.

Releases: run `ship duckling`. There is no release document.

## Rules

Logic another front end would need lives in `src/lib.rs`, never in `src/main.rs`; the translation
catalogue is declared in `src/main.rs`, since only the window speaks. Nothing writes around
`available_path`: no existing file is overwritten. The models ship in the package from
`fetch-models.sh`'s pins; there is no download at run time and no code for one. The C in the tree is
ONNX Runtime, pdfium and oniguruma, plus DirectML on Windows; another C dependency is David's decision
(`~/notes/pure_rust_preference.md`). `+crt-static` stays absent on Windows, and `check-imports.ps1`
refusing a DLL goes to David, not into its list. Nothing under `packaging/windows` may write an
extension's default value or remove a `UserChoice`. `src/lib.rs` is `forbid(unsafe_code)` and
`src/main.rs` is `deny`; lifting it for a platform module is David's decision. Every source file header
carries `Author: David M. Anderson` and `Built with AI assistance (Claude, Anthropic)`. Commits carry a
`Co-Authored-By` trailer for the Claude model in use and a `Signed-off-by` trailer for David, and no session URL.
