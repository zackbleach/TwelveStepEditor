// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Swift translation of the KMI SysEx framing from the official 12 Step editor:
//   QT/presetimageformatting/DeviceManager/sysex.cpp
//   QT/inc/KMI_KMDM/kmiSysEx/kmiSysEx.cpp
// Original code Copyright (c) 2025 KMI Music, Inc. (Muse Kinetics), MPL-2.0.
// https://github.com/Muse-Kinetics/12-step-editor-qt6

import Foundation

/// CRC-16 (CCITT polynomial, seed 0xFFFF) exactly as implemented by KMI's `crc_byte(char val)`.
///
/// The C implementation takes a *signed* `char`, so bytes >= 0x80 are sign-extended before
/// being XORed into the register. That quirk changes results and is reproduced here.
public enum KMICRC {
    public static let seed: UInt16 = 0xFFFF

    public static func update(_ crc: UInt16, _ byte: UInt8) -> UInt16 {
        let signedValue = Int32(Int8(bitPattern: byte))
        let temp = UInt16(truncatingIfNeeded: Int32(crc >> 8) ^ signedValue)
        var result = crc << 8
        var quick = temp ^ (temp >> 4)
        result ^= quick
        quick <<= 5
        result ^= quick
        quick <<= 7
        result ^= quick
        return result
    }

    public static func checksum<S: Sequence>(_ bytes: S, seed: UInt16 = seed) -> UInt16 where S.Element == UInt8 {
        bytes.reduce(seed, update)
    }
}

/// KMI 8-bit -> 7-bit packing: every 7 data bytes are followed by one byte holding their MSBs
/// (bit i = MSB of byte i). A trailing partial group is zero-padded to 7 bytes.
public enum SevenBitCodec {
    public static func encode(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count + data.count / 7 + 8)
        var index = 0
        while index < data.count {
            var group = Array(data[index..<min(index + 7, data.count)])
            group += Array(repeating: 0, count: 7 - group.count)
            var highBits: UInt8 = 0
            for (bit, byte) in group.enumerated() {
                out.append(byte & 0x7F)
                if byte & 0x80 != 0 { highBits |= 1 << bit }
            }
            out.append(highBits)
            index += 7
        }
        return out
    }

    /// Decodes complete 8-byte groups. A trailing partial group is ignored, matching `KMI_Decode`.
    public static func decode(_ encoded: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(encoded.count)
        var index = 0
        while index + 8 <= encoded.count {
            let highBits = encoded[index + 7]
            for bit in 0..<7 {
                var byte = encoded[index + bit]
                if highBits & (1 << bit) != 0 { byte |= 0x80 }
                out.append(byte)
            }
            index += 8
        }
        return out
    }
}

/// KMI manufacturer ID bytes as used in SysEx headers (`midi.h` kmi_id_1..3).
public let kmiManufacturerID: [UInt8] = [0x00, 0x01, 0x5F]

/// A KMI framed packet: a 16-bit packet type followed by zero or more chained data blocks.
public struct KMIPacket: Equatable, Sendable {
    /// USB/MIDI product ID byte in the SysEx header (20 = 12 Step, 22 = 12 Step2).
    public var pid: UInt8
    /// Legacy packets use e.g. 9 (`SX_PACKET_STANDALONE`); newer ones use `(category << 8) | type`.
    public var packetType: UInt16
    public var blocks: [[UInt8]]

    public init(pid: UInt8, packetType: UInt16, blocks: [[UInt8]] = []) {
        self.pid = pid
        self.packetType = packetType
        self.blocks = blocks
    }

    public init(pid: UInt8, category: UInt8, type: UInt8, payload: [UInt8]? = nil) {
        self.init(pid: pid, packetType: UInt16(category) << 8 | UInt16(type), blocks: payload.map { [$0] } ?? [])
    }

    public var category: UInt8 { UInt8(packetType >> 8) }
    public var type: UInt8 { UInt8(packetType & 0xFF) }
}

public enum KMIFramingError: Error, Equatable, Sendable {
    case notKMISysEx
    case missingStartMarker
    case truncated(decodedBytes: Int)
    case preambleCRCMismatch(expected: UInt16, computed: UInt16)
    case blockCRCMismatch(block: Int, expected: UInt16, computed: UInt16)
}

public enum KMIFraming {
    static let tailLength = 4 // length[msb/lsb], crc[msb/lsb]
    static let startMarker: UInt8 = 0x01

    /// Encodes a packet as a complete SysEx message (F0 … F7).
    ///
    /// - Parameter headerPadding: zero bytes between the format byte and the 0x01 start marker.
    ///   `KMI_Encode` and the hard-coded tether messages use 4; the legacy preset encoder uses 10.
    public static func encode(_ packet: KMIPacket, headerPadding: Int = 4) -> [UInt8] {
        var stream: [UInt8] = []
        var crc = KMICRC.seed

        func putCRC16(_ value: UInt16) {
            for byte in [UInt8(value >> 8), UInt8(value & 0xFF)] {
                crc = KMICRC.update(crc, byte)
                stream.append(byte)
            }
        }
        func put16(_ value: UInt16) {
            stream.append(UInt8(value >> 8))
            stream.append(UInt8(value & 0xFF))
        }

        // Preamble
        putCRC16(packet.packetType)
        putCRC16(UInt16((packet.blocks.first?.count ?? 0) + tailLength))
        put16(crc)

        // Chained data blocks: data, next block length (+tail, or 0), crc over both.
        for (index, block) in packet.blocks.enumerated() {
            crc = KMICRC.seed
            for byte in block {
                crc = KMICRC.update(crc, byte)
                stream.append(byte)
            }
            let next = index + 1 < packet.blocks.count ? packet.blocks[index + 1].count + tailLength : 0
            putCRC16(UInt16(next))
            put16(crc)
        }

        var message: [UInt8] = [0xF0] + kmiManufacturerID + [0x00, packet.pid, 0x00]
        message += Array(repeating: 0, count: headerPadding)
        message.append(startMarker)
        message += SevenBitCodec.encode(stream)
        message.append(0xF7)
        return message
    }

    /// True if the message carries the KMI manufacturer header.
    public static func isKMISysEx(_ message: [UInt8]) -> Bool {
        message.count > 6 && message[0] == 0xF0 && Array(message[1...3]) == kmiManufacturerID
    }

    /// The two block layouts seen on the wire.
    public enum Format: Equatable, Sendable {
        /// Host → device (`KMI_Encode`): preamble length = data + 4; each block is followed by the
        /// next block's length (+4, or 0) and a CRC over data + next length.
        case chained
        /// Device → host, as parsed by the desktop's `KMI_Decode`: preamble length = data length;
        /// one block followed only by a CRC over the data. Confirmed on a 12 Step2 (fw 1.0.9)
        /// CV calibration reply captured on 2026-10-24.
        case singleBlock
    }

    /// Encodes a packet in the device → host single-block layout. Used by the mock transport and
    /// tests to reproduce real device replies; the app never sends this layout.
    public static func encodeSingleBlock(pid: UInt8, packetType: UInt16, payload: [UInt8], headerPadding: Int = 4) -> [UInt8] {
        var stream: [UInt8] = [UInt8(packetType >> 8), UInt8(packetType & 0xFF),
                               UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        let preambleCRC = KMICRC.checksum(stream)
        stream += [UInt8(preambleCRC >> 8), UInt8(preambleCRC & 0xFF)]
        let dataCRC = KMICRC.checksum(payload)
        stream += payload + [UInt8(dataCRC >> 8), UInt8(dataCRC & 0xFF)]

        var message: [UInt8] = [0xF0] + kmiManufacturerID + [0x00, pid, 0x00]
        message += Array(repeating: 0, count: headerPadding)
        message.append(startMarker)
        message += SevenBitCodec.encode(stream)
        message.append(0xF7)
        return message
    }

    /// Decodes a KMI framed SysEx message in either layout, verifying all CRCs.
    public static func decode(_ message: [UInt8]) throws -> KMIPacket {
        try decodeDetectingFormat(message).packet
    }

    /// Tries the chained layout first, then the single-block layout. Chained-first matters: a
    /// chained packet read as single-block can pass its CRC by construction (the CRC residue),
    /// whereas a single-block packet read as chained only passes by a 1-in-65536 coincidence.
    public static func decodeDetectingFormat(_ message: [UInt8]) throws -> (packet: KMIPacket, format: Format) {
        guard isKMISysEx(message) else { throw KMIFramingError.notKMISysEx }
        let pid = message[5]
        let end = message.last == 0xF7 ? message.count - 1 : message.count

        guard let markerIndex = message[6..<end].firstIndex(of: startMarker) else {
            throw KMIFramingError.missingStartMarker
        }
        let stream = SevenBitCodec.decode(Array(message[(markerIndex + 1)..<end]))

        let chainedError: Error
        do {
            return (try decodeChained(stream, pid: pid), .chained)
        } catch {
            chainedError = error
        }
        do {
            return (try decodeSingleBlock(stream, pid: pid), .singleBlock)
        } catch KMIFramingError.truncated {
            throw chainedError // too short for single-block, so the chained error is more informative
        }
    }

    private static func readPreamble(_ stream: [UInt8]) throws -> (packetType: UInt16, length: UInt16) {
        guard stream.count >= 6 else { throw KMIFramingError.truncated(decodedBytes: stream.count) }
        let packetType = UInt16(stream[0]) << 8 | UInt16(stream[1])
        let length = UInt16(stream[2]) << 8 | UInt16(stream[3])
        let preambleCRC = UInt16(stream[4]) << 8 | UInt16(stream[5])
        let computed = KMICRC.checksum(stream[0..<4])
        guard preambleCRC == computed else {
            throw KMIFramingError.preambleCRCMismatch(expected: preambleCRC, computed: computed)
        }
        return (packetType, length)
    }

    private static func decodeSingleBlock(_ stream: [UInt8], pid: UInt8) throws -> KMIPacket {
        let (packetType, length) = try readPreamble(stream)
        let dataEnd = 6 + Int(length)
        guard dataEnd + 2 <= stream.count else { throw KMIFramingError.truncated(decodedBytes: stream.count) }
        let block = Array(stream[6..<dataEnd])
        let expected = UInt16(stream[dataEnd]) << 8 | UInt16(stream[dataEnd + 1])
        let computed = KMICRC.checksum(block)
        guard expected == computed else {
            throw KMIFramingError.blockCRCMismatch(block: 0, expected: expected, computed: computed)
        }
        return KMIPacket(pid: pid, packetType: packetType, blocks: block.isEmpty ? [] : [block])
    }

    private static func decodeChained(_ stream: [UInt8], pid: UInt8) throws -> KMIPacket {
        let (packetType, firstLength) = try readPreamble(stream)
        var length = firstLength
        var cursor = 6

        func read16() throws -> UInt16 {
            guard cursor + 2 <= stream.count else { throw KMIFramingError.truncated(decodedBytes: stream.count) }
            defer { cursor += 2 }
            return UInt16(stream[cursor]) << 8 | UInt16(stream[cursor + 1])
        }

        var blocks: [[UInt8]] = []
        // A zero-length preamble (length == tail) with nothing following means "no data blocks"
        // (e.g. requests from KMI_Encode). Otherwise follow the chain until next length == 0.
        let remainingAfterPreamble = stream.count - cursor
        if Int(length) == tailLength && remainingAfterPreamble < tailLength {
            return KMIPacket(pid: pid, packetType: packetType, blocks: [])
        }
        while length != 0 {
            let dataLength = Int(length) - tailLength
            guard dataLength >= 0, cursor + dataLength <= stream.count else {
                throw KMIFramingError.truncated(decodedBytes: stream.count)
            }
            let block = Array(stream[cursor..<(cursor + dataLength)])
            cursor += dataLength
            let nextLength = try read16()
            let blockCRC = try read16()
            let computed = KMICRC.checksum(block + [UInt8(nextLength >> 8), UInt8(nextLength & 0xFF)])
            guard blockCRC == computed else {
                throw KMIFramingError.blockCRCMismatch(block: blocks.count, expected: blockCRC, computed: computed)
            }
            blocks.append(block)
            length = nextLength
        }
        return KMIPacket(pid: pid, packetType: packetType, blocks: blocks)
    }
}
