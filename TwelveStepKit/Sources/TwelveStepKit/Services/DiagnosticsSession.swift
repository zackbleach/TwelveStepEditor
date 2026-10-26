import Foundation
import Observation

public enum ConnectionStatus: Equatable, Sendable {
    case transportUnavailable(String)
    case noDevice
    /// A 12 Step port is present but has not answered an identity request yet.
    case detected(endpointName: String)
    /// The device answered an identity request on this connection.
    case identified(endpointName: String, reply: IdentityReply)

    public var title: String {
        switch self {
        case .transportUnavailable: "MIDI unavailable"
        case .noDevice: "No 12 Step detected"
        case .detected: "12 Step detected"
        case .identified: "12 Step identified"
        }
    }
}

public struct QueryResult: Identifiable, Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case reply(bytes: [UInt8], latency: TimeInterval, decoded: String)
        case timeout(seconds: TimeInterval)
        case failed(String)
    }

    public let id = UUID()
    public let command: SafeCommand
    public let destinationName: String
    public let sentBytes: [UInt8]
    public let startedAt: Date
    public let outcome: Outcome
    /// Other SysEx received while waiting (may hint at a different reply format).
    public let otherSysExDuringWait: [[UInt8]]
}

/// Coordinates transport, discovery, safe queries and the diagnostic log. Contains no UI code.
@MainActor
@Observable
public final class DiagnosticsSession {
    public let transport: MIDITransport
    public let log: DiagnosticLog

    public private(set) var endpoints = EndpointSnapshot()
    public private(set) var status: ConnectionStatus = .noDevice
    public private(set) var lastResult: QueryResult?
    public private(set) var isQuerying = false
    public private(set) var isUploading = false
    public var isMonitorPaused = false

    /// Destination used for queries. Auto-selected to the 12 Step control port unless the user picks one.
    public private(set) var selectedDestinationID: EndpointID?
    private var userPickedDestination = false

    /// User override of the query destination. Pass nil to return to automatic selection.
    public func selectDestination(_ id: EndpointID?) {
        selectedDestinationID = id
        userPickedDestination = id != nil
        if id == nil { refreshEndpoints() }
    }

    public var queryTimeout: TimeInterval = 2.0
    /// Sends the read-only identity request when a 12 Step appears, as the desktop editor does,
    /// so the app knows the hardware generation and firmware without a manual query.
    public var autoIdentify = false

    private var eventTask: Task<Void, Never>?
    private var lastIdentity: IdentityReply?
    private var knownTwelveStepIDs: Set<EndpointID> = []
    private var waiters: [UUID: Waiter] = [:]

    private struct Waiter {
        let matches: ([UInt8]) -> Bool
        var others: [[UInt8]] = []
        let continuation: CheckedContinuation<(ReceivedMessage?, [[UInt8]]), Never>
    }

    public init(transport: MIDITransport, log: DiagnosticLog? = nil) {
        self.transport = transport
        self.log = log ?? DiagnosticLog()
    }

    public var twelveStepMatches: [TwelveStepPortMatch] {
        DeviceDiscovery.matches(in: endpoints.sources + endpoints.destinations)
    }

    public var selectedDestination: EndpointInfo? {
        endpoints.destinations.first { $0.id == selectedDestinationID }
    }

    public func start() {
        guard eventTask == nil else { return }
        log.append(.info, summary: "Starting \(transport.name) transport\(transport.isSimulated ? " (SIMULATED, not real hardware)" : "")")
        do {
            try transport.start()
        } catch {
            status = .transportUnavailable(error.localizedDescription)
            log.append(.error, summary: "Transport failed to start: \(error.localizedDescription)")
            return
        }
        refreshEndpoints()

        let stream = transport.events
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        transport.stop()
    }

    // MARK: Endpoints and status

    public func refreshEndpoints() {
        endpoints = transport.snapshot()

        let matches = twelveStepMatches
        let currentIDs = Set(matches.map(\.endpoint.id))
        for match in matches where !knownTwelveStepIDs.contains(match.endpoint.id) {
            log.append(.info, endpointName: match.endpoint.displayName,
                       summary: "12 Step \(match.endpoint.direction.rawValue) appeared (role: \(match.role.rawValue))")
        }
        if !knownTwelveStepIDs.isEmpty && currentIDs.isEmpty {
            log.append(.warning, summary: "12 Step endpoints disappeared (disconnected or lost power)")
            lastIdentity = nil
        }
        let appeared = knownTwelveStepIDs.isEmpty && !currentIDs.isEmpty
        knownTwelveStepIDs = currentIDs

        if let selected = selectedDestinationID, !endpoints.destinations.contains(where: { $0.id == selected }) {
            log.append(.warning, summary: "Selected destination is no longer available")
            selectedDestinationID = nil
            userPickedDestination = false
        }
        if !userPickedDestination {
            selectedDestinationID = DeviceDiscovery.preferredControlEndpoint(in: endpoints.destinations)?.id
        }
        updateStatus()

        if appeared, autoIdentify, lastIdentity == nil {
            Task { [weak self] in
                // Give the device a moment to finish enumerating, like the desktop's poll.
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.lastIdentity == nil, !self.isQuerying, !self.isUploading,
                      self.selectedDestination != nil else { return }
                await self.run(.identityRequest)
            }
        }
    }

    private func updateStatus() {
        guard let control = DeviceDiscovery.preferredControlEndpoint(in: endpoints.destinations)
                ?? DeviceDiscovery.preferredControlEndpoint(in: endpoints.sources) else {
            status = .noDevice
            return
        }
        if let lastIdentity {
            status = .identified(endpointName: control.displayName, reply: lastIdentity)
        } else {
            status = .detected(endpointName: control.displayName)
        }
    }

    private func sourceName(_ id: EndpointID) -> String {
        endpoints.sources.first { $0.id == id }?.displayName ?? "source \(id)"
    }

    // MARK: Events

    private func handle(_ event: TransportEvent) {
        switch event {
        case .setupChanged:
            refreshEndpoints()
        case .warning(let message, let sourceID):
            log.append(.warning, endpointName: sourceID.map(sourceName), summary: message)
        case .received(let message):
            let classification = MessageClassifier.classify(message.bytes)
            if message.bytes.first == 0xF0 {
                if let reply = IdentityReply(message.bytes) {
                    lastIdentity = reply
                    updateStatus()
                }
                deliverToWaiters(message)
            }
            // Always log configuration traffic; performance traffic respects the pause toggle.
            if !isMonitorPaused || classification.kind == .configuration {
                log.append(.received, bytes: message.bytes, endpointName: sourceName(message.sourceID),
                           kind: classification.kind, summary: classification.summary, at: message.receivedAt)
            }
        }
    }

    private func deliverToWaiters(_ message: ReceivedMessage) {
        for (id, waiter) in waiters {
            if waiter.matches(message.bytes) {
                waiters[id] = nil
                waiter.continuation.resume(returning: (message, waiter.others))
            } else {
                waiters[id]?.others.append(message.bytes)
            }
        }
    }

    // MARK: Uploads (writes)

    /// Sends a setlist or settings upload built by `PresetImageFormatter`, paced like the desktop
    /// editor. **A setlist upload replaces every preset on the device.** The device sends no
    /// acknowledgement; it shows a received-preset count (or "PRST ERR SEND AGAN") on its display.
    public func upload(_ message: [UInt8]) async throws -> UploadPolicy.Kind {
        guard let kind = UploadPolicy.classify(message) else {
            log.append(.error, bytes: message, kind: .configuration, summary: "Upload refused by safety policy")
            throw TransportError.messageRejectedBySafetyPolicy
        }
        guard let destination = selectedDestination else {
            throw TransportError.destinationNotFound(selectedDestinationID ?? 0)
        }
        guard !isUploading, !isQuerying else { throw UploadError.busy }
        isUploading = true
        defer { isUploading = false }

        log.append(.sent, bytes: message, endpointName: destination.displayName, kind: .configuration,
                   summary: "WRITE: \(kind.title), \(message.count) bytes")
        let started = Date()
        do {
            try await transport.sendPaced(message, to: destination.id, chunkBytes: 1000, gap: .milliseconds(1))
        } catch {
            log.append(.error, kind: .configuration, summary: "\(kind.title) failed: \(error.localizedDescription)")
            throw error
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        log.append(.info, kind: .configuration,
                   summary: "\(kind.title) sent in \(elapsed) ms. Check the 12 Step display for the received-preset count.")
        return kind
    }

    public enum UploadError: Error, LocalizedError {
        case busy
        public var errorDescription: String? { "Another query or upload is in progress." }
    }

    // MARK: Safe queries

    /// Sends one allow-listed read-only query and waits for its reply or a timeout.
    @discardableResult
    public func run(_ command: SafeCommand) async -> QueryResult {
        let bytes = command.bytes
        let startedAt = Date()
        guard let destination = selectedDestination else {
            return finish(QueryResult(command: command, destinationName: "—", sentBytes: bytes, startedAt: startedAt,
                                      outcome: .failed("No MIDI destination selected."), otherSysExDuringWait: []))
        }
        guard !isUploading else {
            return finish(QueryResult(command: command, destinationName: destination.displayName, sentBytes: bytes,
                                      startedAt: startedAt, outcome: .failed(UploadError.busy.localizedDescription),
                                      otherSysExDuringWait: []))
        }
        // Defence in depth: the command enum is already restricted, but verify the bytes too.
        guard SendPolicy.isAllowed(bytes) else {
            return finish(QueryResult(command: command, destinationName: destination.displayName, sentBytes: bytes,
                                      startedAt: startedAt, outcome: .failed(TransportError.messageRejectedBySafetyPolicy.localizedDescription),
                                      otherSysExDuringWait: []))
        }

        isQuerying = true
        defer { isQuerying = false }

        let waiterID = UUID()
        let timeout = queryTimeout
        var sendError: Error?

        let (reply, others) = await withCheckedContinuation { continuation in
            // Register before sending so a fast reply cannot be missed.
            waiters[waiterID] = Waiter(matches: command.isReply, continuation: continuation)
            do {
                try transport.send(bytes, to: destination.id)
                log.append(.sent, bytes: bytes, endpointName: destination.displayName,
                           kind: .configuration, summary: "\(command.title) (read-only)")
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    self?.expireWaiter(waiterID)
                }
            } catch {
                sendError = error
                expireWaiter(waiterID)
            }
        }

        let outcome: QueryResult.Outcome
        if let sendError {
            outcome = .failed(sendError.localizedDescription)
        } else if let reply {
            outcome = .reply(bytes: reply.bytes, latency: reply.receivedAt.timeIntervalSince(startedAt),
                             decoded: Self.decode(reply.bytes))
        } else {
            outcome = .timeout(seconds: timeout)
        }
        return finish(QueryResult(command: command, destinationName: destination.displayName, sentBytes: bytes,
                                  startedAt: startedAt, outcome: outcome, otherSysExDuringWait: others))
    }

    private func expireWaiter(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: (nil, waiter.others))
    }

    private func finish(_ result: QueryResult) -> QueryResult {
        lastResult = result
        switch result.outcome {
        case .reply(_, let latency, let decoded):
            log.append(.info, kind: .configuration,
                       summary: "\(result.command.title): reply in \(Int(latency * 1000)) ms · \(decoded)")
        case .timeout(let seconds):
            log.append(.warning, kind: .configuration,
                       summary: "\(result.command.title): no reply within \(seconds) s")
        case .failed(let message):
            log.append(.error, kind: .configuration, summary: "\(result.command.title) failed: \(message)")
        }
        return result
    }

    public static func decode(_ bytes: [UInt8]) -> String {
        if let identity = IdentityReply(bytes) {
            return identity.summary
        }
        if let legacy = LegacyFirmwareReply(bytes) {
            return legacy.summary
        }
        if KMIFraming.isKMISysEx(bytes) {
            do {
                let packet = try KMIFraming.decode(bytes)
                if packet.category == KMICategory.calibration, packet.type == KMICalibrationType.cvCalPayload,
                   let payload = packet.blocks.first.flatMap(CVCalibrationPayload.init) {
                    return "CRC OK · " + payload.summary
                }
                return "CRC OK · " + MessageClassifier.describeKMIPacket(bytes)
            } catch {
                return "KMI packet failed to decode: \(error)"
            }
        }
        return MessageClassifier.classify(bytes).summary
    }

    // MARK: Report

    /// Plain-text report for sharing with the developer.
    public func diagnosticReport(appVersion: String, osVersion: String, deviceModel: String) -> String {
        var lines: [String] = []
        lines.append("12 Step Diagnostics report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("App: \(appVersion) · \(osVersion) · \(deviceModel)")
        lines.append("Transport: \(transport.name)\(transport.isSimulated ? " — SIMULATED DATA, NOT HARDWARE" : "")")
        lines.append("Status: \(status.title)")
        if case .identified(_, let reply) = status {
            lines.append("Identity: \(reply.summary)")
            lines.append("Identity raw: \(Hex.string(reply.raw))")
        }
        lines.append("")
        lines.append("== Sources ==")
        for endpoint in endpoints.sources { lines += Self.describe(endpoint) }
        lines.append("== Destinations ==")
        for endpoint in endpoints.destinations { lines += Self.describe(endpoint) }
        if let lastResult {
            lines.append("")
            lines.append("== Last query ==")
            lines.append("\(lastResult.command.title) -> \(lastResult.destinationName)")
            lines.append("TX: \(Hex.string(lastResult.sentBytes))")
            switch lastResult.outcome {
            case .reply(let bytes, let latency, let decoded):
                lines.append("RX (\(Int(latency * 1000)) ms): \(Hex.string(bytes))")
                lines.append("Decoded: \(decoded)")
            case .timeout(let seconds):
                lines.append("Timeout after \(seconds) s")
            case .failed(let message):
                lines.append("Failed: \(message)")
            }
            for other in lastResult.otherSysExDuringWait {
                lines.append("Other SysEx during wait: \(Hex.string(other))")
            }
        }
        lines.append("")
        lines.append("== Device properties (first 12 Step endpoint) ==")
        if let match = twelveStepMatches.first {
            lines.append(match.endpoint.propertyDump)
        } else {
            lines.append("(none)")
        }
        lines.append("")
        lines.append("== Log ==")
        lines.append(log.exportText())
        return lines.joined(separator: "\n")
    }

    static func describe(_ endpoint: EndpointInfo) -> [String] {
        let match = DeviceDiscovery.match(endpoint)
        var line = "- [\(endpoint.id)] \"\(endpoint.displayName)\" name=\"\(endpoint.name)\""
        if let device = endpoint.deviceName { line += " device=\"\(device)\"" }
        if let entity = endpoint.entityName { line += " entity=\"\(entity)\"" }
        if let manufacturer = endpoint.manufacturer { line += " mfr=\"\(manufacturer)\"" }
        if let model = endpoint.model { line += " model=\"\(model)\"" }
        if let owner = endpoint.driverOwner { line += " driver=\"\(owner)\"" }
        if endpoint.isOffline { line += " OFFLINE" }
        if let match { line += " → 12 Step \(match.role.rawValue)" }
        return [line]
    }
}
