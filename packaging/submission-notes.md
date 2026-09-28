# Submission notes

What a store submission needs from a person and no file supplies: the notes a
certification reader is handed, the answers a form asks that no build can
give, and the reasoning behind the screenshots.

The listing text itself is not here. It is `store-listing.toml` beside this,
which `ship` checks before the tag and pushes to both stores on every release,
and what a release tells them changed is `release-notes.toml`. A field edited
in this file would reach nobody. Apple's Notes for Review are there too, as
`apple-review-notes`, which `ship` pushes to `appStoreReviewDetail` on every
Mac App Store submission - Microsoft's Notes for certification below have no
such field and are still typed in by hand.

## Notes for certification

What the Microsoft Store shows a certification tester. The message count in
the second paragraph changes with the binary: reread it off the kit report
before a submission.

```
Five DLLs ship inside the package beside duckling.exe: four Visual C++ runtime files and DirectML. The runtime files are app-local because +crt-static cannot link the ONNX Runtime this application uses - the link fails with 63 unresolved externals. DirectML is linked in by the ONNX Runtime distribution whether or not the application asks for it, at the version that library was built against rather than whatever the machine has.

The optional "Blocked executables" test reports 57 matches and the kit's overall result is PASS. Most are the three-letter scan for reg, cmd, csi, cdb and dnx finding those byte sequences inside binary weight data: decoder_kv.onnx.data is 116 MB and contains 11 occurrences of "cmd", fewer than the 55 that uniform random bytes would produce.

The "cmd.exe" strings and CreateProcessW in duckling.exe are the Rust standard library's process module, linked in because the GUI framework uses the webbrowser crate to open hyperlinks; the application contains no call that spawns a process. ShellExecuteW is used deliberately and only on a button press: the preview pane's Open and Show in folder buttons hand the file the user just converted to the shell's default handler.

Duckling converts documents offline, so about 375 MB of the package is ONNX model weights plus pdfium and DirectML. It makes no network connection of any kind and its import table contains no ws2_32, winhttp, wininet or iphlpapi. It claims no file type, so any Word file or PDF exercises it; the twelve documents the screenshots use are at github.com/excelano/duckling/tree/v0.1.1/packaging/demo/documents
```

## The answers a form asks

    Copyright and trademark   Excelano LLC
    Additional licence terms  blank - the application is MIT and the
                              repository carries the licence
    Short title               blank - the product name is already one word

## Screenshots

Each lane takes its own with its platform's script, against the packaged
application, with the pointer parked off the window and the window photographed
by its id. The documents are the ones in `packaging/demo/documents`, copied to a
folder with a short readable path, since the path shows in the preview. Two
shots, macOS taking each again in dark for the Mac App Store listing:

| | State to reach |
| --- | --- |
| `01-converting` / `01-doclang` | Convert to **DocLang**, press Convert, select `field-notes.docx`. Windows captures a few seconds in, with some rows still Queued and the scanned PDF spinning; macOS waits for the whole batch instead, since on a warm runner the batch can finish in four seconds and a frame caught part way through would then depend on how warm the machine was. |
| `02-converted` / `02-markdown` | Convert to **Markdown**, let the batch finish, select `site-survey-report.pdf`, capture. |

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
