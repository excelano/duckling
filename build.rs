//! Embed the Windows application manifest, and do nothing else ever.
//!
//! This is the tree's only build script, and `CLAUDE.md` is why it is worth
//! reading before adding a second thing to it. The rule there is about C: the
//! application takes ONNX Runtime and pdfium and nothing more, and a third C
//! dependency is a decision to take with David. This script holds to that by
//! compiling nothing at all - it prints two linker arguments and the linker
//! that was already linking the binary embeds
//! `packaging/windows/duckling.manifest`. No resource compiler, no object file.
//!
//! The distinction matters because the obvious way to do this is `rc.exe` or
//! `windres`, and `packaging/windows/README.md` rejects exactly that for the
//! window icon - which is why the icon travels through `include_bytes!`. That
//! rejection is of the resource compiler and not of the outcome, and the linker
//! route needs no compiler.
//!
//! **A second use for this file is a decision, not a precedent.** The one
//! opened here is narrow on purpose.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

#![forbid(unsafe_code)]

use std::path::Path;

fn main() {
    // The manifest lives with the rest of this platform's files under
    // `packaging/`, which is the same rule as staying inside your own directory
    // there. One level up from the crate, where segler's copy needs two,
    // because that repository is a workspace and this is a single crate.
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("packaging")
        .join("windows")
        .join("duckling.manifest");

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed={}", manifest.display());

    // Read from the environment rather than from `cfg!`, because a build script
    // is compiled for the host and `cfg!(windows)` in here answers about the
    // machine doing the building. Cross-checking from Linux with
    // `--target x86_64-pc-windows-msvc` is a thing this repository does, and it
    // would take the wrong branch.
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    if os != "windows" || env != "msvc" {
        return;
    }

    // `/MANIFEST:EMBED` is MSVC's, which is why the guard above tests the
    // environment and not just the operating system: a `windows-gnu` target
    // links with something that would not understand it.
    //
    // Named rather than `-bins`, so that the argument says which binary it is
    // about. There is one, and if a second ever arrives it should have to opt
    // in here rather than inherit a window's DPI declaration by accident.
    for arg in [
        "/MANIFEST:EMBED".to_string(),
        format!("/MANIFESTINPUT:{}", manifest.display()),
    ] {
        println!("cargo:rustc-link-arg-bin=duckling={arg}");
    }
}
