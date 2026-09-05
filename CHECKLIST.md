# Checklist: the things only a hand can test

Every window defect slipcase-desktop and segler found was found at the
keyboard, and none by a test. The suite passed through all of them. This
file is what a person runs instead.

It is the list, not the log. What each run found is in `git log`. A finding
earns a place here only when it changes how you run the list.

Run against the packaged application, not a developer build: on Linux the
`.deb` installed with `apt`, on Windows the MSIX, on macOS the bundle.
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

## Linux: the package

10. `sudo apt install ./dist/duckling_X.Y.Z_amd64.deb` installs with no
    maintainer-script output, and `dpkg -V duckling` is silent.
11. `man duckling` opens.
12. `packaging/linux/check-libraries.sh` passes on both backends. It is a
    command and not part of CI because it needs a display.

## What earlier runs cost

**Walk through the first usable slice, not the fourth.** Segler built four
stages before the first keyboard walkthrough, and the walkthrough found the
product frame wrong rather than a defect. Duckling's first walkthrough was
the first build.

**One step at a time, one report per step.** David runs the list and reports
each item as pass or as what he saw; a screenshot or a screencast for
anything visual.
