#!/bin/sh
# The Mac App Store screenshots: which documents, which frames, and what the
# window is doing when the shutter goes.
#
# `screenshot.sh` beside this is the driver and `take-shots.sh` sits between
# them; both are ship's and the same in every repository. This file is
# Duckling's half. `packaging/windows/shots.ps1` is the same two frames for the
# other store, and `packaging/submission-notes.md` says why they are these two.
#
#     ./packaging/macos/shots.sh --app dist/Duckling.app
#     ./packaging/macos/shots.sh --app dist/Duckling.app --lang de
#     ./packaging/macos/shots.sh --app dist/Duckling.app --reference
#     ./packaging/macos/shots.sh --app dist/Duckling.app --reference --list-open
#
# The two reference frames are how the coordinates below get measured: the
# plain one gives the toolbar and the rows, and `--list-open` opens the format
# list, whose items exist only while it is open.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "${here}/../.." && pwd)

# --- the configuration ------------------------------------------------------

# One of the four sizes App Store Connect accepts, and the largest reachable
# without a Retina display. Every coordinate below is measured at this size and
# after the zoom.
WIDTH=1440
HEIGHT=900

# Duckling declares no document types, so the queue arrives as argv.
AS_ARGS=yes

# Four steps of egui's own zoom, 140%, which is the scale the frames on the
# listing are already at. At 100% the queue fills the top third of the frame
# and the text is small; the cost is the German toolbar wrapping to a second
# row, which the coordinates below account for.
EVERY_SHOT="--key cmd+plus --key cmd+plus --key cmd+plus --key cmd+plus"

DOCUMENTS="${root}/packaging/demo/documents"

# The queue is copied here first, so the paths in the frame read like somebody's
# machine rather than like a checkout.
STAGED="Alder Creek"

# Long enough for the whole queue, which for the scanned PDF is the models
# loading as well as the pages. Both frames wait for it: a frame caught part
# way through depends on how warm the machine is, and on a second run the batch
# was already finished at four seconds.
WHOLE_BATCH=90

list_open=no

# --- the controls, per language ---------------------------------------------
#
# "X,Y" in the frame, measured off a reference at the zoom above. German runs
# longer than English: its toolbar wraps to a second row, which moves every row
# of the queue down as well as pushing the controls right.

for_language() {
    document=$DOCUMENTS
    staged_name=$STAGED
    case "$1" in
        en|en-US|en-us)
            FORMAT_CONTROL='435,49'
            FORMAT_MARKDOWN='425,115'
            CONVERT='1065,49'
            FIELD_NOTES_ROW='80,200'
            SITE_SURVEY_ROW='100,435'
            ;;
        de|de-DE|de-de)
            FORMAT_CONTROL='630,49'
            FORMAT_MARKDOWN='620,115'
            CONVERT='1322,49'
            FIELD_NOTES_ROW='80,229'
            SITE_SURVEY_ROW='100,464'
            ;;
        *) echo "shots.sh: no set is written for $1" >&2; exit 2 ;;
    esac
    if [ "$list_open" = yes ]; then
        EVERY_SHOT="${EVERY_SHOT} --click ${FORMAT_CONTROL}"
    fi
}

# --- the shots --------------------------------------------------------------

shots() {
    # Twelve documents of nine formats converted in the format the window opens
    # on, with a Word file's DocLang in the preview: the structure a converter
    # is for, out of a format that hides it.
    shot 01-doclang \
        --click "$CONVERT" --settle "$WHOLE_BATCH" --click "$FIELD_NOTES_ROW"

    # The same queue as Markdown, the preview open on a PDF long enough to have
    # been worth converting, and `species-list.md` written out as
    # `species-list (1).md` - the never-overwrite rule of DESIGN.md §5 in the
    # picture.
    shot 02-markdown \
        --click "$FORMAT_CONTROL" --click "$FORMAT_MARKDOWN" \
        --click "$CONVERT" --settle "$WHOLE_BATCH" --click "$SITE_SURVEY_ROW"
}

# --- the driving ------------------------------------------------------------

# `--list-open` is this repository's own and is taken out before the rest goes
# to take-shots.sh, which refuses an argument it does not know.
rest=""
for arg in "$@"; do
    if [ "$arg" = --list-open ]; then
        list_open=yes
    else
        rest="${rest} ${arg}"
    fi
done

if [ "$list_open" = yes ]; then
    case " $rest " in
        *" --reference "*) ;;
        *) echo "shots.sh: --list-open is for taking a reference frame" >&2; exit 2 ;;
    esac
fi

. "${here}/take-shots.sh"

# shellcheck disable=SC2086
take_shots ${rest}
