import CoreMIDI
import Foundation
import os

/// Core MIDI implementation of `MIDITransport`.
///
/// - Receives on a MIDI 1.0 protocol input port (UMP event lists) connected to every source.
/// - Sends via `MIDISendEventList` using UMP SysEx7 / channel-voice packets.
/// - Core MIDI callbacks arrive on Core MIDI's own thread; they only parse and yield events,
///   never touching UI state.
public final class CoreMIDITransport: MIDITransport, @unchecked Sendable {
    public let name = "Core MIDI"
    public let isSimulated = false
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private static let logger = Logger(subsystem: "TwelveStepKit", category: "CoreMIDI")
    private var logger: Logger { Self.logger }

    private struct State {
        var client = MIDIClientRef()
        var inputPort = MIDIPortRef()
        var outputPort = MIDIPortRef()
        var started = false
        var connectedSources: [EndpointID: MIDIEndpointRef] = [:]
        var parsers: [EndpointID: UMPParser] = [:]
    }

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self, bufferingPolicy: .bufferingNewest(10_000))
    }

    deinit {
        stop()
        continuation.finish()
    }

    public func start() throws {
        if lock.withLock({ $0.started }) { return }

        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("TwelveStepDiagnostics" as CFString, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard clientStatus == noErr else { throw TransportError.clientCreationFailed(clientStatus) }

        var inputPort = MIDIPortRef()
        let inputStatus = MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inputPort) { [weak self] eventList, refCon in
            self?.handle(eventList: eventList, refCon: refCon)
        }
        guard inputStatus == noErr else { throw TransportError.portCreationFailed(inputStatus) }

        var outputPort = MIDIPortRef()
        let outputStatus = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard outputStatus == noErr else { throw TransportError.portCreationFailed(outputStatus) }

        let (newClient, newInput, newOutput) = (client, inputPort, outputPort)
        lock.withLock {
            $0.client = newClient
            $0.inputPort = newInput
            $0.outputPort = newOutput
            $0.started = true
        }
        connectAllSources()
    }

    public func stop() {
        let state = lock.withLock { state -> State in
            let copy = state
            state = State()
            return copy
        }
        guard state.started else { return }
        for source in state.connectedSources.values {
            MIDIPortDisconnectSource(state.inputPort, source)
        }
        MIDIPortDispose(state.inputPort)
        MIDIPortDispose(state.outputPort)
        MIDIClientDispose(state.client)
    }

    // MARK: Enumeration

    public func snapshot() -> EndpointSnapshot {
        let sources = (0..<MIDIGetNumberOfSources()).compactMap { index -> EndpointInfo? in
            let endpoint = MIDIGetSource(index)
            return endpoint == 0 ? nil : Self.describe(endpoint, direction: .source)
        }
        let destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index -> EndpointInfo? in
            let endpoint = MIDIGetDestination(index)
            return endpoint == 0 ? nil : Self.describe(endpoint, direction: .destination)
        }
        return EndpointSnapshot(sources: sources, destinations: destinations)
    }

    static func describe(_ endpoint: MIDIEndpointRef, direction: EndpointDirection) -> EndpointInfo {
        var entity = MIDIEntityRef()
        var device = MIDIDeviceRef()
        if MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 {
            MIDIEntityGetDevice(entity, &device)
        }
        let dumpTarget = device != 0 ? device : endpoint
        return EndpointInfo(
            id: integer(endpoint, kMIDIPropertyUniqueID) ?? 0,
            direction: direction,
            name: string(endpoint, kMIDIPropertyName) ?? "(unnamed)",
            displayName: string(endpoint, kMIDIPropertyDisplayName) ?? string(endpoint, kMIDIPropertyName) ?? "(unnamed)",
            entityName: entity != 0 ? string(entity, kMIDIPropertyName) : nil,
            deviceName: device != 0 ? string(device, kMIDIPropertyName) : nil,
            manufacturer: string(endpoint, kMIDIPropertyManufacturer) ?? (device != 0 ? string(device, kMIDIPropertyManufacturer) : nil),
            model: string(endpoint, kMIDIPropertyModel) ?? (device != 0 ? string(device, kMIDIPropertyModel) : nil),
            driverOwner: string(endpoint, kMIDIPropertyDriverOwner),
            isOffline: (integer(endpoint, kMIDIPropertyOffline) ?? 0) != 0,
            propertyDump: propertyDump(dumpTarget)
        )
    }

    static func string(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func integer(_ object: MIDIObjectRef, _ property: CFString) -> Int32? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else { return nil }
        return value
    }

    static func propertyDump(_ object: MIDIObjectRef) -> String {
        var properties: Unmanaged<CFPropertyList>?
        guard MIDIObjectGetProperties(object, &properties, true) == noErr, let properties else { return "" }
        let plist = properties.takeRetainedValue()
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return String(describing: plist)
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Source connections

    private func connectAllSources() {
        let (started, inputPort) = lock.withLock { ($0.started, $0.inputPort) }
        guard started else { return }

        var found: [EndpointID: MIDIEndpointRef] = [:]
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, let id = Self.integer(endpoint, kMIDIPropertyUniqueID) else { continue }
            found[id] = endpoint
        }
        let current = found

        let (toConnect, toDrop) = lock.withLock { state -> ([EndpointID: MIDIEndpointRef], [EndpointID]) in
            let newOnes = current.filter { state.connectedSources[$0.key] == nil }
            let gone = state.connectedSources.keys.filter { current[$0] == nil }
            return (newOnes, Array(gone))
        }

        for (id, endpoint) in toConnect {
            // The unique ID is passed as the connection refCon so received data can be attributed.
            let refCon = Self.refCon(for: id)
            let status = MIDIPortConnectSource(inputPort, endpoint, refCon)
            if status == noErr {
                lock.withLock {
                    $0.connectedSources[id] = endpoint
                    $0.parsers[id] = UMPParser()
                }
            } else {
                continuation.yield(.warning("Could not connect to source \(id) (OSStatus \(status))", sourceID: id))
            }
        }
        lock.withLock { state in
            for id in toDrop {
                state.connectedSources[id] = nil
                state.parsers[id] = nil
            }
        }
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
            connectAllSources()
            continuation.yield(.setupChanged)
        default:
            break
        }
    }

    // MARK: Receive

    /// Encodes a unique ID in a pointer-sized refCon. Bit 40 is set so the pointer is never nil.
    static func refCon(for id: EndpointID) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: Int(UInt32(bitPattern: id)) | (1 << 40))
    }

    static func sourceID(from refCon: UnsafeMutableRawPointer?) -> EndpointID {
        guard let refCon else { return 0 }
        return EndpointID(bitPattern: UInt32(truncatingIfNeeded: Int(bitPattern: refCon)))
    }

    private func handle(eventList: UnsafePointer<MIDIEventList>, refCon: UnsafeMutableRawPointer?) {
        let sourceID = Self.sourceID(from: refCon)
        let receivedAt = Date()

        var words: [UInt32] = []
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
            let start = UnsafeRawPointer(packet).advanced(by: wordsOffset).assumingMemoryBound(to: UInt32.self)
            words.append(contentsOf: UnsafeBufferPointer(start: start, count: count))
        }

        let collected = words
        let parsed = lock.withLock { state -> [UMPParser.Event] in
            var parser = state.parsers[sourceID] ?? UMPParser()
            let events = parser.parse(collected)
            state.parsers[sourceID] = parser
            return events
        }

        for event in parsed {
            switch event {
            case .message(let bytes):
                continuation.yield(.received(ReceivedMessage(bytes: bytes, sourceID: sourceID, receivedAt: receivedAt)))
            case .unsupported(let words):
                let hex = words.map { String(format: "%08X", $0) }.joined(separator: " ")
                continuation.yield(.warning("Unsupported UMP: \(hex)", sourceID: sourceID))
            case .malformedSysEx(let partial):
                continuation.yield(.warning("Malformed SysEx stream (\(partial.count) bytes): \(Hex.string(partial.prefix(32)))…", sourceID: sourceID))
            }
        }
    }

    // MARK: Send

    public func send(_ bytes: [UInt8], to destination: EndpointID) throws {
        let (outputPort, object, words) = try prepare(bytes, to: destination)
        // Send in batches of SysEx7 packets so each event list stays small.
        for batch in Self.batches(words, wordsPerBatch: 64) {
            try Self.send(batch, port: outputPort, destination: object)
        }
    }

    public func sendPaced(_ bytes: [UInt8], to destination: EndpointID, chunkBytes: Int, gap: Duration) async throws {
        let (outputPort, object, words) = try prepare(bytes, to: destination)
        // Each SysEx7 UMP packet is 2 words carrying up to 6 bytes.
        let wordsPerBatch = max(2, (chunkBytes / 6) * 2)
        for (index, batch) in Self.batches(words, wordsPerBatch: wordsPerBatch).enumerated() {
            if index > 0 { try await Task.sleep(for: gap) }
            try Self.send(batch, port: outputPort, destination: object)
        }
    }

    private static func batches(_ words: [UInt32], wordsPerBatch: Int) -> [[UInt32]] {
        stride(from: 0, to: words.count, by: wordsPerBatch).map {
            Array(words[$0..<min($0 + wordsPerBatch, words.count)])
        }
    }

    private static func send(_ batch: [UInt32], port: MIDIPortRef, destination: MIDIEndpointRef) throws {
        let status = sendEventList(batch, port: port, destination: destination)
        guard status == noErr else {
            logger.error("MIDISendEventList failed: \(status)")
            throw TransportError.sendFailed(status)
        }
    }

    private func prepare(_ bytes: [UInt8], to destination: EndpointID) throws -> (MIDIPortRef, MIDIEndpointRef, [UInt32]) {
        let (started, outputPort) = lock.withLock { ($0.started, $0.outputPort) }
        guard started else { throw TransportError.notStarted }

        var object = MIDIObjectRef()
        var objectType = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(destination, &object, &objectType) == noErr,
              objectType == .destination || objectType == .externalDestination else {
            throw TransportError.destinationNotFound(destination)
        }

        let words: [UInt32]
        if bytes.first == 0xF0 {
            words = UMP.sysExWords(bytes)
        } else if let word = UMP.channelVoiceWord(bytes) {
            words = [word]
        } else {
            throw TransportError.sendFailed(-1)
        }
        return (outputPort, object, words)
    }

    private static func sendEventList(_ words: [UInt32], port: MIDIPortRef, destination: MIDIEndpointRef) -> OSStatus {
        // Generous buffer: list header plus one packet header per UMP message.
        let bufferSize = MemoryLayout<MIDIEventList>.size + words.count * (MemoryLayout<UInt32>.size + MemoryLayout<MIDIEventPacket>.size)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)

        var packet: UnsafeMutablePointer<MIDIEventPacket>? = MIDIEventListInit(list, ._1_0)
        var index = 0
        while index < words.count {
            let count = UMP.wordCount(forFirstWord: words[index])
            let message = Array(words[index..<min(index + count, words.count)])
            guard let current = packet else { return OSStatus(kMIDIMessageSendErr) }
            // MIDIEventListAdd returns NULL when the list is full; the buffer is sized so that cannot happen.
            packet = message.withUnsafeBufferPointer { MIDIEventListAdd(list, bufferSize, current, 0, $0.count, $0.baseAddress!) }
            index += count
        }
        return MIDISendEventList(port, destination, list)
    }
}
