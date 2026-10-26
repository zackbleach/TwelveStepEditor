import Foundation

/// Conversion between MIDI 1.0 byte-stream messages and Universal MIDI Packets (MIDI 1.0 protocol),
/// as used by Core MIDI's event-list APIs. Pure functions so they can be unit-tested.
public enum UMP {
    /// Number of 32-bit words for each UMP message type (top nibble of the first word).
    static let wordsPerMessageType: [Int] = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    public static func wordCount(forFirstWord word: UInt32) -> Int {
        wordsPerMessageType[Int(word >> 28)]
    }

    /// Encodes a complete SysEx message (F0 … F7) as UMP SysEx7 packets (2 words each, 6 bytes per packet).
    public static func sysExWords(_ message: [UInt8], group: UInt8 = 0) -> [UInt32] {
        var payload = message[...]
        if payload.first == 0xF0 { payload = payload.dropFirst() }
        if payload.last == 0xF7 { payload = payload.dropLast() }
        let bytes = Array(payload)

        let chunks: [[UInt8]] = bytes.isEmpty
            ? [[]]
            : stride(from: 0, to: bytes.count, by: 6).map { Array(bytes[$0..<min($0 + 6, bytes.count)]) }

        var words: [UInt32] = []
        for (index, chunk) in chunks.enumerated() {
            let status: UInt32
            switch (chunks.count, index) {
            case (1, _): status = 0x0 // complete in one packet
            case (_, 0): status = 0x1 // start
            case (_, chunks.count - 1): status = 0x3 // end
            default: status = 0x2 // continue
            }
            var b = chunk + Array(repeating: 0, count: 6 - chunk.count)
            b = b.map { $0 & 0x7F }
            let word0 = 0x3000_0000 | UInt32(group & 0xF) << 24 | status << 20 | UInt32(chunk.count) << 16
                | UInt32(b[0]) << 8 | UInt32(b[1])
            let word1 = UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5])
            words += [word0, word1]
        }
        return words
    }

    /// Encodes a MIDI 1.0 channel voice message (2 or 3 bytes) as a single UMP word.
    public static func channelVoiceWord(_ message: [UInt8], group: UInt8 = 0) -> UInt32? {
        guard let status = message.first, (0x80...0xEF).contains(status) else { return nil }
        let d1 = message.count > 1 ? message[1] & 0x7F : 0
        let d2 = message.count > 2 ? message[2] & 0x7F : 0
        return 0x2000_0000 | UInt32(group & 0xF) << 24 | UInt32(status) << 16 | UInt32(d1) << 8 | UInt32(d2)
    }
}

/// Reassembles MIDI 1.0 byte-stream messages from incoming UMP words.
/// Keeps per-group SysEx state, so feed it the words of a single source in order.
public struct UMPParser: Sendable {
    public enum Event: Equatable, Sendable {
        case message([UInt8])
        /// UMP that has no MIDI 1.0 byte-stream equivalent (e.g. MIDI 2.0 or utility messages).
        case unsupported(words: [UInt32])
        /// A SysEx stream was malformed (e.g. continue without start); partial bytes included.
        case malformedSysEx(partial: [UInt8])
    }

    private var sysExBuffers: [UInt8: [UInt8]] = [:]
    /// Limit to protect against an unterminated stream growing without bound.
    public var maxSysExLength = 256 * 1024

    public init() {}

    public mutating func parse(_ words: [UInt32]) -> [Event] {
        var events: [Event] = []
        var index = 0
        while index < words.count {
            let first = words[index]
            let count = UMP.wordCount(forFirstWord: first)
            guard index + count <= words.count else {
                events.append(.unsupported(words: Array(words[index...])))
                break
            }
            let packet = Array(words[index..<(index + count)])
            index += count
            events += handle(packet)
        }
        return events
    }

    private mutating func handle(_ packet: [UInt32]) -> [Event] {
        let word0 = packet[0]
        let messageType = word0 >> 28
        let group = UInt8((word0 >> 24) & 0xF)

        switch messageType {
        case 0x0: // utility (NOOP, JR timestamps): nothing to report
            return []
        case 0x1: // system common / realtime
            let status = UInt8((word0 >> 16) & 0xFF)
            let d1 = UInt8((word0 >> 8) & 0x7F)
            let d2 = UInt8(word0 & 0x7F)
            switch status {
            case 0xF1, 0xF3: return [.message([status, d1])]
            case 0xF2: return [.message([status, d1, d2])]
            default: return [.message([status])]
            }
        case 0x2: // MIDI 1.0 channel voice
            let status = UInt8((word0 >> 16) & 0xFF)
            let d1 = UInt8((word0 >> 8) & 0x7F)
            let d2 = UInt8(word0 & 0x7F)
            switch status & 0xF0 {
            case 0xC0, 0xD0: return [.message([status, d1])]
            default: return [.message([status, d1, d2])]
            }
        case 0x3: // SysEx7
            let status = (word0 >> 20) & 0xF
            let count = min(Int((word0 >> 16) & 0xF), 6)
            let word1 = packet[1]
            let all: [UInt8] = [
                UInt8((word0 >> 8) & 0x7F), UInt8(word0 & 0x7F),
                UInt8((word1 >> 24) & 0x7F), UInt8((word1 >> 16) & 0x7F),
                UInt8((word1 >> 8) & 0x7F), UInt8(word1 & 0x7F),
            ]
            let bytes = Array(all.prefix(count))
            switch status {
            case 0x0:
                var events: [Event] = []
                if let stale = sysExBuffers.removeValue(forKey: group) { events.append(.malformedSysEx(partial: stale)) }
                events.append(.message([0xF0] + bytes + [0xF7]))
                return events
            case 0x1:
                var events: [Event] = []
                if let stale = sysExBuffers.removeValue(forKey: group) { events.append(.malformedSysEx(partial: stale)) }
                sysExBuffers[group] = [0xF0] + bytes
                return events
            case 0x2, 0x3:
                guard var buffer = sysExBuffers[group] else {
                    return [.malformedSysEx(partial: bytes)]
                }
                buffer += bytes
                if status == 0x3 {
                    sysExBuffers[group] = nil
                    return [.message(buffer + [0xF7])]
                }
                if buffer.count > maxSysExLength {
                    sysExBuffers[group] = nil
                    return [.malformedSysEx(partial: buffer)]
                }
                sysExBuffers[group] = buffer
                return []
            default:
                return [.unsupported(words: packet)]
            }
        default:
            return [.unsupported(words: packet)]
        }
    }
}
