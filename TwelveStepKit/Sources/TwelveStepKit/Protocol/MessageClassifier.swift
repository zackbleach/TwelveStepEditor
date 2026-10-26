import Foundation

public enum Hex {
    public static func string<C: Collection>(_ bytes: C, separator: String = " ") -> String where C.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}

/// Broad grouping used to filter the monitor.
public enum TrafficKind: String, Sendable, CaseIterable {
    case performance   // channel voice messages (notes, CC, PC, …)
    case realtime      // clock, active sensing, …
    case configuration // SysEx recognised as 12 Step / KMI protocol
    case sysex         // other SysEx
    case other

    public var label: String {
        switch self {
        case .performance: "Performance"
        case .realtime: "Realtime"
        case .configuration: "Config"
        case .sysex: "SysEx"
        case .other: "Other"
        }
    }
}

public struct Classification: Equatable, Sendable {
    public let kind: TrafficKind
    public let summary: String
}

public enum MessageClassifier {
    public static func classify(_ message: [UInt8]) -> Classification {
        guard let status = message.first else { return Classification(kind: .other, summary: "Empty message") }

        switch status {
        case 0x80...0xEF:
            return Classification(kind: .performance, summary: describeChannelMessage(message))
        case 0xF0:
            return classifySysEx(message)
        case 0xF8...0xFF:
            return Classification(kind: .realtime, summary: realtimeName(status))
        default:
            return Classification(kind: .other, summary: String(format: "System common 0x%02X", status))
        }
    }

    static func classifySysEx(_ message: [UInt8]) -> Classification {
        if message == TwelveStepMessages.identityRequest {
            return Classification(kind: .configuration, summary: "Identity request")
        }
        if let reply = IdentityReply(message) {
            return Classification(kind: .configuration, summary: "Identity reply · \(reply.summary)")
        }
        if let legacy = LegacyFirmwareReply(message) {
            let isQuery = message == TwelveStepMessages.legacyFirmwareQuery
            return Classification(kind: .configuration, summary: isQuery ? "Legacy firmware query" : legacy.summary)
        }
        if KMIFraming.isKMISysEx(message) {
            return Classification(kind: .configuration, summary: describeKMIPacket(message))
        }
        return Classification(kind: .sysex, summary: "SysEx, \(message.count) bytes")
    }

    static func describeKMIPacket(_ message: [UInt8]) -> String {
        do {
            let packet = try KMIFraming.decode(message)
            let payloadBytes = packet.blocks.reduce(0) { $0 + $1.count }
            let head = "KMI packet PID \(packet.pid) type 0x\(String(format: "%04X", packet.packetType))"
            if packet.category == KMICategory.calibration {
                switch packet.type {
                case KMICalibrationType.requestCVCal:
                    return "\(head) · CV calibration request"
                case KMICalibrationType.cvCalPayload:
                    let detail = packet.blocks.first.flatMap(CVCalibrationPayload.init)?.summary ?? "empty"
                    return "\(head) · \(detail)"
                default:
                    return "\(head) · calibration type \(packet.type), \(payloadBytes) bytes"
                }
            }
            if packet.category == KMICategory.preset {
                switch packet.type {
                case KMIPresetType.requestPreset:
                    return "\(head) · preset request (experimental)"
                case KMIPresetType.presetPayload:
                    return "\(head) · PRESET PAYLOAD, \(payloadBytes) bytes (preset IMAGE struct is 191)"
                default:
                    return "\(head) · preset category type \(packet.type), \(payloadBytes) bytes"
                }
            }
            if packet.packetType == 9, let first = packet.blocks.first, first.count >= 2 {
                let saType = UInt16(first[0]) << 8 | UInt16(first[1])
                let names = ["preset image", "preset set", "settings", "standalone on/off", "tether on/off"]
                let name = saType < names.count ? names[Int(saType)] : "standalone type \(saType)"
                return "\(head) · \(name), \(payloadBytes) bytes"
            }
            return "\(head) · \(packet.blocks.count) block(s), \(payloadBytes) bytes"
        } catch {
            return "KMI SysEx (decode failed: \(error))"
        }
    }

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Note name using the desktop editor's convention, middle C (60) = C3.
    public static func noteName(_ note: UInt8) -> String {
        "\(noteNames[Int(note) % 12])\(Int(note) / 12 - 2)"
    }

    static func describeChannelMessage(_ message: [UInt8]) -> String {
        let status = message[0]
        let channel = Int(status & 0x0F) + 1
        let d1 = message.count > 1 ? message[1] : 0
        let d2 = message.count > 2 ? message[2] : 0
        switch status & 0xF0 {
        case 0x80: return "Note Off ch\(channel) \(noteName(d1)) (\(d1)) vel \(d2)"
        case 0x90 where d2 == 0: return "Note Off ch\(channel) \(noteName(d1)) (\(d1)) [vel 0]"
        case 0x90: return "Note On ch\(channel) \(noteName(d1)) (\(d1)) vel \(d2)"
        case 0xA0: return "Poly AT ch\(channel) \(noteName(d1)) = \(d2)"
        case 0xB0:
            let nrpnPart = [99: " (NRPN MSB)", 98: " (NRPN LSB)", 6: " (Data MSB)", 38: " (Data LSB)"][Int(d1)] ?? ""
            return "CC ch\(channel) #\(d1)\(nrpnPart) = \(d2)"
        case 0xC0: return "Program Change ch\(channel) \(d1) (shown as \(Int(d1) + 1) on 1-based devices)"
        case 0xD0: return "Channel Pressure ch\(channel) = \(d1)"
        case 0xE0: return "Pitch Bend ch\(channel) = \(Int(d2) << 7 | Int(d1))"
        default: return "Channel message"
        }
    }

    static func realtimeName(_ status: UInt8) -> String {
        switch status {
        case 0xF8: "Clock"
        case 0xFA: "Start"
        case 0xFB: "Continue"
        case 0xFC: "Stop"
        case 0xFE: "Active Sensing"
        case 0xFF: "Reset"
        default: String(format: "Realtime 0x%02X", status)
        }
    }
}
