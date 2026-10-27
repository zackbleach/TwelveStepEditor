# 12 Step iOS Editor

A native iOS editor for the Muse Kinetics **12 Step** MIDI foot controller, over USB-C.

**Current state: preparing the first release (0.6.0).** It covers everything the desktop 12 Step Editor does to presets, the setlist and global settings, with a redesigned way to assign notes to keys. Setlist and settings are sent to the 12 Step over USB-C, byte-identical to the desktop editor. Firmware update and the calibration windows aren't included.

## Sharing presets with the desktop editor (optional)

The phone app works on its own, starting from the factory presets. To edit the same presets on a Mac and the phone:

1. Build and open **12 Step Sync** (`Tools/sync-setup/build-app.sh` makes `Tools/sync-setup/dist/12 Step Sync.app`).
   - It checks that the desktop editor is closed and iCloud Drive is on.
   - It backs up the editor's folder to `~/Documents/12 Step Editor Backups/`.
   - It copies the four preset files to `iCloud Drive/12 Step Editor/`.
   - It points the editor's `PRESET_DIR` preference there.
   - **Turn Off Sync** reverses it, bringing the latest presets back to the Mac.
   - The desktop editor app itself is never modified.
2. In the iOS app: **Settings › Choose folder… › iCloud Drive › 12 Step Editor**.

The older Terminal scripts in `Tools/mac-sync/` do the same steps.

**Rules:**
- Quit the desktop editor while editing on the phone. It doesn't notice outside changes and would overwrite them when it saves. The app refuses to save over a file that changed since it was loaded.
- If the desktop editor says a file is missing, choose **Exit Application**, never **Factory Default**. Factory Default deletes the whole folder, and with sync, on every device.

This doesn't need a paid Apple developer account. The app uses the Files picker, not its own iCloud container.

## Layout

```
TwelveStepEditor/
├── TwelveStepEditor.xcodeproj   iOS app project (Xcode 16+)
├── TwelveStepEditor/            SwiftUI app: App entry, AppModel, Views/, Assets
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
│   ├── sync-setup/       "12 Step Sync" Mac app: turns iCloud sharing on/off for the desktop editor
│   └── mac-sync/         the same as Terminal scripts (older)
├── PRIVACY.md    privacy policy (the app collects no data)
├── LICENSE.md    licence overview
└── LICENSES/     PolyForm Noncommercial 1.0.0 and MPL-2.0 texts
```

The official editor's source is at https://github.com/Muse-Kinetics/12-step-editor-qt6. The official user manual (help texts are based on v3.0.1) is at https://files.musekinetics.com/pub/products/12Step/editor/Manual/.

## Build

- **iOS app:** open `TwelveStepEditor.xcodeproj`, choose your Team under Signing & Capabilities, select your iPhone, then ⌘R.
- **Command-line check:**
  ```sh
  xcodebuild -project TwelveStepEditor.xcodeproj -scheme TwelveStepEditor \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```
- **Tests (macOS host):** `cd TwelveStepKit && swift test`
- **Demo mode (simulated device):** use the "Demo mode" switch on the Device tab, or the `-simulate` launch argument. Simulated replies are invented placeholders.

Requirements: Xcode 16 or later, and iOS 17 or later (USB-C iPhones ship with iOS 17+).

## Licensing

Source-available: free for noncommercial use, and commercial use needs permission. See [`LICENSE.md`](LICENSE.md).
- **Most of the project:** [PolyForm Noncommercial 1.0.0](LICENSES/PolyForm-Noncommercial-1.0.0.md).
- **Files derived from the official 12 Step Editor stay [MPL-2.0](LICENSES/MPL-2.0.txt):**
  - `Protocol/KMIFraming.swift`
  - `Protocol/PresetImageFormatter.swift`
  - `Resources/FactoryPresets/`
  - `Tools/golden-harness/`

Every source file's `SPDX-License-Identifier` header says which licence applies. By contributing, you agree that your contribution may be distributed under these terms and also licensed by the copyright holder under other terms, including commercially.
