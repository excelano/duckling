#!/bin/sh
# Photograph the application's own window at a size App Store Connect accepts.
#
# The counterpart of `packaging/windows/screenshot.ps1`, cloned from
# slipcase-desktop's script of the same name. What a script cannot do is decide
# which documents to queue or whether the result is a good advertisement -
# `packaging/store-listing.md` decides that. What it can do is every
# mechanical part: launch the bundle with those documents, size the window,
# front it, park the pointer, capture, and refuse if what came back is the
# wrong size.
#
#   ./packaging/macos/screenshot.sh --app dist/Duckling.app \
#       --documents ~/Documents/Alder\ Creek --out shots/01-queue.png
#
# `--documents` is a folder, which the application walks the way a drop does,
# or a file; give it more than once for more than one. `--wait SECONDS` is how
# long to leave the window before the shutter, which is what catches a queue
# mid-conversion or lets it finish.
#
# THREE THINGS MEASURED RATHER THAN ASSUMED, ALL OF THEM SLIPCASE-DESKTOP'S
#
# **It captures the window by its id, not by its rectangle.** `screencapture
# -R` photographs whatever is on screen in that region, so anything overlapping
# the window lands in the picture. `-l` takes the window's own buffer.
#
# **The pointer is moved off the window first.** A shot once came back 2292
# pixels different from its predecessor and none of them were the change being
# photographed, because the pointer was resting on a field and egui drew it
# hovered.
#
# **It photographs a bundle, never the bare executable.** And never the Store
# package: that cannot be launched off the Store, so no macOS screenshot is
# ever of the artefact uploaded. Build a signed bundle from the commit being
# released and say so in `packaging/store-listing.md`.
#
# WHAT IS DUCKLING'S OWN
#
# The documents reach the application as arguments - `open --args` - because
# Duckling claims no file type on this platform, so `open -a Duckling file.pdf`
# would be refused by AppKit for want of a document handler. That is the same
# path a command-line launch takes and the one `main.rs` reads.
#
# And it needs an Apple silicon Mac to photograph a conversion: the release
# build is arm64 only. On the Intel lane it photographs the `intel-mac` build,
# whose PDF rows fail, which is a picture of the wrong thing for a listing.
#
# Needs Accessibility permission for whatever runs it, because sizing another
# application's window goes through System Events. System Settings → Privacy &
# Security → Accessibility.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
set -eu

app=""
documents=""
out=""
wait=6
# 1440x900 is one of the four sizes App Store Connect accepts for macOS, and the
# largest reachable without a Retina display. The other two - 2560x1600 and
# 2880x1800 - need a backing scale of 2.
width=1440
height=900
x=100
y=80

usage() {
    sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app) app="${2:?--app needs a bundle}"; shift 2 ;;
        --documents) documents="${documents} $(cd "$(dirname "${2:?}")" && pwd)/$(basename "$2")"; shift 2 ;;
        --out) out="${2:?--out needs a path}"; shift 2 ;;
        --wait) wait="${2:?}"; shift 2 ;;
        --width) width="${2:?}"; shift 2 ;;
        --height) height="${2:?}"; shift 2 ;;
        --x) x="${2:?}"; shift 2 ;;
        --y) y="${2:?}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "screenshot.sh: unknown argument $1" >&2; usage 2 ;;
    esac
done

refuse() { echo "screenshot.sh: $1" >&2; exit 1; }

[ -n "$app" ] || refuse "no --app given"
[ -n "$documents" ] || refuse "no --documents given"
[ -n "$out" ] || refuse "no --out given"
[ -d "$app" ] || refuse "no bundle at $app"

case "$app" in
    *.app) ;;
    *) refuse "--app wants a .app bundle; a bare executable has no icon and is not what anybody installs" ;;
esac

# `open -a` reads a relative path as an application *name* to look up.
app=$(cd "$(dirname "$app")" && pwd)/$(basename "$app")
mkdir -p "$(dirname "$out")"

helper=$(mktemp -d)/helper.swift
trap 'rm -rf "$(dirname "$helper")"' EXIT INT TERM
cat > "$helper" <<'SWIFT'
import CoreGraphics
import Foundation

// Park the pointer in the far corner. The corner rather than a constant: a
// fixed coordinate is off-screen on a smaller display.
if CommandLine.arguments.contains("--park") {
    let screen = CGDisplayBounds(CGMainDisplayID())
    CGWarpMouseCursorPosition(CGPoint(x: screen.maxX - 1, y: screen.maxY - 1))
    exit(0)
}

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Duckling"
guard
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]]
else {
    FileHandle.standardError.write("the window server returned nothing\n".data(using: .utf8)!)
    exit(2)
}
for w in windows {
    guard w[kCGWindowOwnerName as String] as? String == wanted,
          (w[kCGWindowLayer as String] as? Int ?? -1) == 0,
          let number = w[kCGWindowNumber as String] as? Int
    else { continue }
    print(number)
    exit(0)
}
FileHandle.standardError.write("no ordinary window belonging to \(wanted)\n".data(using: .utf8)!)
exit(1)
SWIFT

# Anything already running is stopped, so the window photographed is the one
# holding this run's documents rather than one left over.
pkill -f "$(basename "$app")/Contents/MacOS/" 2>/dev/null || true
sleep 1

# shellcheck disable=SC2086
open -a "$app" --args $documents
sleep 4

osascript >/dev/null <<OSA || refuse "could not size the window - is Accessibility granted?"
tell application "System Events"
    set p to first process whose name is "Duckling"
    set frontmost of p to true
    tell p
        set position of window 1 to {$x, $y}
        set size of window 1 to {$width, $height}
    end tell
end tell
OSA

swift "$helper" --park
sleep "$wait"

id=$(swift "$helper" Duckling) || refuse "could not find the window"
screencapture -x -o -l "$id" "$out"

got_w=$(sips -g pixelWidth "$out" | sed -n 's/.*pixelWidth: *//p')
got_h=$(sips -g pixelHeight "$out" | sed -n 's/.*pixelHeight: *//p')
if [ "$got_w" != "$width" ] || [ "$got_h" != "$height" ]; then
    refuse "asked for ${width}x${height} and got ${got_w}x${got_h} - App Store Connect refuses anything but its own sizes"
fi

echo "${out}: ${got_w}x${got_h}, window ${id}"
