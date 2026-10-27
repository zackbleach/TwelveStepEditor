// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Swift translation of the official 12 Step editor's preset/settings formatting and upload framing:
//   QT/presetimageformatting/imageformatter.cpp   (JSON values -> IMAGE / SETTINGS structs)
//   QT/presetimageformatting/StandalonePreset.h   (struct layouts)
//   QT/presetimageformatting/DeviceManager/download.c, sysex.cpp (SysEx framing)
// Original code Copyright (c) 2025 KMI Music, Inc. (Muse Kinetics), MPL-2.0.
// https://github.com/Muse-Kinetics/12-step-editor-qt6
//
// Byte-for-byte equality with the original C++ is checked by GoldenUploadTests, using bytes
// produced by Tools/golden-harness (the unmodified C++ compiled against a small Qt stand-in).

import Foundation

/// Builds the exact bytes the desktop editor sends for a setlist upload and a settings upload.
public enum PresetImageFormatter {
    /// `sizeof(IMAGE)`: one preset as stored on the device.
    public static let imageSize = 191
    /// `sizeof(SETTINGS)`.
    public static let settingsSize = 15

    /// Packet type `SX_PACKET_STANDALONE`, sub-types from `sysexcmds.h`.
    static let standalonePacketType: UInt16 = 9
    static let presetImageType: UInt8 = 0  // SA_TYPE_PRESET_IMAGE
    static let settingsType: UInt8 = 2     // SA_TYPE_SETTINGS
    static let presetInfoFormatVersion: UInt8 = 1 // PRESET_INFO_FORMAT_VERSION
    /// The legacy encoder always uses PID 20 and 10 padding bytes, even for a 12 Step2.
    static let legacyPID = TwelveStepPID.twelveStep1.rawValue
    static let legacyHeaderPadding = 10

    // MARK: Messages

    /// The full-setlist upload, or nil for an empty setlist (the editor sends nothing then).
    /// **Replaces every preset on the device.**
    public static func setlistMessage(for resolved: ResolvedSetlist) -> [UInt8]? {
        let order = resolved.uploadOrder
        guard !order.isEmpty else { return nil }
        // STANDALONE_INFO: type (u16, big-endian on the wire), preset_info {format, reserved[2], num_presets}.
        let info: [UInt8] = [0, presetImageType, presetInfoFormatVersion, 0, 0, UInt8(truncatingIfNeeded: order.count)]
        let images = order.enumerated().map { image(for: $0.element, slot: $0.offset) }
        return KMIFraming.encode(KMIPacket(pid: legacyPID, packetType: standalonePacketType, blocks: [info] + images),
                                 headerPadding: legacyHeaderPadding)
    }

    /// The global settings upload.
    ///
    /// The C++ keeps `standalone_info` in a global, so after a setlist upload its last three bytes
    /// still hold the preset-info values. We always send them as zero, which is what the desktop
    /// sends on connect, before any setlist upload in the session.
    public static func settingsMessage(for settings: GlobalSettings) -> [UInt8] {
        let info: [UInt8] = [0, settingsType, 0, 0, 0, 0]
        return KMIFraming.encode(KMIPacket(pid: legacyPID, packetType: standalonePacketType,
                                           blocks: [info, settingsBytes(settings)]),
                                 headerPadding: legacyHeaderPadding)
    }

    // MARK: IMAGE (one preset)

    /// `ImageFormatter::formatImage` for one slot. A nil preset is a setlist gap, which the
    /// editor sends as an image built from an empty map.
    public static func image(for preset: Preset?, slot: Int) -> [UInt8] {
        let values = preset?.values ?? [:]
        func value(_ key: String) -> JSONValue { values[key] ?? .null }
        func char(_ key: String) -> UInt8 { UInt8(truncatingIfNeeded: value(key).intValue) }

        var modlines = [Destination: [UInt8]]()
        var ctlNum1: UInt8 = 0
        var ctlNum2: UInt8 = 0
        var cc1Used = false

        // The C++ loops modlineNum 0..<6 over keys "modline0_…" to "modline5_…". The JSON keys run
        // from modline1 to modline6, so modline6 is never sent. Reproduced deliberately.
        for number in 0..<6 {
            func field(_ name: String) -> JSONValue { value("modline\(number)_\(name)") }
            let destination: Destination?
            switch field("destination").stringValue {
            case "Note": destination = .velocity
            case "Bend": destination = .bend
            case "CC" where !cc1Used:
                destination = .cc1
                ctlNum1 = UInt8(truncatingIfNeeded: field("cc_number").intValue)
                cc1Used = true
            case "CC":
                destination = .cc2
                ctlNum2 = UInt8(truncatingIfNeeded: field("cc_number").intValue)
            case "Channel Pressure": destination = .aftertouch
            case "Poly Aftertouch": destination = .polyAftertouch
            default: destination = nil // "Volume", "XFade", "Pan" and unknown values are ignored
            }
            guard let destination else { continue }
            modlines[destination] = fixedPoint(field("gain").doubleValue) + [
                UInt8(truncatingIfNeeded: field("max").intValue),
                UInt8(truncatingIfNeeded: field("min").intValue),
                UInt8(truncatingIfNeeded: field("offset").intValue),
                UInt8(truncatingIfNeeded: field("smooth").intValue),
                sourceMenuNumber(field("source_a").stringValue),
                sourceMenuNumber(field("source_b").stringValue),
                tableMenuNumber(field("table").stringValue),
            ]
        }

        var bytes: [UInt8] = [UInt8(truncatingIfNeeded: slot)]
        for destination in Destination.structOrder {
            bytes += modlines[destination] ?? [UInt8](repeating: 0, count: 11)
        }
        for index in 1...4 {
            bytes.append(latin1FirstCharacter(value("preset_displayname_\(index)").stringValue))
        }
        bytes += [ctlNum1, ctlNum2]

        let noteMode = noteModes[value("settings_note_mode").stringValue] ?? 0
        let footMode = keySafetyModes[value("settings_key_safety_mode").stringValue] ?? 0
        bytes.append(bitfield(mode: noteMode,
                              local: cvLocalModes[value("settings_cv1_local").stringValue] ?? 0,
                              usb: cvUSBModes[value("settings_cv1_usb").stringValue] ?? 0,
                              channel: cvUSBModes[value("settings_cv1_usb_ch").stringValue] ?? 0))
        bytes.append(bitfield(mode: footMode,
                              local: cvLocalModes[value("settings_cv2_local").stringValue] ?? 0,
                              usb: cvUSBModes[value("settings_cv2_usb").stringValue] ?? 0,
                              channel: cvUSBModes[value("settings_cv2_usb_ch").stringValue] ?? 0))

        for prefix in ["voice_a", "voice_b"] {
            // VOICE: reserved[3], bankMSB, bankLSB, channel, reserved4, programChange, transpose
            bytes += [0, 0, 0,
                      char("\(prefix)_bank_msb"), char("\(prefix)_bank"), char("\(prefix)_channel"),
                      0, char("\(prefix)_programchange"), char("\(prefix)_transpose")]
        }

        for key in 1...13 {
            for note in 1...5 {
                bytes.append(char(String(format: "key%02d_note%d", key, note)))
            }
        }
        assert(bytes.count == imageSize)
        return bytes
    }

    // MARK: SETTINGS

    /// `ImageFormatter::formatSettings`.
    public static func settingsBytes(_ settings: GlobalSettings) -> [UInt8] {
        let values = settings.values
        func value(_ key: String) -> JSONValue? { values[key] }
        func int(_ key: String, default fallback: Int = 0) -> UInt8 {
            UInt8(truncatingIfNeeded: value(key)?.intValue ?? fallback)
        }
        // Pedal calibration uses `isNull()`, so a JSON null also falls back to the default.
        func pedal(_ key: String, default fallback: Int) -> UInt8 {
            guard let value = value(key), value != .null else { return UInt8(fallback) }
            return UInt8(truncatingIfNeeded: value.intValue)
        }
        let midiChannel10 = 9 // MIDI_CH_10

        var bytes = fixedPoint(value("globalSensitivity")?.doubleValue ?? 0)
        bytes += [int("selectSensitivity"), int("offThreshold", default: 5), int("onThreshold", default: 15)]
        bytes += [pedal("pedal_calibration_min", default: 20),
                  pedal("pedal_calibration_max", default: 230),
                  pedal("pedal_calibration_table", default: 0)]
        bytes += [int("backlightBrightness"), int("progchgRXchannel", default: midiChannel10), 0]
        // CONNECT_MODE: standalone (byte), then bit fields tether:1, midi_volume_reset:1, key_velocity_disable:1.
        let volumeReset = int("midiVolume") & 1
        let velocityDisable = int("velocityOverride") & 1
        bytes += [1, volumeReset << 1 | velocityDisable << 2]
        assert(bytes.count == settingsSize)
        return bytes
    }

    // MARK: Helpers

    enum Destination: CaseIterable {
        case aftertouch, bend, cc1, cc2, pan, polyAftertouch, velocity, volume, xfade
        /// Field order of `MODLINES`: AfTch, bend, CC1, CC2, Pan, PlyAftTch, Velociy, Volume, XFade.
        static let structOrder: [Destination] = [.aftertouch, .bend, .cc1, .cc2, .pan, .polyAftertouch, .velocity, .volume, .xfade]
    }

    /// `toFixedPt`: 16.16 fixed point, `(int)(val * 65536)`, stored big-endian.
    static func fixedPoint(_ value: Double) -> [UInt8] {
        let scaled = value * 65536
        let whole: Int32 = scaled.isFinite && abs(scaled) < 2_147_483_648 ? Int32(scaled) : 0
        let bits = UInt32(bitPattern: whole)
        return [UInt8(bits >> 24), UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
    }

    /// Bit fields are allocated from the least significant bit (clang/GCC on little-endian).
    static func bitfield(mode: UInt8, local: UInt8, usb: UInt8, channel: UInt8) -> UInt8 {
        (mode & 0x03) | (local & 0x07) << 2 | (usb & 0x03) << 5 | (channel & 0x01) << 7
    }

    /// `QString::toLatin1().at(0)`, or a space for an empty string.
    static func latin1FirstCharacter(_ string: String) -> UInt8 {
        guard let first = string.utf16.first else { return 0x20 }
        return first <= 0xFF ? UInt8(first) : 0x3F // '?' for characters outside Latin-1
    }

    static func sourceMenuNumber(_ item: String) -> UInt8 {
        sourceMenu.firstIndex(of: item).map(UInt8.init) ?? 0
    }

    static func tableMenuNumber(_ item: String) -> UInt8 {
        tableMenu.firstIndex(of: item).map(UInt8.init) ?? 0
    }

    static let sourceMenu = ["Off", "Velocity", "Velocity (Inverted)", "Pressure", "Pressure (Inverted)", "Tilt",
                             "Tilt (Inverted)", "KeyNum", "KeyNum (Inverted)", "Pedal", "Pedal (Inverted)"]
    static let tableMenu = ["Linear", "Sine", "Cosine", "Exponential", "Logarithmic", "DeadZone"]
    static let noteModes: [String: UInt8] = ["Normal": 0, "Legato": 1, "Toggle": 2, "Hold": 3]
    static let keySafetyModes: [String: UInt8] = ["SingleKey": 1, "MultiKey": 0, "Single Key": 1, "Multi Key": 0, "Mono": 1, "Poly": 0]
    static let cvLocalModes: [String: UInt8] = ["Default (Gate)": 0, "Default (Pitch)": 0, "Gate": 1, "Pitch": 2, "Velocity": 3,
                                                "Pressure": 4, "Tilt": 5, "Expression Pedal": 6, "Disabled": 7]
    static let cvUSBModes: [String: UInt8] = ["Gate": 0, "Pitch": 1, "Velocity": 2, "Bend / Mod": 3, "Ch 1": 0, "Ch 2": 1]
}
