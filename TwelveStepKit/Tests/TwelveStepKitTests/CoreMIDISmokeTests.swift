import Testing
@testable import TwelveStepKit

/// Exercises the real Core MIDI transport on the host (macOS) without any hardware attached.
struct CoreMIDISmokeTests {
    @Test func startsEnumeratesAndRejectsUnknownDestination() throws {
        let transport = CoreMIDITransport()
        try transport.start()
        defer { transport.stop() }
        let snapshot = transport.snapshot()
        #expect(snapshot.sources.allSatisfy { $0.direction == .source })
        #expect(throws: TransportError.destinationNotFound(123_456_789)) {
            try transport.send(TwelveStepMessages.identityRequest, to: 123_456_789)
        }
    }

    @Test func refConRoundTripsUniqueIDs() {
        for id: EndpointID in [0, 1, -1, .max, .min, 123_456] {
            #expect(CoreMIDITransport.sourceID(from: CoreMIDITransport.refCon(for: id)) == id)
        }
    }
}
