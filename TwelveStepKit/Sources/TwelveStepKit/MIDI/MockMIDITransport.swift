import Foundation
import os

/// Simulated transport for previews, tests and UI work without hardware.
///
/// The simulated replies are invented placeholders shaped like the desktop editor's parsing
/// expectations. They are NOT captured from a real 12 Step and must never be treated as evidence
/// of real device behaviour.
public final class MockMIDITransport: MIDITransport, @unchecked Sendable {
    public struct Behavior: Sendable {
        public var answersIdentity = true
        public var answersCVCalibration = true
        public var replyDelay: Duration = .milliseconds(40)
        public var firmware: [UInt8] = [1, 0, 9]
        public var productID: TwelveStepPID = .twelveStep2

        public init() {}
    }

    public let name = "Simulated 12 Step"
    public let isSimulated = true
    public let events: AsyncStream<TransportEvent>

    public static let controlSourceID: EndpointID = 1001
    public static let expanderSourceID: EndpointID = 1002
    public static let controlDestinationID: EndpointID = 2001
    public static let expanderDestinationID: EndpointID = 2002

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let state: OSAllocatedUnfairLock<(connected: Bool, behavior: Behavior, sent: [[UInt8]])>

    public init(behavior: Behavior = Behavior(), connected: Bool = true) {
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        state = OSAllocatedUnfairLock(initialState: (connected, behavior, []))
    }

    public var sentMessages: [[UInt8]] { state.withLock { $0.sent } }

    public func start() throws {}
    public func stop() {}

    public func setConnected(_ connected: Bool) {
        state.withLock { $0.connected = connected }
        continuation.yield(.setupChanged)
    }

    public func setBehavior(_ behavior: Behavior) {
        state.withLock { $0.behavior = behavior }
    }

    /// Injects an incoming message as if the device had sent it (e.g. simulated key presses).
    public func simulateIncoming(_ bytes: [UInt8], from source: EndpointID = controlSourceID) {
        continuation.yield(.received(ReceivedMessage(bytes: bytes, sourceID: source)))
    }

    public func snapshot() -> EndpointSnapshot {
        guard state.withLock({ $0.connected }) else { return EndpointSnapshot() }
        let props = "SIMULATED DEVICE: no real Core MIDI properties"
        return EndpointSnapshot(
            sources: [
                EndpointInfo(id: Self.controlSourceID, direction: .source, name: "Control Surface",
                             displayName: "12Step Control Surface", entityName: "Control Surface",
                             deviceName: "12Step", manufacturer: "KMI (simulated)", propertyDump: props),
                EndpointInfo(id: Self.expanderSourceID, direction: .source, name: "Expander",
                             displayName: "12Step Expander", entityName: "Expander",
                             deviceName: "12Step", manufacturer: "KMI (simulated)", propertyDump: props),
            ],
            destinations: [
                EndpointInfo(id: Self.controlDestinationID, direction: .destination, name: "Control Surface",
                             displayName: "12Step Control Surface", entityName: "Control Surface",
                             deviceName: "12Step", manufacturer: "KMI (simulated)", propertyDump: props),
                EndpointInfo(id: Self.expanderDestinationID, direction: .destination, name: "Expander",
                             displayName: "12Step Expander", entityName: "Expander",
                             deviceName: "12Step", manufacturer: "KMI (simulated)", propertyDump: props),
            ]
        )
    }

    public func send(_ bytes: [UInt8], to destination: EndpointID) throws {
        let (connected, behavior) = state.withLock { state -> (Bool, Behavior) in
            state.sent.append(bytes)
            return (state.connected, state.behavior)
        }
        guard connected, destination == Self.controlDestinationID || destination == Self.expanderDestinationID else {
            throw TransportError.destinationNotFound(destination)
        }
        guard destination == Self.controlDestinationID, let reply = reply(to: bytes, behavior: behavior) else { return }

        let continuation = continuation
        Task {
            try? await Task.sleep(for: behavior.replyDelay)
            continuation.yield(.received(ReceivedMessage(bytes: reply, sourceID: Self.controlSourceID)))
        }
    }

    private func reply(to bytes: [UInt8], behavior: Behavior) -> [UInt8]? {
        if bytes == TwelveStepMessages.identityRequest, behavior.answersIdentity {
            // Placeholder layout matching the offsets KMI_mdm.cpp reads (PID @8, bootloader flag @9,
            // bootloader version @12-14, firmware version @15-17).
            return [0xF0, 0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x5F, behavior.productID.rawValue, 0x00,
                    0x00, 0x00, 0x01, 0x00, 0x00] + behavior.firmware + [0xF7]
        }
        if bytes == TwelveStepMessages.cvCalibrationRequest, behavior.answersCVCalibration {
            var payload = [UInt8](repeating: 0, count: CVCalibrationPayload.expectedLength)
            payload[0] = 1 // version
            payload[1] = 1 // octaves mode
            // Real 12 Step2 replies use the single-block layout (observed on hardware 2026-10-24).
            return KMIFraming.encodeSingleBlock(pid: behavior.productID.rawValue,
                                                packetType: UInt16(KMICategory.calibration) << 8 | UInt16(KMICalibrationType.cvCalPayload),
                                                payload: payload)
        }
        return nil
    }
}
