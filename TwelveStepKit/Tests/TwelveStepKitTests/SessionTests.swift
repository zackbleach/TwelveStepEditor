// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Testing
@testable import TwelveStepKit

@MainActor
struct SessionTests {
    @Test func autoSelectsControlDestination() {
        let session = DiagnosticsSession(transport: MockMIDITransport())
        session.start()
        #expect(session.selectedDestinationID == MockMIDITransport.controlDestinationID)
        #expect(session.status == .detected(endpointName: "12Step Control Surface"))
    }

    @Test func identityQueryReceivesAndDecodesReply() async {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()

        let result = await session.run(.identityRequest)
        guard case .reply(let bytes, _, let decoded) = result.outcome else {
            Issue.record("Expected reply, got \(result.outcome)")
            return
        }
        #expect(IdentityReply(bytes)?.firmwareString == "1.0.9")
        #expect(decoded.contains("12 Step2"))
        #expect(mock.sentMessages == [TwelveStepMessages.identityRequest])
        if case .identified = session.status {} else { Issue.record("Status should be identified") }
    }

    @Test func cvCalibrationReplyPassesCRC() async {
        let session = DiagnosticsSession(transport: MockMIDITransport())
        session.start()
        let result = await session.run(.cvCalibrationRequest)
        guard case .reply(_, _, let decoded) = result.outcome else {
            Issue.record("Expected reply, got \(result.outcome)")
            return
        }
        #expect(decoded.hasPrefix("CRC OK"))
        #expect(decoded.contains("270 bytes"))
    }

    @Test func reportsTimeoutWhenDeviceIsSilent() async {
        var behavior = MockMIDITransport.Behavior()
        behavior.answersIdentity = false
        let session = DiagnosticsSession(transport: MockMIDITransport(behavior: behavior))
        session.queryTimeout = 0.2
        session.start()
        let result = await session.run(.identityRequest)
        #expect(result.outcome == .timeout(seconds: 0.2))
    }

    @Test func failsWithoutDestination() async {
        let session = DiagnosticsSession(transport: MockMIDITransport(connected: false))
        session.start()
        #expect(session.status == .noDevice)
        let result = await session.run(.identityRequest)
        #expect(result.outcome == .failed("No MIDI destination selected."))
    }

    @Test func tracksDisconnection() async throws {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()
        _ = await session.run(.identityRequest)
        mock.setConnected(false)
        try await waitUntil { session.status == .noDevice }
        #expect(session.selectedDestinationID == nil)
        #expect(session.log.entries.contains { $0.summary.contains("disappeared") })
    }

    @Test func logsIncomingPerformanceMIDI() async throws {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()
        mock.simulateIncoming([0x90, 60, 90])
        try await waitUntil { session.log.entries.contains { $0.kind == .performance } }
    }

    @Test func pausedMonitorStillLogsConfigurationTraffic() async throws {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()
        session.isMonitorPaused = true
        mock.simulateIncoming([0x90, 60, 90])
        _ = await session.run(.identityRequest)
        #expect(!session.log.entries.contains { $0.kind == .performance })
        #expect(session.log.entries.contains { $0.direction == .received && $0.kind == .configuration })
    }

    @Test func reportFlagsSimulatedData() {
        let session = DiagnosticsSession(transport: MockMIDITransport())
        session.start()
        let report = session.diagnosticReport(appVersion: "test", osVersion: "test", deviceModel: "test")
        #expect(report.contains("SIMULATED DATA, NOT HARDWARE"))
        #expect(report.contains("→ 12 Step control"))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor
struct LogMirrorTests {
    @Test func onAppendSeesEveryEntryInOrder() {
        let log = DiagnosticLog()
        var mirrored: [String] = []
        log.onAppend = { mirrored.append($0.summary) }
        log.append(.info, summary: "one")
        log.appendBatch([(.received, [0x90, 0x3C, 0x7F], "port", .performance, "two", Date()),
                         (.received, [0x80, 0x3C, 0x00], "port", .performance, "three", Date())])
        #expect(mirrored == ["one", "two", "three"])
    }
}

@MainActor
struct AutoIdentifyTests {
    @Test func identifiesWhenTheDeviceAppears() async throws {
        let mock = MockMIDITransport(connected: false)
        let session = DiagnosticsSession(transport: mock)
        session.autoIdentify = true
        session.start()
        mock.setConnected(true)
        for _ in 0..<100 {
            if case .identified = session.status { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .identified(_, let reply) = session.status else {
            Issue.record("not identified: \(session.status)")
            return
        }
        #expect(reply.product == .twelveStep2)
        #expect(mock.sentMessages == [TwelveStepMessages.identityRequest])
    }
}
