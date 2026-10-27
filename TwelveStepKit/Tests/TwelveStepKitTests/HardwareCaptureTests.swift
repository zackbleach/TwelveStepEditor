// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Testing
@testable import TwelveStepKit

/// Vectors captured from real hardware: a 12 Step2 (fw 1.0.9, bl 1.0.0) on an iPhone 16 Pro
/// running iOS 26.6.2, 2026-10-24 (12step-diagnostics-20261024-212414.txt).
struct HardwareCaptureTests {
    static let identityReply = bytes("F0 7E 00 06 02 00 01 5F 16 00 00 00 01 00 00 01 00 09 F7")
    static let cvCalibrationReply = bytes("F0 00 01 5F 00 16 00 00 00 00 00 01 01 05 01 0E 4B 7B 01 10 00 00 40 03 02 06 0C 00 09 17 0C 23 0F 5B 00 00 3D 03 02 06 17 09 27 00 0C 39 0F 66 00 00 00 00 40 00 00 00 40 01 00 14 01 40 01 00 01 40 02 28 00 02 40 02 00 02 40 50 03 02 03 42 03 02 03 20 42 04 02 04 42 04 02 41 04 42 05 02 05 42 05 02 02 05 42 06 0C 06 4C 05 06 0C 06 4C 07 0C 07 0A 4C 07 0C 07 4C 08 0C 14 08 4C 08 0C 08 4C 09 28 17 09 58 09 19 09 5A 50 0A 1B 0A 5C 0A 1D 0A 20 5E 0B 1F 0B 60 0B 21 41 0B 62 0C 23 0C 67 0C 02 2B 0C 6F 0D 33 0D 77 05 0D 3B 0D 7F 0E 43 0E 0A 07 0E 4B 0F 0F 0F 5B 05 00 00 00 3D 00 00 00 20 40 01 00 01 40 01 00 41 01 40 02 00 02 40 02 02 00 02 40 03 02 03 43 05 03 04 03 45 04 06 04 0A 47 04 08 04 49 05 0A 14 05 4B 05 0C 05 4D 06 28 17 06 58 06 19 06 5A 50 07 1B 07 5C 07 1D 07 20 5E 08 1F 08 60 08 21 41 08 62 09 27 09 68 09 02 29 09 6A 0A 2B 0A 6C 05 0A 2D 0A 6E 0B 2F 0B 0A 70 0B 31 0B 72 0C 39 14 0C 7C 0C 3F 0D 02 0D 08 45 0D 08 0D 4B 0E 0E 14 0E 51 0E 14 0E 57 0F 28 1A 0F 66 07 67 00 00 00 F7")

    static func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    @Test func identityReplyDecodes() throws {
        let reply = try #require(IdentityReply(Self.identityReply))
        #expect(reply.summary == "KMI · 12 Step2 · fw 1.0.9 · bl 1.0.0")
    }

    @Test func cvCalibrationReplyDecodesAsSingleBlock() throws {
        let (packet, format) = try KMIFraming.decodeDetectingFormat(Self.cvCalibrationReply)
        #expect(format == .singleBlock)
        #expect(packet.pid == 22)
        #expect(packet.category == KMICategory.calibration && packet.type == KMICalibrationType.cvCalPayload)
        #expect(packet.blocks.count == 1)
        let payload = try #require(CVCalibrationPayload(packet.blocks[0]))
        #expect(payload.length == CVCalibrationPayload.expectedLength)
        #expect(payload.version == 1)
        #expect(payload.calibrationMode == 0)
    }

    @Test func singleBlockEncoderReproducesCapturedReplyExactly() throws {
        let packet = try KMIFraming.decode(Self.cvCalibrationReply)
        let encoded = KMIFraming.encodeSingleBlock(pid: packet.pid, packetType: packet.packetType, payload: packet.blocks[0])
        #expect(encoded == Self.cvCalibrationReply)
    }

    @Test func capturedReplyIsRecognisedAsAnswerToRequest() {
        #expect(SafeCommand.cvCalibrationRequest.isReply(Self.cvCalibrationReply))
    }

    @Test func corruptedCapturedReplyIsRejected() {
        var corrupted = Self.cvCalibrationReply
        corrupted[40] ^= 0x01
        #expect(throws: KMIFramingError.self) { try KMIFraming.decode(corrupted) }
    }

    @Test(arguments: [0, 1, 5, 6, 7, 191, 270])
    func singleBlockRoundTrips(length: Int) throws {
        let payload = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 0x80) }
        let message = KMIFraming.encodeSingleBlock(pid: 22, packetType: 0x0105, payload: payload)
        let (packet, format) = try KMIFraming.decodeDetectingFormat(message)
        #expect(packet.blocks == (payload.isEmpty ? [] : [payload]))
        #expect(length == 0 || format == .singleBlock)
    }
}
