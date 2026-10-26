# 12 Step iOS Editor

A native iOS editor for the Muse Kinetics **12 Step** MIDI foot controller, over USB-C.

**Current state: Phase 7, first full editor (0.5.0).** It covers everything the desktop 12 Step Editor does to presets, the setlist and global settings, with a redesigned way to assign notes to keys (see `DESIGN.md`). Setlist and settings are sent to the 12 Step over USB-C, byte-identical to the desktop editor. Firmware update and the calibration windows aren't included.

## Sharing presets with the desktop editor (optional)

The phone app works on its own, starting from the factory presets. To edit the same presets on a Mac and the phone:

1. Quit the 12 Step Editor, then double-click `Tools/mac-sync/Enable iCloud Sync.command`. It:
   - backs up the editor's folder to `~/Documents/12 Step Editor Backups/`;
   - copies the files to `iCloud Drive/12 Step Editor/`;
   - points the editor there.

   The editor app itself isn't modified. `Disable iCloud Sync.command` undoes it.
2. In Finder, right-click `iCloud Drive/12 Step Editor` and choose **Keep Downloaded**.
3. In the app, go to Library → **Choose folder…** → iCloud Drive → **12 Step Editor**.

**Rules:**
- Quit the desktop editor while editing on the phone. It doesn't notice outside changes and would overwrite them when it saves. The app refuses to save over a file that changed since it was loaded.
- If the desktop editor says a file is missing, choose **Exit Application**, never **Factory Default**. Factory Default deletes the whole folder, and with sync, on every device.

This doesn't need a paid Apple developer account. The app uses the Files picker, not its own iCloud container.

## Layout

```
TwelveStepEditor/
├── TwelveStepDiagnostics.xcodeproj   iOS app project (Xcode 16+)
├── TwelveStepDiagnostics/            SwiftUI app: App entry, AppModel, Views/, Assets
├── TwelveStepKit/                    Swift package, no UI
│   ├── Sources/TwelveStepKit/
│   │   ├── MIDI/         MIDITransport protocol, CoreMIDITransport, MockMIDITransport, UMP codec
│   │   ├── Protocol/     KMI framing + CRC (MPL-2.0), 12 Step messages, safety allow-list, classifier
│   │   ├── Discovery/    12 Step endpoint matching
│   │   ├── Logging/      DiagnosticLog
│   │   └── Services/     DiagnosticsSession (queries, timeouts, status, report)
│   ├── Sources/twelvestep-probe/   macOS CLI using the same code (hardware baseline)
│   └── Tests/            Swift Testing suite (golden vectors from the official editor)
├── Tools/
│   ├── golden-harness/   builds the official C++ formatter to produce golden upload bytes
│   └── mac-sync/         Enable / Disable iCloud Sync scripts for the desktop editor
├── PROTOCOL.md   protocol findings with source references
├── FEASIBILITY.md
├── TESTING.md    install + physical test instructions
├── PROGRESS.md   phase status and next steps
└── LICENSES/MPL-2.0.txt
```

The official editor source used as the reference is cloned at `../12step-reference`.

## Build

- **iOS app:** open `TwelveStepDiagnostics.xcodeproj`, choose your Team under Signing & Capabilities, select your iPhone, then ⌘R. See `TESTING.md` for the full steps.
- **Command-line check:**
  ```sh
  xcodebuild -project TwelveStepDiagnostics.xcodeproj -scheme TwelveStepDiagnostics \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```
- **Tests (macOS host):** `cd TwelveStepKit && swift test`
- **Simulated device:** use the "Use simulated device" switch on the Device tab, or the `-simulate` launch argument. Simulated replies are invented placeholders.

Requirements: Xcode 16 or later, and iOS 17 or later (USB-C iPhones ship with iOS 17+).

## Licensing

Some files are derived from the official editor and stay under MPL-2.0 (see their headers and `LICENSES/MPL-2.0.txt`):
- `Protocol/KMIFraming.swift` and `Protocol/PresetImageFormatter.swift` (translations);
- `Resources/FactoryPresets/` (copied unmodified, see `NOTICE.txt`).

If you distribute the app, the source of these files must be made available. The rest of the project isn't derived from MPL files.
