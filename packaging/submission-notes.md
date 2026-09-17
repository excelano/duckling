# Submission notes

What a store submission needs from a person and no file supplies: the notes an
App Review or certification reader is handed, the answers a form asks that no
build can give, and the reasoning behind the screenshots.

The listing text itself is not here. It is `store-listing.toml` beside this,
which `ship` checks before the tag and pushes to both stores on every release,
and what a release tells them changed is `release-notes.toml`. A field edited
in this file would reach nobody.

## App Review notes

Duckling converts documents. It reads Word, PowerPoint and Excel files, PDFs, HTML, EPUB, RTF, OpenDocument, Apple Pages, Numbers and Keynote and some forty formats in all, and writes DocLang, Markdown, docling JSON, LaTeX, ODT, ODS, ODP, DOCX or XLSX. No account, no sign-in, no test credentials, and no network connection of any kind are needed to test it.

There is nothing a tester must be handed before the window does anything. Duckling claims no file type and opens with an empty queue: drop any Word file or PDF you already have onto the window, or use Add files, pick an output format, and convert. If you would rather have ours, the twelve documents the screenshots were taken from are at https://github.com/excelano/duckling/tree/v0.2.0/packaging/demo/documents — invented for the purpose, MIT licensed like the rest of the repository, and between them they exercise every format claimed above.

The App Sandbox is on with exactly two entitlements: the sandbox itself and read-write access to user-selected files. That grant is what a person gives by dropping a file or a folder on the window, picking one in the Add dialogs, or choosing a destination folder. What it does not cover is the folder around a file that arrived on its own, so Duckling asks for that folder before writing beside such a file rather than failing quietly. There is no network entitlement, no Downloads-folder entitlement, and no temporary exception.

Conversion is local. Documents are read by docling.rs, the open-source Rust port of IBM's Docling, compiled into the application; nothing is uploaded and no model is fetched. The full privacy statement is at https://excelano.com/legal/#duckling and the complete source is at https://github.com/excelano/duckling.

## Notes for certification

What the Microsoft Store shows a certification tester. The message count in
the second paragraph changes with the binary: reread it off the kit report
before a submission.

```
Five DLLs ship inside the package beside duckling.exe: four Visual C++ runtime files and DirectML. The runtime files are app-local because +crt-static cannot link the ONNX Runtime this application uses - the link fails with 63 unresolved externals. DirectML is linked in by the ONNX Runtime distribution whether or not the application asks for it, at the version that library was built against rather than whatever the machine has.

The optional "Blocked executables" test reports 57 matches and the kit's overall result is PASS. Most are the three-letter scan for reg, cmd, csi, cdb and dnx finding those byte sequences inside binary weight data: layout_heron.onnx is 172 MB and contains 20 occurrences of "cmd", fewer than the 82 that uniform random bytes would produce.

The "cmd.exe" strings and CreateProcessW in duckling.exe are the Rust standard library's process module, linked in because the GUI framework uses the webbrowser crate to open hyperlinks; the application contains no call that spawns a process. ShellExecuteW is used deliberately and only on a button press: the preview pane's Open and Show in folder buttons hand the file the user just converted to the shell's default handler.

Duckling converts documents offline, so about 734 MB of the package is ONNX model weights plus pdfium and DirectML. It makes no network connection of any kind and its import table contains no ws2_32, winhttp, wininet or iphlpapi. It claims no file type, so any Word file or PDF exercises it; the twelve documents the screenshots use are at github.com/excelano/duckling/tree/v0.1.1/packaging/demo/documents
```

## The answers a form asks

    Copyright and trademark   Excelano LLC
    Additional licence terms  blank - the application is MIT and the
                              repository carries the licence
    Short title               blank - the product name is already one word

## Screenshots

Each lane takes its own with its platform's script, against the packaged
application, light theme, with the pointer parked off the window and the window
photographed by its id. The documents are the ones in `packaging/demo/documents`,
copied to a folder with a short readable path, since the path shows in the
preview. Two shots:

| | State to reach |
| --- | --- |
| `01-converting` | Convert to **DocLang**, press Convert, select `field-notes.docx` about a second later, capture at about 2.5 s: some rows still Queued, the scanned PDF spinning, the rest done. |
| `02-converted` | Convert to **Markdown**, let the batch finish, select `site-survey-report.pdf`, capture. |

DocLang is selected in the first shot, where the preview is not the subject,
because its preview is markup carrying four `<location>` elements per node;
Markdown is selected in the shot with the preview open, and it is the word
people search for. In the first, the selected result comes from a Word file
rather than a PDF or the CSV, since neither of those reads as prose in a narrow
pane. In the second, a row shows `species-list.md` becoming
`species-list (1).md`, the never-overwrite rule of `DESIGN.md` §5 in the
picture; keep it. `site-survey-report.pdf` is the one long enough to be caught
mid-conversion with a page count, and `scanned-notice.pdf` is the one that
cannot convert without the models in the package, so a shot of it converted is
the offline-OCR claim photographed.

Zoom four steps, about 140%, with egui's own `Ctrl` and `+`, which the scripts
do and which nothing persists: the Store renders screenshots small, and at 100%
this application's text is about ten pixels.

**Windows.** `packaging/windows/shots.ps1` carries both frames and launches the
packaged application through the apps folder moniker with the documents as
arguments, since Duckling claims no file type and the executable under
`WindowsApps` cannot be run directly. It writes 1366x768, the Store's minimum.
The coordinates its recipes need have never been measured here — the Windows
pair predates the driver growing actions and was taken by hand — so
`shots.ps1 -Reference` takes the frame to read them off, and until they are
filled in the set refuses rather than photographing clicks that landed on
nothing.

**Mac App Store.** App Store Connect accepts 1280x800, 1440x900, 2560x1600 and
2880x1800; `packaging/macos/screenshot.sh` takes 1440x900 by default, from a
bundle launched with the documents as arguments. The bundle has to be the arm64
one signed with a Developer ID or Apple Development identity from the commit
being released, since a Store package cannot be launched off the Store, and it
runs only on an Apple silicon Mac; the sandbox blocks the argument route there,
so the folder goes in through Add folder. The `intel-mac` build fails every PDF
row, which for a listing whose second shot is a scanned PDF converted is a
picture of the wrong thing. Under the display's HiDPI mode
(`packaging/macos/display-mode.swift`) the window at 1440 by 900 points
captures at 2880x1800.
