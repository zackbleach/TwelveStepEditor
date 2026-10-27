// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

/// Product IDs from `KMI_DevData.h`.
public enum TwelveStepPID: UInt8, Sendable {
    case twelveStep1 = 20
    case bootloader = 21
    case twelveStep2 = 22

    public var displayName: String {
        switch self {
        case .twelveStep1: "12 Step (gen 1)"
        case .bootloader: "12 Step bootloader"
        case .twelveStep2: "12 Step2"
        }
    }
}

/// Message categories and types from `device_includes.h` (newer KMI packet format).
public enum KMICategory {
    public static let calibration: UInt8 = 1
    public static let preset: UInt8 = 2
}

/// `SYX_PRESET_MSGS` (`device_includes.h:78`). Defined in the source but never used by the editor.
public enum KMIPresetType {
    public static let requestPreset: UInt8 = 0
    public static let presetPayload: UInt8 = 1
}

public enum KMICalibrationType {
    public static let requestPedalCal: UInt8 = 0
    public static let pedalCalPayload: UInt8 = 1
    public static let requestKeysCal: UInt8 = 2
    public static let keysCalPayload: UInt8 = 3
    public static let requestCVCal: UInt8 = 4
    public static let cvCalPayload: UInt8 = 5
    public static let resetCVCalToFactory: UInt8 = 6
}

/// The only queries the app is allowed to transmit: read-only messages that the official desktop
/// editor sends routinely (see PROTOCOL.md §3). The one-off preset-request probe (2026-10-24,
/// PROTOCOL.md §9) has been removed now its question is answered.
public enum SafeCommand: String, CaseIterable, Identifiable, Sendable {
    /// Universal Identity Request, sent by the desktop editor every 5 s while connecting.
    case identityRequest
    /// Request CV calibration data (12 Step2). Sent by the desktop editor on every connect.
    case cvCalibrationRequest
    /// Legacy 12 Step firmware query for pre-1.0.9 units named "12Step Port 1".
    case legacyFirmwareQuery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .identityRequest: "Identity request"
        case .cvCalibrationRequest: "CV calibration request"
        case .legacyFirmwareQuery: "Legacy firmware query"
        }
    }

    public var explanation: String {
        switch self {
        case .identityRequest:
            "Standard MIDI Universal Identity Request. Reads hardware generation, firmware and bootloader versions."
        case .cvCalibrationRequest:
            "KMI packet (category 1, type 4). Reads CV calibration; expected to answer on 12 Step2 only. Exercises the CRC/7-bit decoder."
        case .legacyFirmwareQuery:
            "Old-style 12 Step firmware query used for pre-1.0.9 units. Fallback only."
        }
    }

    public var bytes: [UInt8] {
        switch self {
        case .identityRequest:
            TwelveStepMessages.identityRequest
        case .cvCalibrationRequest:
            TwelveStepMessages.cvCalibrationRequest
        case .legacyFirmwareQuery:
            TwelveStepMessages.legacyFirmwareQuery
        }
    }

    /// Whether an incoming SysEx message is the expected reply to this command.
    public func isReply(_ message: [UInt8]) -> Bool {
        guard message != bytes else { return false } // ignore our own message echoed back
        return switch self {
        case .identityRequest:
            IdentityReply(message) != nil
        case .cvCalibrationRequest:
            (try? KMIFraming.decode(message)).map {
                $0.category == KMICategory.calibration && $0.type == KMICalibrationType.cvCalPayload
            } ?? false
        case .legacyFirmwareQuery:
            LegacyFirmwareReply(message) != nil || IdentityReply(message) != nil
        }
    }
}

public enum TwelveStepMessages {
    /// `_sx_id_req_standard` (KMI_SysexMessages.c:14)
    public static let identityRequest: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]

    /// `_fw_req_12step` (KMI_SysexMessages.c:69). Note manufacturer bytes 00 01 55.
    public static let legacyFirmwareQuery: [UInt8] = {
        var bytes: [UInt8] = [0xF0, 0x00, 0x01, 0x55, 0x7A, 0x14]
        bytes += Array(repeating: 0, count: 51)
        bytes += [0x01, 0x00, 0x00, 0x00, 0x00, 0x04, 0x40, 0x00, 0x30, 0xF7]
        return bytes
    }()

    /// `KMI_Encode(PID_12STEP2).slotEncodePacket(MSG_CAT_CALIBRATION, REQUEST_CV_CAL, 0, 0)`
    /// as sent by `cvCal::slotGetDeviceCVCalibration` (cvCal.cpp:422).
    public static let cvCalibrationRequest: [UInt8] = KMIFraming.encode(
        KMIPacket(pid: TwelveStepPID.twelveStep2.rawValue,
                  category: KMICategory.calibration,
                  type: KMICalibrationType.requestCVCal)
    )

    // Messages below are known from the source so they can be recognised and refused.
    // They are NEVER sent by this app.

    /// `_bl_12step`: enter bootloader. Forbidden.
    public static let enterBootloader: [UInt8] = [
        0xF0, 0x00, 0x01, 0x5F, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x05, 0x00, 0x04, 0x2F, 0x34, 0x00, 0x20, 0xF7,
    ]
    /// `_12s_tether_on`: changes device mode. Not sent by the diagnostics build.
    public static let tetherOn: [UInt8] = [
        0xF0, 0x00, 0x01, 0x5F, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x09, 0x00,
        0x07, 0x6A, 0x36, 0x00, 0x20, 0x04, 0x01, 0x00, 0x00, 0x6C, 0x4D, 0x00, 0x30, 0xF7,
    ]
    public static let tetherOff: [UInt8] = [
        0xF0, 0x00, 0x01, 0x5F, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x09, 0x00,
        0x07, 0x6A, 0x36, 0x00, 0x20, 0x04, 0x00, 0x00, 0x00, 0x5B, 0x7D, 0x00, 0x30, 0xF7,
    ]
    public static let standaloneOn: [UInt8] = [
        0xF0, 0x00, 0x01, 0x5F, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x09, 0x00,
        0x07, 0x6A, 0x36, 0x00, 0x20, 0x03, 0x01, 0x00, 0x00, 0x3D, 0x60, 0x00, 0x30, 0xF7,
    ]
}

/// Enforces that only allow-listed read-only messages leave the app.
public enum SendPolicy {
    public static func isAllowed(_ bytes: [UInt8]) -> Bool {
        SafeCommand.allCases.contains { $0.bytes == bytes }
    }
}

/// Parsed Universal Identity Reply, using the offsets the desktop editor reads
/// (KMI_mdm.cpp:1510-1535).
public struct IdentityReply: Equatable, Sendable {
    public let raw: [UInt8]
    public let deviceID: UInt8
    public let manufacturer: [UInt8]
    public let productID: UInt8?
    public let bootloaderMode: Bool?
    public let bootloaderVersion: [UInt8]?
    public let firmwareVersion: [UInt8]?

    public init?(_ message: [UInt8]) {
        guard message.count >= 6, message[0] == 0xF0, message[1] == 0x7E,
              message[3] == 0x06, message[4] == 0x02 else { return nil }
        raw = message
        deviceID = message[2]
        let body = message.last == 0xF7 ? Array(message.dropLast()) : message
        manufacturer = Array(body.dropFirst(5).prefix(3))
        productID = body.count > 8 ? body[8] : nil
        bootloaderMode = body.count > 9 ? body[9] == 1 : nil
        bootloaderVersion = body.count >= 15 ? Array(body[12...14]) : nil
        firmwareVersion = body.count >= 18 ? Array(body[15...17]) : nil
    }

    public var isKMI: Bool { manufacturer == kmiManufacturerID }
    public var product: TwelveStepPID? { productID.flatMap(TwelveStepPID.init(rawValue:)) }

    public var firmwareString: String? { firmwareVersion.map(Self.versionString) }
    public var bootloaderString: String? { bootloaderVersion.map(Self.versionString) }

    static func versionString(_ parts: [UInt8]) -> String {
        parts.map(String.init).joined(separator: ".")
    }

    public var summary: String {
        var parts: [String] = []
        parts.append(isKMI ? "KMI" : "Manufacturer \(Hex.string(manufacturer))")
        if let product { parts.append(product.displayName) } else if let productID { parts.append("PID \(productID)") }
        if let firmwareString { parts.append("fw \(firmwareString)") }
        if let bootloaderString { parts.append("bl \(bootloaderString)") }
        if bootloaderMode == true { parts.append("IN BOOTLOADER MODE") }
        return parts.joined(separator: " · ")
    }
}

/// Reply to the legacy firmware query (`_fw_reply_12step` found at index 1; version digits in byte 68).
public struct LegacyFirmwareReply: Equatable, Sendable {
    public static let prefix: [UInt8] = [0x00, 0x01, 0x55, 0x7A, 0x14]
    public let raw: [UInt8]
    public let firmwareVersion: [UInt8]?

    public init?(_ message: [UInt8]) {
        guard message.count > 6, message[0] == 0xF0, Array(message[1...5]) == Self.prefix else { return nil }
        raw = message
        if message.count > 68 {
            let whole = message[68]
            firmwareVersion = [0, (whole - whole % 10) / 10, whole % 10]
        } else {
            firmwareVersion = nil
        }
    }

    public var summary: String {
        "Legacy 12 Step firmware reply" + (firmwareVersion.map { " · fw \(IdentityReply.versionString($0))" } ?? "")
    }
}

/// CV calibration payload header (`cvCalData.h`): version, mode, then 2 × (6 + 61) 16-bit values.
public struct CVCalibrationPayload: Equatable, Sendable {
    public static let expectedLength = 270
    public let version: Int8
    public let calibrationMode: UInt8
    public let length: Int

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        version = Int8(bitPattern: payload[0])
        calibrationMode = payload[1]
        length = payload.count
    }

    public var summary: String {
        let mode = switch calibrationMode {
        case 0: "factory"
        case 1: "octaves"
        case 2: "notes"
        default: "mode \(calibrationMode)"
        }
        let lengthNote = length == Self.expectedLength ? "" : " (unexpected length \(length))"
        return "CV calibration v\(version), \(mode), \(length) bytes\(lengthNote)"
    }
}
