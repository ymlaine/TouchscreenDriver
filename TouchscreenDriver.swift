#!/usr/bin/env swift

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import AppKit

// ============================================
// Corsair Xeneon Edge Configuration
// Adjust after analyzing HID reports
// ============================================
let TOUCHSCREEN_VENDOR_ID: Int = 0x27c0
let TOUCHSCREEN_PRODUCT_ID: Int = 0x0859

// Touchscreen coordinate ranges (calibrated via HIDAnalyzer)
var touchscreenMaxX: CGFloat = 16383
var touchscreenMaxY: CGFloat = 9599
var touchscreenMinX: CGFloat = 0
var touchscreenMinY: CGFloat = 0

// ============================================
// Target screen configuration
// ============================================
var targetScreen: NSScreen?
var screenOffsetX: CGFloat = 0
var screenOffsetY: CGFloat = 0
var screenWidth: CGFloat = 2560
var screenHeight: CGFloat = 720

// ============================================
// Touch state
// ============================================
var currentX: CGFloat = 0
var currentY: CGFloat = 0
var isTouching: Bool = false
var lastClickTime: Date = Date.distantPast
let debounceInterval: TimeInterval = 0.05 // 50ms debounce

// Buffered coordinates to handle HID element ordering race:
// touch state can arrive before coordinates in the same report
var pendingX: CGFloat?
var pendingY: CGFloat?

// ============================================
// Event source (private state so our injected events
// don't interfere with the system's cursor tracking)
// ============================================
let eventSource: CGEventSource? = CGEventSource(stateID: .privateState)

// ============================================
// Cursor suppression via CGEvent tap
// Suppresses mouse-movement events during click injection so
// Stream Deck (Electron/Chromium) can't displace the cursor.
// ============================================
var suppressCursorEvents: Bool = false
var cursorSuppressionTap: CFMachPort?

func cursorSuppressionCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if macOS disabled it (timeout or user input)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = cursorSuppressionTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // During click injection, suppress all mouse-movement events
    if suppressCursorEvents {
        return nil
    }

    return Unmanaged.passUnretained(event)
}

func setupCursorSuppression() {
    // Intercept all mouse-movement event types that could displace the
    // cursor while we're injecting a click.
    let eventMask: CGEventMask =
        (1 << CGEventType.mouseMoved.rawValue) |
        (1 << CGEventType.leftMouseDragged.rawValue) |
        (1 << CGEventType.rightMouseDragged.rawValue) |
        (1 << CGEventType.otherMouseDragged.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: cursorSuppressionCallback,
        userInfo: nil
    ) else {
        log("Warning: could not create cursor suppression tap")
        return
    }

    cursorSuppressionTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("Cursor suppression tap active")
}

// ============================================
// HID capture mode
// ============================================
enum CaptureMode {
    case shared      // Listens without blocking (may cause double clicks)
    case exclusive   // Exclusive capture - blocks system events (recommended)
}
var captureMode: CaptureMode = .exclusive

// ============================================
// Logging (works under launchd where print() is buffered)
// ============================================
func log(_ message: String) {
    let line = message + "\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

// ============================================
// Utility functions
// ============================================

func convertToScreenCoordinates(rawX: Int, rawY: Int) -> CGPoint {
    // Normalize raw coordinates to 0.0 - 1.0
    let normalizedX = (CGFloat(rawX) - touchscreenMinX) / (touchscreenMaxX - touchscreenMinX)
    let normalizedY = (CGFloat(rawY) - touchscreenMinY) / (touchscreenMaxY - touchscreenMinY)

    // Convert to screen coordinates
    let screenX = screenOffsetX + (normalizedX * screenWidth)
    let screenY = screenOffsetY + (normalizedY * screenHeight)

    return CGPoint(x: screenX, y: screenY)
}

func injectClick(at point: CGPoint) {
    // Debounce check
    let now = Date()
    guard now.timeIntervalSince(lastClickTime) > debounceInterval else { return }
    lastClickTime = now

    // Save current cursor position (NSScreen coords -> CG coords)
    let originalPosition = NSEvent.mouseLocation
    let mainScreenHeight = NSScreen.screens[0].frame.height
    let originalCGPosition = CGPoint(x: originalPosition.x,
                                     y: mainScreenHeight - originalPosition.y)

    // Save the frontmost application before the click.
    // The injected click on the Xeneon Edge shifts macOS key focus to whatever
    // window is at the touch point (e.g., Stream Deck's Electron window).
    // We re-activate the original app after the click so that Stream Deck
    // hotkey actions deliver keystrokes to the correct app.
    let previousApp = NSWorkspace.shared.frontmostApplication

    // --- Begin cursor-protected click ---
    // 1. Suppress all mouse-movement events (event tap)
    // 2. Hide cursor + warp to touch point
    // 3. Inject click
    // 4. Warp back to original position + show cursor
    // 5. Re-activate the previously focused app
    // 6. Keep suppression active to absorb delayed responses
    suppressCursorEvents = true
    CGDisplayHideCursor(CGMainDisplayID())
    CGWarpMouseCursorPosition(point)

    guard let mouseDown = CGEvent(mouseEventSource: eventSource,
                                   mouseType: .leftMouseDown,
                                   mouseCursorPosition: point,
                                   mouseButton: .left) else {
        log("Error creating mouseDown event")
        suppressCursorEvents = false
        CGDisplayShowCursor(CGMainDisplayID())
        return
    }

    guard let mouseUp = CGEvent(mouseEventSource: eventSource,
                                 mouseType: .leftMouseUp,
                                 mouseCursorPosition: point,
                                 mouseButton: .left) else {
        log("Error creating mouseUp event")
        suppressCursorEvents = false
        CGDisplayShowCursor(CGMainDisplayID())
        return
    }

    mouseDown.post(tap: .cghidEventTap)
    usleep(10000) // 10ms between down and up
    mouseUp.post(tap: .cghidEventTap)

    // Warp back immediately after click
    CGWarpMouseCursorPosition(originalCGPosition)
    CGDisplayShowCursor(CGMainDisplayID())

    // Re-activate the previously focused app after a short delay.
    // The click has been delivered to Stream Deck; now restore focus so that
    // any hotkey/keystroke Stream Deck sends lands on the correct app.
    // 50ms is enough for the click to register but well before Stream Deck
    // processes the button action and sends a keystroke (~100-300ms).
    if let app = previousApp {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            app.activate()
        }
    }

    // Keep suppression active for 300ms to absorb any delayed
    // Stream Deck hover/focus events that would displace the cursor
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
        suppressCursorEvents = false
    }

    log("Click injected at (\(Int(point.x)), \(Int(point.y)))")
}

func injectDrag(to point: CGPoint) {
    // Skip drag events during click suppression window --
    // otherwise drag warps override the warp-back in injectClick
    guard !suppressCursorEvents else { return }

    guard let dragEvent = CGEvent(mouseEventSource: eventSource,
                                   mouseType: .leftMouseDragged,
                                   mouseCursorPosition: point,
                                   mouseButton: .left) else {
        return
    }

    CGWarpMouseCursorPosition(point)
    dragEvent.post(tap: .cghidEventTap)
}

// ============================================
// HID callback
// ============================================

func hidInputCallback(context: UnsafeMutableRawPointer?,
                      result: IOReturn,
                      sender: UnsafeMutableRawPointer?,
                      value: IOHIDValue) {

    // Do NOT call updateScreenFromCurrentList() here -- it overwrites
    // correct geometry on every HID event. Screen geometry is updated
    // via the ScreenChangeObserver notification + polling timer instead.

    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)

    // Buffer coordinates -- they may arrive before or after touch state
    if usagePage == 0x01 { // Generic Desktop
        switch usage {
        case 0x30: // X
            pendingX = CGFloat(intValue)
        case 0x31: // Y
            pendingY = CGFloat(intValue)
        default:
            break
        }
    }

    // Detect touch (Tip Switch OR Button 1)
    // The Xeneon Edge uses Button 1 (usagePage 0x09, usage 0x01) instead of Tip Switch
    let isTouchEvent = (usagePage == 0x0D && usage == 0x42) || (usagePage == 0x09 && usage == 0x01)

    if isTouchEvent {
        // Commit any buffered coordinates before processing touch state
        if let px = pendingX { currentX = px; pendingX = nil }
        if let py = pendingY { currentY = py; pendingY = nil }

        let wasTouching = isTouching
        isTouching = intValue != 0

        if isTouching && !wasTouching {
            // New touch -> click
            let screenPoint = convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY))
            injectClick(at: screenPoint)
        } else if isTouching && wasTouching {
            // Slide -> drag
            let screenPoint = convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY))
            injectDrag(to: screenPoint)
        }
        // On release, do nothing (mouseUp was already sent)
    } else if usagePage == 0x01 {
        // Coordinate-only update while touching -> treat as drag
        if let px = pendingX { currentX = px; pendingX = nil }
        if let py = pendingY { currentY = py; pendingY = nil }
        if isTouching {
            let screenPoint = convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY))
            injectDrag(to: screenPoint)
        }
    }
}

// ============================================
// Screen configuration
// ============================================

func setupScreen() {
    // Find the Corsair Xeneon Edge display

    let screens = NSScreen.screens
    log("Detected screens:")

    for (index, screen) in screens.enumerated() {
        let frame = screen.frame
        let name = screen.localizedName
        log("   [\(index)] \(name): \(Int(frame.width))x\(Int(frame.height)) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
    }

    // Look for the Corsair screen (fall back to secondary or primary)
    if let xeneonScreen = screens.first(where: { $0.localizedName.contains("XENEON") || $0.localizedName.contains("Corsair") }) {
        targetScreen = xeneonScreen
        log("Xeneon Edge screen found!")
    } else if screens.count > 1 {
        targetScreen = screens[1]
        log("Xeneon not identified by name, using secondary screen")
    } else {
        targetScreen = NSScreen.main
        log("Only one screen detected, using primary screen")
    }

    updateScreenGeometry()
}

var xeneonDisplayID: CGDirectDisplayID = 0

func findXeneonDisplayID() {
    // Correlate with the NSScreen we identified as the Xeneon via deviceDescription
    if let screen = targetScreen,
       let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
        xeneonDisplayID = screenNumber
        log("Xeneon display ID from NSScreen: \(xeneonDisplayID)")
        return
    }

    // Fallback: pick non-main display (original behavior)
    var displayCount: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &displayCount)

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    CGGetActiveDisplayList(displayCount, &displays, &displayCount)

    for display in displays {
        if display != CGMainDisplayID() {
            xeneonDisplayID = display
            log("Xeneon display ID (fallback, first non-main): \(xeneonDisplayID)")
            break
        }
    }
}

func updateScreenFromCurrentList() {
    guard xeneonDisplayID != 0 else { return }

    // Use CGDisplayBounds which updates in real-time (unlike NSScreen.screens)
    let bounds = CGDisplayBounds(xeneonDisplayID)

    // CGDisplayBounds uses top-left origin coordinate system
    screenOffsetX = bounds.origin.x
    screenOffsetY = bounds.origin.y
    screenWidth = bounds.width
    screenHeight = bounds.height
}

func updateScreenGeometry() {
    if let screen = targetScreen {
        let frame = screen.frame
        let scaleFactor = screen.backingScaleFactor

        // NSScreen uses bottom-left origin, but CGEvent uses top-left origin
        // We need to convert Y coordinates
        let mainScreenHeight = NSScreen.screens[0].frame.height

        screenOffsetX = frame.origin.x
        // Convert Y: cgY = mainHeight - nsY - screenHeight
        screenOffsetY = mainScreenHeight - frame.origin.y - frame.height

        // CGEvent uses logical point coordinates
        // frame.size already gives logical size, which is what we want
        screenWidth = frame.width
        screenHeight = frame.height

        log("Target screen: \(Int(screenWidth))x\(Int(screenHeight)) points")
        log("   Backing scale factor: \(scaleFactor)x (HiDPI: \(scaleFactor > 1 ? "yes" : "no"))")
        log("   NSScreen origin: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
        log("   CGEvent origin:  (\(Int(screenOffsetX)), \(Int(screenOffsetY)))")
    }
}

// ============================================
// Screen change observer
// ============================================

// Last known geometry for detecting changes
var lastKnownScreenOriginX: CGFloat = 0
var lastKnownScreenOriginY: CGFloat = 0
var lastKnownScreenWidth: CGFloat = 0
var lastKnownScreenHeight: CGFloat = 0

class ScreenChangeObserver {
    var timer: DispatchSourceTimer?

    init() {
        // Watch for screen configuration changes (connect/disconnect)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            log("\nScreen configuration changed! Updating...")
            setupScreen()
            findXeneonDisplayID()
            saveCurrentGeometry()
        }

        // GCD timer to check for position changes
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer?.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer?.setEventHandler {
            checkForGeometryChanges()
        }
        timer?.resume()
    }
}

func saveCurrentGeometry() {
    if let screen = targetScreen {
        lastKnownScreenOriginX = screen.frame.origin.x
        lastKnownScreenOriginY = screen.frame.origin.y
        lastKnownScreenWidth = screen.frame.width
        lastKnownScreenHeight = screen.frame.height
    }
}

func checkForGeometryChanges() {
    // Find the Xeneon screen in the current list (updated by the system)
    guard let currentXeneon = NSScreen.screens.first(where: {
        $0.localizedName.contains("XENEON") || $0.localizedName.contains("Corsair")
    }) ?? (NSScreen.screens.count > 1 ? NSScreen.screens[1] : nil) else {
        return
    }

    let frame = currentXeneon.frame
    if frame.origin.x != lastKnownScreenOriginX ||
       frame.origin.y != lastKnownScreenOriginY ||
       frame.width != lastKnownScreenWidth ||
       frame.height != lastKnownScreenHeight {

        log("\nLayout change detected!")
        log("   Before: (\(Int(lastKnownScreenOriginX)), \(Int(lastKnownScreenOriginY))) \(Int(lastKnownScreenWidth))x\(Int(lastKnownScreenHeight))")
        log("   After:  (\(Int(frame.origin.x)), \(Int(frame.origin.y))) \(Int(frame.width))x\(Int(frame.height))")

        // Update the screen reference
        targetScreen = currentXeneon
        updateScreenGeometry()
        findXeneonDisplayID()
        saveCurrentGeometry()
    }
}

var screenObserver: ScreenChangeObserver?

// ============================================
// Permission check
// ============================================

func checkAccessibilityPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// ============================================
// Main
// ============================================

func main() {
    // Initialize NSApplication so that:
    // 1. NSScreen.screens returns live data (not stale)
    // 2. didChangeScreenParametersNotification actually fires
    // 3. AppKit events are dispatched properly
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // No dock icon, no menu bar

    log("""
    ======================================================
       Touchscreen Driver - Corsair Xeneon Edge  v3.1.0
       Converts touch input to absolute mouse clicks
    ======================================================

    """)

    // Check Accessibility permissions
    log("Checking Accessibility permissions...")
    if !checkAccessibilityPermission() {
        log("""

        PERMISSION REQUIRED

        To inject clicks, this app must be added to:
        System Settings -> Privacy & Security -> Accessibility

        A permission dialog should have appeared.
        After granting permission, restart the program.

        """)
        exit(1)
    }
    log("Accessibility permission granted")

    // Configure the target screen
    setupScreen()
    findXeneonDisplayID()
    saveCurrentGeometry()

    // Initialize the screen change observer
    screenObserver = ScreenChangeObserver()

    log("""

    Current configuration:
       Touchscreen: X=[0, \(Int(touchscreenMaxX))], Y=[0, \(Int(touchscreenMaxY))]
       Click mode: warp + suppression (cursor invisible during click)
       Capture mode: \(captureMode == .exclusive ? "EXCLUSIVE (blocks system events)" : "SHARED (may cause double clicks)")

    If clicks are at the wrong position, adjust touchscreenMaxX/Y
       in the source code after using HIDAnalyzer.

    """)

    // Install cursor suppression event tap (must be before HID manager)
    setupCursorSuppression()

    // Create the HID Manager
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    // Filter for our touchscreen
    let deviceMatch: [String: Any] = [
        kIOHIDVendorIDKey as String: TOUCHSCREEN_VENDOR_ID,
        kIOHIDProductIDKey as String: TOUCHSCREEN_PRODUCT_ID
    ]

    IOHIDManagerSetDeviceMatching(manager, deviceMatch as CFDictionary)

    // Open the manager with the appropriate mode
    // kIOHIDOptionsTypeSeizeDevice = 0x01 - takes exclusive control of the device
    let openOptions: IOOptionBits
    if captureMode == .exclusive {
        openOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        log("Opening in EXCLUSIVE mode (seize device)...")
    } else {
        openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
        log("Opening in SHARED mode...")
    }

    let openResult = IOHIDManagerOpen(manager, openOptions)
    if openResult != kIOReturnSuccess {
        log("Error: Cannot open IOHIDManager (code: \(openResult))")
        if captureMode == .exclusive {
            log("""

            Exclusive mode can fail if:
               - Another program is already using the device
               - Insufficient permissions

            You can try SHARED mode by changing:
               var captureMode: CaptureMode = .shared

            """)
        }
        exit(1)
    }

    // Verify the device
    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
        log("Error: Touchscreen not found!")
        exit(1)
    }

    log("Touchscreen connected! (\(deviceSet.count) HID interface(s) seized)")
    for device in deviceSet {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usageId = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
        log("   - \(product): usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usageId, radix: 16))")
    }

    // Register the callback
    IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    log("""

    Driver active! Touch the screen to click.
       (Ctrl+C to quit)

    """)

    // Use NSApplication.run() instead of CFRunLoopRun() so that:
    // 1. AppKit events are dispatched (NSScreen notifications work)
    // 2. The run loop processes all event sources properly
    app.run()
}

// Disable stdout buffering for real-time output
setbuf(stdout, nil)

// Entry point
main()
