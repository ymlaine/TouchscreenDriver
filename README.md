# Touchscreen Driver for Corsair Xeneon Edge

> **Co-authored by [Yves-Marie Lainé](https://github.com/ymlaine) and [Claude](https://claude.ai) (Anthropic AI)**
>
> This driver was developed through human-AI collaboration using Claude Code.

A macOS driver that converts touch input from the Corsair Xeneon Edge (14.5" touch bar, 2560x720) into mouse clicks at the correct absolute screen position.

## Features

- Converts touch events to mouse clicks at the touched position
- Exclusive HID capture (no double clicks)
- Multi-monitor support with automatic screen detection
- Cursor returns to original position after click
- Adapts to resolution changes (including HiDPI/scaled modes)
- Dynamic reconfiguration when displays are rearranged

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Touchscreen    │────▶│  Driver          │────▶│  macOS          │
│  (USB HID)      │     │  (exclusive)     │     │  (CGEvent)      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
   Raw X, Y coords        Convert & map          Click at absolute
   Button events          to screen space        position
```

## Requirements

- macOS 10.15+ (Catalina or later)
- Xcode Command Line Tools: `xcode-select --install`
- Corsair Xeneon Edge connected via USB-C

## Installation

### Automatic (Recommended)

```bash
git clone https://github.com/ymlaine/TouchscreenDriver.git
cd TouchscreenDriver
./install.sh
```

This will:
- Compile the driver
- Install it to `/usr/local/bin`
- Configure it to start automatically at login
- Start the driver immediately

### Uninstall

```bash
./uninstall.sh
```

### Manual

```bash
git clone https://github.com/ymlaine/TouchscreenDriver.git
cd TouchscreenDriver
chmod +x run_driver.sh run_analyzer.sh
./run_driver.sh
```

### Grant Permissions

On first run, macOS will ask for permissions:

1. **Accessibility**: Required to inject mouse clicks
   - System Settings → Privacy & Security → Accessibility
   - Add Terminal (or the compiled binary)

2. **Input Monitoring**: Required to capture HID events
   - System Settings → Privacy & Security → Input Monitoring
   - Add Terminal (or the compiled binary)

### Control Commands

```bash
# Status
pgrep -f TouchscreenDriver && echo "Running" || echo "Stopped"

# Logs
tail -f /tmp/touchscreendriver.log

# Stop
launchctl unload ~/Library/LaunchAgents/com.ymlaine.touchscreendriver.plist

# Start
launchctl load ~/Library/LaunchAgents/com.ymlaine.touchscreendriver.plist
```

## Calibration

The driver is pre-calibrated for the Xeneon Edge touchscreen:
- X range: 0 - 16383
- Y range: 0 - 9599
- Touch detection: Button 1 (HID Usage Page 0x09)

### Re-calibrate (if needed)

If touch positions are incorrect, use the analyzer:

```bash
./run_analyzer.sh
```

Touch the screen corners and note the X/Y max values, then update `TouchscreenDriver.swift`:

```swift
var touchscreenMaxX: CGFloat = 16383  // Your X max
var touchscreenMaxY: CGFloat = 9599   // Your Y max
```

## Hardware Info

```
Touchscreen Controller:
  Vendor ID:  0x27c0
  Product ID: 0x0859
  Manufacturer: wch.cn

Display:
  Native resolution: 2560x720 (32:9 ratio)
  Recommended: 1920x540 scaled (better readability)
```

## Files

| File | Description |
|------|-------------|
| `TouchscreenDriver.swift` | Main driver with HID capture and CGEvent injection |
| `HIDAnalyzer.swift` | Diagnostic tool to inspect raw HID reports |
| `run_driver.sh` | Build and run the driver |
| `run_analyzer.sh` | Build and run the analyzer |

## Troubleshooting

### "Touchscreen not found"
- Ensure the Xeneon Edge is connected via USB-C
- Check USB connection in System Information → USB
- Verify Vendor/Product IDs match

### "Cannot open IOHIDManager"
- Grant Input Monitoring permission to Terminal
- Restart Terminal after granting permissions
- Close other apps using the touchscreen (iCUE, etc.)

### Clicks at wrong position
1. Run `./run_analyzer.sh` and touch screen corners
2. Update touchscreenMaxX/Y values in the code
3. Rebuild with `./run_driver.sh`

### Exclusive mode fails
Another app may be using the touchscreen. Either:
- Close conflicting apps (iCUE, etc.)
- Switch to shared mode (edit `TouchscreenDriver.swift`):
  ```swift
  var captureMode: CaptureMode = .shared
  ```
  Note: Shared mode may cause double clicks.

## Resolution Tips

The native 2560x720 resolution can make text hard to read. For better readability:

1. Go to **System Settings → Displays**
2. Select the Xeneon Edge
3. Choose **1920x540** (maintains 32:9 ratio, larger text)

The driver automatically adapts to any resolution.

## License

MIT License - Feel free to use and modify.

## Credits

Created by **Yves-Marie Lainé** in collaboration with **Claude** (Anthropic).

Built with Swift using IOKit HID and CoreGraphics frameworks.
