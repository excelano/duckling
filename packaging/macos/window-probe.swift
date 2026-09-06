// Ask the window server whether an application has drawn a window.
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// This exists for CI. `.github/workflows/macos.yml` runs the suite on an Apple
// silicon runner, which is the only kind of machine the release build runs on
// at all, and the one thing a test cannot reach is the window.
//
// **A screenshot is the wrong assertion and the fleet already knows it.**
// slipcase-desktop's `CHECKLIST.md` records `screencapture` returning the
// desktop and the menu bar with every window omitted, reporting no error while
// doing it. A job asserting on pixels would have gone green against that. So
// this asks the window server directly.
//
// `CGWindowListCopyWindowInfo` gives the owner name and the bounds without
// Screen Recording permission; only the window *title* needs it, which is why
// no title is read here. That claim is the reason this prints what it saw
// rather than only its verdict: if the list is empty the API is restricted and
// the answer is unknown, and if it holds other applications' windows but none
// of ours then the application genuinely drew nothing. Those are different
// findings and a bare exit code cannot tell them apart.

import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Duckling"

guard
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]]
else {
    print("the window server returned nothing at all - the list is unavailable")
    exit(2)
}

var owners: Set<String> = []
var ours: [(Double, Double, Int)] = []

for w in windows {
    guard let owner = w[kCGWindowOwnerName as String] as? String else { continue }
    owners.insert(owner)
    guard owner == wanted else { continue }
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    guard
        let b = w[kCGWindowBounds as String] as? [String: Any],
        let width = b["Width"] as? Double,
        let height = b["Height"] as? Double
    else { continue }
    ours.append((width, height, layer))
}

print("on-screen windows: \(windows.count), from \(owners.count) applications")
print("owners: \(owners.sorted().joined(separator: ", "))")

if windows.isEmpty {
    print("VERDICT: unknown - the window server listed nothing, so this says")
    print("         nothing about \(wanted). Not a pass and not a failure.")
    exit(2)
}

// Layer 0 is an ordinary application window. A menu, a panel or a shadow sits
// elsewhere, and counting one of those as the application's window would make
// this pass against a build that draws no interface at all.
let real = ours.filter { $0.0 > 1 && $0.1 > 1 && $0.2 == 0 }
for (w, h, layer) in ours {
    print(String(format: "  %@ window: %.0f x %.0f at layer %d", wanted, w, h, layer))
}

if real.isEmpty {
    print("VERDICT: FAILED - \(windows.count) windows are listed and none of them is")
    print("         an ordinary window belonging to \(wanted).")
    exit(1)
}

print("VERDICT: passed - \(wanted) has \(real.count) ordinary window(s) on screen")
exit(0)
