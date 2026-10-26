import Testing
@testable import TwelveStepKit

struct PresetProbeTests {
    @Test func presetProbeIsTheOnlyExperimentalCommand() {
        #expect(SafeCommand.allCases.filter(\.isExperimental) == [.presetRequestProbe])
    }

    @Test func probeIsFramedLikeTheCVCalibrationRequest() throws {
        let probe = TwelveStepMessages.presetRequestProbe
        #expect(Hex.string(probe) == "F0 00 01 5F 00 16 00 00 00 00 00 01 02 00 00 04 29 2C 00 00 F7")
        #expect(Array(probe[1...5]) == [0x00, 0x01, 0x5F, 0x00, 22])
        let packet = try KMIFraming.decode(probe)
        #expect(packet.category == KMICategory.preset && packet.type == KMIPresetType.requestPreset)
        #expect(packet.blocks.isEmpty)
        // Same length and header as the CV request; only the packet type and preamble CRC differ.
        #expect(probe.count == TwelveStepMessages.cvCalibrationRequest.count)
    }

    @Test func otherPresetCategoryMessagesAreStillRejected() {
        let payloadWrite = KMIFraming.encode(KMIPacket(pid: 22, category: KMICategory.preset,
                                                       type: KMIPresetType.presetPayload, payload: Array(repeating: 0, count: 191)))
        let requestWithIndex = KMIFraming.encode(KMIPacket(pid: 22, category: KMICategory.preset,
                                                           type: KMIPresetType.requestPreset, payload: [0]))
        #expect(!SendPolicy.isAllowed(payloadWrite))
        #expect(!SendPolicy.isAllowed(requestWithIndex))
    }

    @Test func probeAcceptsAnyPresetCategoryReplyButNotCalibration() {
        let presetReply = KMIFraming.encodeSingleBlock(pid: 22, packetType: 0x0201, payload: [1, 2, 3])
        let oddReply = KMIFraming.encodeSingleBlock(pid: 22, packetType: 0x0207, payload: [])
        #expect(SafeCommand.presetRequestProbe.isReply(presetReply))
        #expect(SafeCommand.presetRequestProbe.isReply(oddReply))
        #expect(!SafeCommand.presetRequestProbe.isReply(HardwareCaptureTests.cvCalibrationReply))
        #expect(!SafeCommand.presetRequestProbe.isReply(TwelveStepMessages.presetRequestProbe))
    }

    @MainActor @Test func sessionCapturesSimulatedPresetReply() async {
        var behavior = MockMIDITransport.Behavior()
        behavior.presetProbeReply = Array(repeating: 0x42, count: 191)
        let session = DiagnosticsSession(transport: MockMIDITransport(behavior: behavior))
        session.start()
        let result = await session.run(.presetRequestProbe)
        guard case .reply(_, _, let decoded) = result.outcome else {
            Issue.record("expected a reply, got \(result.outcome)")
            return
        }
        #expect(decoded.contains("PRESET PAYLOAD, 191 bytes"))
        #expect(session.log.entries.contains { $0.summary.contains("EXPERIMENTAL") })
    }
}
