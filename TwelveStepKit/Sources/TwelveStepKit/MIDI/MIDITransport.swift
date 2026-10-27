// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

public typealias EndpointID = Int32

public enum EndpointDirection: String, Sendable {
    case source      // device -> app
    case destination // app -> device
}

/// Snapshot of a Core MIDI endpoint and the device/entity it belongs to.
public struct EndpointInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: EndpointID
    public var direction: EndpointDirection
    public var name: String
    public var displayName: String
    public var entityName: String?
    public var deviceName: String?
    public var manufacturer: String?
    public var model: String?
    public var driverOwner: String?
    public var isOffline: Bool
    /// All Core MIDI properties of the owning device (or the endpoint if it has none), as text.
    public var propertyDump: String

    public init(id: EndpointID, direction: EndpointDirection, name: String, displayName: String,
                entityName: String? = nil, deviceName: String? = nil, manufacturer: String? = nil,
                model: String? = nil, driverOwner: String? = nil, isOffline: Bool = false,
                propertyDump: String = "") {
        self.id = id
        self.direction = direction
        self.name = name
        self.displayName = displayName
        self.entityName = entityName
        self.deviceName = deviceName
        self.manufacturer = manufacturer
        self.model = model
        self.driverOwner = driverOwner
        self.isOffline = isOffline
        self.propertyDump = propertyDump
    }
}

public struct EndpointSnapshot: Equatable, Sendable {
    public var sources: [EndpointInfo]
    public var destinations: [EndpointInfo]

    public init(sources: [EndpointInfo] = [], destinations: [EndpointInfo] = []) {
        self.sources = sources
        self.destinations = destinations
    }
}

public struct ReceivedMessage: Equatable, Sendable {
    public var bytes: [UInt8]
    public var sourceID: EndpointID
    public var receivedAt: Date

    public init(bytes: [UInt8], sourceID: EndpointID, receivedAt: Date = Date()) {
        self.bytes = bytes
        self.sourceID = sourceID
        self.receivedAt = receivedAt
    }
}

public enum TransportEvent: Sendable {
    /// Endpoints were added, removed or changed. Call `snapshot()` to refresh.
    case setupChanged
    case received(ReceivedMessage)
    /// Something the transport could not turn into a MIDI 1.0 message.
    case warning(String, sourceID: EndpointID?)
}

public enum TransportError: Error, LocalizedError, Equatable {
    case notStarted
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
    case destinationNotFound(EndpointID)
    case sendFailed(OSStatus)
    case messageRejectedBySafetyPolicy

    public var errorDescription: String? {
        switch self {
        case .notStarted: "MIDI transport has not been started."
        case .clientCreationFailed(let status): "Could not create Core MIDI client (OSStatus \(status))."
        case .portCreationFailed(let status): "Could not create Core MIDI port (OSStatus \(status))."
        case .destinationNotFound(let id): "MIDI destination \(id) is no longer available."
        case .sendFailed(let status): "Core MIDI send failed (OSStatus \(status))."
        case .messageRejectedBySafetyPolicy: "Message blocked: only allow-listed read-only queries can be sent."
        }
    }
}

/// Abstraction over MIDI I/O so the protocol and UI layers can run against hardware or a mock.
public protocol MIDITransport: AnyObject, Sendable {
    /// Human-readable description shown in the UI (e.g. "Core MIDI" or "Simulated device").
    var name: String { get }
    var isSimulated: Bool { get }
    /// Stream of transport events. Each transport exposes a single stream for its lifetime.
    var events: AsyncStream<TransportEvent> { get }

    func start() throws
    func stop()
    func snapshot() -> EndpointSnapshot
    /// Sends a complete MIDI 1.0 message (SysEx must include F0 … F7).
    func send(_ bytes: [UInt8], to destination: EndpointID) throws
    /// Sends a large SysEx message in chunks of about `chunkBytes`, pausing `gap` between chunks,
    /// like the desktop editor's 1000-byte / 1 ms upload pacing (`KMI_mdm.cpp:299-306`).
    func sendPaced(_ bytes: [UInt8], to destination: EndpointID, chunkBytes: Int, gap: Duration) async throws
}

extension MIDITransport {
    public func sendPaced(_ bytes: [UInt8], to destination: EndpointID, chunkBytes: Int, gap: Duration) async throws {
        try send(bytes, to: destination)
    }
}
