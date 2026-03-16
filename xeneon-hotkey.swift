#!/usr/bin/env swift

// xeneon-hotkey — Send keystrokes via CGEvent (bypasses Accessibility API)
//
// Usage:
//   xeneon-hotkey <key> [modifiers...]
//
// Examples:
//   xeneon-hotkey v command          # ⌘V (paste)
//   xeneon-hotkey c command          # ⌘C (copy)
//   xeneon-hotkey x command          # ⌘X (cut)
//   xeneon-hotkey z command          # ⌘Z (undo)
//   xeneon-hotkey z command shift    # ⌘⇧Z (redo)
//   xeneon-hotkey a command          # ⌘A (select all)
//   xeneon-hotkey s command          # ⌘S (save)
//   xeneon-hotkey f command          # ⌘F (find)
//   xeneon-hotkey t command          # ⌘T (new tab)
//   xeneon-hotkey w command          # ⌘W (close tab)
//   xeneon-hotkey space              # Space
//   xeneon-hotkey return             # Return/Enter
//   xeneon-hotkey escape             # Escape
//   xeneon-hotkey tab                # Tab
//   xeneon-hotkey delete             # Delete/Backspace
//   xeneon-hotkey up                 # Arrow up
//   xeneon-hotkey down               # Arrow down
//   xeneon-hotkey left               # Arrow left
//   xeneon-hotkey right              # Arrow right
//
// The 100ms delay before sending allows the TouchscreenDriver's
// focus restoration to complete when used from Stream Deck on the
// Corsair Xeneon Edge.

import Foundation
import CoreGraphics

// Key name → macOS virtual key code mapping
let keyCodes: [String: CGKeyCode] = [
    // Letters
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
    "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
    "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
    "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
    "4": 0x15, "6": 0x16, "5": 0x17, "7": 0x1A, "8": 0x1C,
    "9": 0x19, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
    "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D,
    "m": 0x2E,

    // Special keys
    "return": 0x24, "enter": 0x24,
    "tab": 0x30,
    "space": 0x31,
    "delete": 0x33, "backspace": 0x33,
    "escape": 0x35, "esc": 0x35,
    "forwarddelete": 0x75,

    // Arrow keys
    "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,

    // Function keys
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
    "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,

    // Punctuation
    "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
    "\\": 0x2A, ";": 0x29, "'": 0x27, ",": 0x2B,
    ".": 0x2F, "/": 0x2C, "`": 0x32,
]

// Parse modifier names → CGEventFlags
func parseModifiers(_ args: [String]) -> CGEventFlags {
    var flags = CGEventFlags()
    for arg in args {
        switch arg.lowercased() {
        case "command", "cmd":
            flags.insert(.maskCommand)
        case "shift":
            flags.insert(.maskShift)
        case "option", "alt":
            flags.insert(.maskAlternate)
        case "control", "ctrl":
            flags.insert(.maskControl)
        default:
            break
        }
    }
    return flags
}

// --- Main ---

let args = Array(CommandLine.arguments.dropFirst())

guard !args.isEmpty else {
    fputs("Usage: xeneon-hotkey <key> [command|shift|option|control...]\n", stderr)
    exit(1)
}

let keyName = args[0].lowercased()
guard let keyCode = keyCodes[keyName] else {
    fputs("Unknown key: \(args[0])\n", stderr)
    fputs("Available keys: \(keyCodes.keys.sorted().joined(separator: ", "))\n", stderr)
    exit(1)
}

let modifiers = parseModifiers(Array(args.dropFirst()))

// Wait for TouchscreenDriver focus restoration to complete.
// The driver restores focus 50ms after injecting the click;
// 100ms gives ample margin.
usleep(100_000)

// Create and post keystroke via CGEvent
let source = CGEventSource(stateID: .combinedSessionState)

guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
    fputs("Error: could not create CGEvent\n", stderr)
    exit(1)
}

keyDown.flags = modifiers
keyUp.flags = modifiers

keyDown.post(tap: .cghidEventTap)
usleep(10_000) // 10ms between down and up
keyUp.post(tap: .cghidEventTap)
