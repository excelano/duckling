# Checklist: the things only a hand can test

Every window defect slipcase-desktop and segler found was found at the
keyboard, and none by a test. The suite passed through all of them. This
file is what a person runs instead.

It is the list, not the log. What each run found is in `git log`. A finding
earns a place here only when it changes how you run the list.

Run against the packaged application, not a developer build: on Linux the
`.deb` installed with `apt`, on Windows the MSIX, on macOS the TestFlight
build, since a Store-signed bundle cannot be launched anywhere else.
Several items are properties of the package rather than the code, and the
first one is the whole reason the package is as large as it is.

The folder to run against is a scratch copy of a few files from the
docling.rs corpus: a Word file with tables, a workbook, a digital PDF with
tables, a scanned PDF, a Markdown file, and something in a non-Latin script.

## Every platform: the window

1. **A scanned PDF converts, from a fresh install, with no network.** Pull
   the cable or turn the radio off first. The page comes back as text.
   This is the models in the package; nothing else on this list proves it.
2. **The window follows the desktop's theme**, light and dark, and switching
   the desktop while the window is up switches the window. On Linux this is
   the XDG portal path in `system_theme.rs`, which nothing else exercises.
3. **Drop the folder on the window.** Every readable file is queued in name
   order, files before the subfolder's, the stray `.exe` is not, and the
   status line says how many were added. Drop a single `.exe`: the status
   line names the extension.
4. **Convert to Markdown, beside each file.** Each row goes from Queued to
   a spinner or page count to Wrote. The PDF rows report pages. Nothing
   overwrites the Markdown source: it gets a numbered sibling.
5. **Select a row.** The preview shows the file's text; Open opens it in the
   default application; Show in folder reveals it.
6. **Convert the same files again into a folder**, as a DocLang archive. The
   folder fills; the preview shows the archive's XML. Open one in Segler.
7. **Convert a file with an existing `report.md` beside it.** The new one is
   `report (1).md` and the old one is untouched, byte for byte.
8. **Right-click a PDF and a Word file in the file manager.** Duckling is
   under Open With, and choosing it opens the window with the file queued.
9. **The non-Latin file.** The written file is right when opened in an
   editor; the preview may show boxes, which DESIGN.md §9 holds.

## Every platform: the language the window comes up in

Added 2026-09-09 with German. Two runs, and the second needs no German.

**In the pseudolocale, first.** `./po/pseudo.sh`, then a debug build with
`POTEXT_LANG=en-x-pseudo`. Every string this application owns comes back
bracketed, accented and 40% long: a sentence still in plain English never went
through `t`, one with no brackets is a message the catalogue never saw, and a
label with its end cut off is a layout built to the width of English.

**A screenshot proves only the paths that drew.** The toolbar, the queue, the
preview and the status bar were checked that way on 2026-09-09 with one file
queued. What that cannot reach is everything a conversion says: run one to the
end and read the status line, run one that fails, and on macOS let the folder
panel appear. The two startup states — no models beside the application, and an
`intel-mac` build — are each a single sentence written before the window opens,
and the dialog for a window that will not open at all is reachable only by
breaking the graphics stack.

**Then in German.** The file's own words stay English on purpose and that is not
a miss: the format a row was read as, an extension in the skipped list, and most
format names in the picker. `DESIGN.md` §9 says which and why.

## Linux: the package

10. `sudo apt install ./dist/duckling_X.Y.Z_amd64.deb` installs with no
    maintainer-script output, and `dpkg -V duckling` is silent.
11. `man duckling` opens.
12. `packaging/linux/check-libraries.sh` passes on both backends. It is a
    command and not part of CI because it needs a display.

## Windows: the package

The first item is the one this lane exists for. Five DLLs ship inside the
package because `+crt-static` will not link the ONNX Runtime this application
uses, and a machine that has never had Visual Studio on it is the only place
that arrangement is really tested. `DESIGN.md` §2 and
`packaging/windows/README.md` §1.

13. **A machine with no Visual C++ Redistributable installed.** Install the
    MSIX and start it. It starts. This is what slipcase-desktop 0.1.1 failed
    certification for, on a tester's clean machine and not on a developer's.
    A fresh VM or Windows Sandbox is the check; the developer machines all
    have Visual Studio.

    **Do the cheap version first, because it proves more.** On any machine,
    including one that has the redistributable, run the installed package and
    read `Get-Process duckling | Select-Object -Expand Modules`: every shipped
    DLL should resolve to the package directory and none to `System32`. A
    clean machine can only show that the application started; this shows which
    file it used, with a `System32` copy present to be preferred if the loader
    were going to prefer it. Done 2026-09-05, all five from the package.
    This item is then about what nobody predicted rather than about the DLLs.

    Getting a genuinely clean machine is harder than it sounds: an old laptop
    has usually had Office or a game on it and so has the redistributable
    already. Check `Test-Path C:\Windows\System32\vcruntime140.dll` **before**
    concluding anything from a machine that started the application.
14. **Convert a PDF from the packaged application.** The models and pdfium
    resolve inside `C:\Program Files\WindowsApps`, which is the only place
    the packaged layout differs from every other. Item 1 covers the network
    being off; this one is that the package's own paths work.
15. **Right-click a PDF and a Word file.** Duckling is under Open With, and
    choosing it opens the window with the file queued. Then check that it did
    not become the default: double-clicking the same PDF still opens whatever
    opened it before. Both routes claim nothing, and this is the item that
    would notice if one started to.

    **Do this before launching Duckling any other way, and say how long it
    took.** On an old Surface on 2026-09-05, the first Open With after
    installing the package did nothing at all - no window, no error - and it
    began working only after the application had once been started from the
    Start menu. Whether that is the shell not yet having picked the
    association up, or a first-run activation timing out while 64 MB of
    executable pages in from a cold disk, is not established. It is the kind
    of thing only a slow machine shows, so a fast one passing this item proves
    less than it looks.
16. `build-msix.ps1 -SelfSign -Certify` from an elevated prompt. The kit's
    findings match `$KNOWN_FINDINGS`, which is empty until the first run puts
    something in it - so the first run is read rather than passed, and what it
    says goes into that list with a traced reason or nowhere.
17. **The taskbar and the Start menu.** The icon is the duckling unplated,
    not on an accent-coloured square. That is `resources.pri` and the
    `altform-unplated` assets doing their job, and slipcase-desktop shipped a
    package where they were present and inert.
18. `install.ps1`, then `uninstall.ps1`. The install directory is gone
    afterwards, Settings > Apps has no leftover row, and a PDF still opens with
    whatever opened it before. Run it with the MSIX installed as well: the two
    coexist, and removing the script install leaves the package's Open With
    entry alone.

## macOS: the package

The release build is Apple silicon only and the lane machine is Intel, so
this section is run on a different machine from the one that built the
package, and the first item is the reason the package is as large as it is.
`packaging/macos/README.md` §1 and §3.

**Run 2026-09-07 on a rented Mac mini M1** under macOS 26.6.1, against the
arm64 bundle signed with the Apple Development identity rather than the
TestFlight build: the same code and the same entitlements, the sandbox real,
and no Apple ID on a machine that belongs to somebody else. TestFlight was set
up through the API and then skipped, decided the same evening, because what it
would have added is Apple's signature over the same bytes. David drove the
window over VNC; the install check, the screenshots and the display mode came
in over ssh. Item 1 held on this machine too: a scanned page came back as text
through the bundled models, with the network refused by the entitlements
rather than by a pulled cable. Item 2 held as well, the window following the
desktop live from light to dark and back.

19. **Convert a single file beside itself, having dropped it alone.** The
    open panel appears at the file's folder with the message *Allow Duckling
    to write beside the files in ...: choose that folder*. Choose it: the row
    goes to Wrote and the file is beside its source. Then a second file from a
    second folder, and cancel the panel: the row stays Queued and the status
    line says so. Then drop a *folder* and convert beside: no panel. Measured
    2026-09-05 on the `intel-mac` build under a real sandbox on the lane
    machine, and 2026-09-07 on the arm64 build, where all three passes matched
    it, the quarantine attribute on the written file included. The folder pass
    also showed two things that are the recorded rules rather than defects: a
    path whose row is already done is queued again, which `src/main.rs` says
    beside `add_paths`, and Duckling's own `.dclg` output in that folder was
    read as DocLang and converted to a numbered sibling, the way item 4's
    Markdown is.
20. **Add files through the button, not the command line.** A file given as
    an argument to a sandboxed application cannot be read - *Operation not
    permitted* - which is the sandbox and not a defect; the argument route is
    for the unsandboxed bundles CI and the lane use. Nothing a person does
    reaches it, and this item is here so nobody files it.
21. **`check-install.sh` on the installed bundle** reports arm64, ONNX
    Runtime linked in, the models in `Contents/Resources/models`, pdfium in
    `Contents/Frameworks` signed by the team, and a sandbox container after
    the first launch. It is a command rather than eyes, and the eyes are the
    two items above and the icon in the Dock. Passed 2026-09-07: native ARM64,
    the container `com.excelano.duckling` after the first launch, and nothing
    mechanical wrong.
22. **No Open With.** Right-click a PDF: Duckling is not offered, and that is
    the recorded state rather than a defect; `DESIGN.md` §9 holds it. Item 8
    does not apply on this platform. Confirmed 2026-09-07 by asking Launch
    Services, which holds no claim for the bundle.
23. **The layout at 2x.** Every Mac this application had been drawn on was a
    1x display over VNC, and a Retina display is where egui's text and the
    preview pane's wrapping get looked at for the first time. Looked at
    2026-09-07 on the rented mini's virtual display switched to its HiDPI mode
    with `packaging/macos/display-mode.swift`, 1920 by 1080 points at 3840 by
    2160 pixels: the text is crisp, the columns hold, the preview wraps inside
    its pane and nothing clips.

## What earlier runs cost

**Walk through the first usable slice, not the fourth.** Segler built four
stages before the first keyboard walkthrough, and the walkthrough found the
product frame wrong rather than a defect. Duckling's first walkthrough was
the first build.

**One step at a time, one report per step.** David runs the list and reports
each item as pass or as what he saw; a screenshot or a screencast for
anything visual.
