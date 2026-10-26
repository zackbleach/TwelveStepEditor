import Testing
@testable import TwelveStepKit

struct UMPTests {
    @Test(arguments: [0, 1, 5, 6, 7, 12, 13, 65, 300])
    func sysExRoundTrip(payloadLength: Int) {
        let message: [UInt8] = [0xF0] + (0..<payloadLength).map { UInt8($0 % 128) } + [0xF7]
        var parser = UMPParser()
        let events = parser.parse(UMP.sysExWords(message))
        #expect(events == [.message(message)])
    }

    @Test func sysExPacketStatusSequence() {
        let words = UMP.sysExWords([0xF0] + Array(repeating: 1, count: 13) + [0xF7])
        let statuses = stride(from: 0, to: words.count, by: 2).map { (words[$0] >> 20) & 0xF }
        #expect(statuses == [1, 2, 3])
        let counts = stride(from: 0, to: words.count, by: 2).map { (words[$0] >> 16) & 0xF }
        #expect(counts == [6, 6, 1])
    }

    @Test func goldenSysExRoundTripsThroughUMP() {
        var parser = UMPParser()
        #expect(parser.parse(UMP.sysExWords(TwelveStepMessages.legacyFirmwareQuery)) == [.message(TwelveStepMessages.legacyFirmwareQuery)])
    }

    @Test func parsesChannelVoiceAndRealtime() {
        var parser = UMPParser()
        let noteOn = UMP.channelVoiceWord([0x90, 60, 100])!
        let program = UMP.channelVoiceWord([0xC3, 5])!
        let clock: UInt32 = 0x10F8_0000
        #expect(parser.parse([noteOn, program, clock]) == [.message([0x90, 60, 100]), .message([0xC3, 5]), .message([0xF8])])
    }

    @Test func interleavedChannelMessagesDuringSysEx() {
        var parser = UMPParser()
        let sysex = UMP.sysExWords([0xF0] + Array(repeating: 2, count: 12) + [0xF7])
        let note = UMP.channelVoiceWord([0x80, 60, 0])!
        let words = Array(sysex[0..<2]) + [note] + Array(sysex[2...])
        #expect(parser.parse(words) == [.message([0x80, 60, 0]), .message([0xF0] + Array(repeating: 2, count: 12) + [0xF7])])
    }

    @Test func sysExSplitAcrossCallbacks() {
        var parser = UMPParser()
        let message: [UInt8] = [0xF0] + Array(repeating: 3, count: 20) + [0xF7]
        let words = UMP.sysExWords(message)
        #expect(parser.parse(Array(words[0..<4])).isEmpty)
        #expect(parser.parse(Array(words[4...])) == [.message(message)])
    }

    @Test func continueWithoutStartIsReportedAsMalformed() {
        var parser = UMPParser()
        let words = UMP.sysExWords([0xF0] + Array(repeating: 4, count: 13) + [0xF7])
        let events = parser.parse(Array(words[2...]))
        #expect(events.first == .malformedSysEx(partial: [4, 4, 4, 4, 4, 4]))
    }
}
