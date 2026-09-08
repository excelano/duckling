// List a Mac's display modes, or switch to one for this login session.
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// This exists for CHECKLIST.md item 23, the layout at 2x. Every Mac this
// application had been drawn on was a 1x display over VNC, and a rented Mac
// mini with no monitor is the same: macOS gives it a 1920 by 1080 virtual
// display. That display's mode list carries a HiDPI mode of the same size at
// 3840 by 2160 pixels, which is a Retina desktop in every way egui can tell,
// and this is what puts it there. The mode is set for the session, so a
// logout puts the display back and nothing is written to disk.
//
//     swiftc -O packaging/macos/display-mode.swift -o display-mode
//     ./display-mode list                 # every mode, HiDPI ones marked
//     ./display-mode set 1920 1080 3840   # points wide, points high, pixels wide
//
// Measured 2026-09-07 on a Mac mini M1 under macOS 26.6.1: the mode took, the
// window kept its 1100 by 732 points, and `screencapture -R` of that rectangle
// came back 2200 by 1464 pixels.

import CoreGraphics
import Foundation

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else {
    print("the window server listed no modes for the main display")
    exit(2)
}

func describe(_ m: CGDisplayMode) -> String {
    let hidpi = m.pixelWidth == 2 * m.width ? "  HiDPI" : ""
    return "\(m.width)x\(m.height) points, \(m.pixelWidth)x\(m.pixelHeight) px\(hidpi)"
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "list":
    print("main display: \(CGDisplayPixelsWide(display))x\(CGDisplayPixelsHigh(display)) points")
    var seen = Set<String>()
    for m in modes where seen.insert(describe(m)).inserted {
        print(describe(m))
    }
case "set" where arguments.count == 5:
    guard let width = Int(arguments[2]), let height = Int(arguments[3]), let pixels = Int(arguments[4]) else {
        print("usage: display-mode set WIDTH HEIGHT PIXEL_WIDTH")
        exit(2)
    }
    guard let mode = modes.first(where: { $0.width == width && $0.height == height && $0.pixelWidth == pixels }) else {
        print("no mode is \(width)x\(height) points at \(pixels) pixels wide; `list` shows what there is")
        exit(1)
    }
    var configuration: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&configuration)
    CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil)
    let error = CGCompleteDisplayConfiguration(configuration, .forSession)
    guard error == .success else {
        print("the window server refused the mode: \(error.rawValue)")
        exit(1)
    }
    print("set \(describe(mode)) for this session")
default:
    print("usage: display-mode list | set WIDTH HEIGHT PIXEL_WIDTH")
    exit(2)
}
