// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Observation

public struct LogEntry: Identifiable, Equatable, Sendable {
    public enum Direction: String, Sendable {
        case received = "RX"
        case sent = "TX"
        case info = "--"
        case warning = "!!"
        case error = "ER"
    }

    public let id: Int
    public let timestamp: Date
    public let direction: Direction
    public let endpointName: String?
    public let bytes: [UInt8]
    public let kind: TrafficKind
    public let summary: String

    public var hex: String { Hex.string(bytes) }
}

/// In-memory ring buffer of diagnostic events. Main-actor isolated; producers hop to the main
/// actor (the session batches incoming MIDI so the UI thread is not flooded).
@MainActor
@Observable
public final class DiagnosticLog {
    public private(set) var entries: [LogEntry] = []
    public private(set) var droppedCount = 0
    public let capacity: Int
    private var nextID = 0
    /// Called for every new entry, e.g. to mirror the log to the Xcode console.
    @ObservationIgnored public var onAppend: ((LogEntry) -> Void)?

    public init(capacity: Int = 5_000) {
        self.capacity = capacity
    }

    public func append(_ direction: LogEntry.Direction, bytes: [UInt8] = [], endpointName: String? = nil,
                       kind: TrafficKind = .other, summary: String, at timestamp: Date = Date()) {
        appendBatch([(direction, bytes, endpointName, kind, summary, timestamp)])
    }

    public func appendBatch(_ items: [(LogEntry.Direction, [UInt8], String?, TrafficKind, String, Date)]) {
        for item in items {
            let entry = LogEntry(id: nextID, timestamp: item.5, direction: item.0, endpointName: item.2,
                                 bytes: item.1, kind: item.3, summary: item.4)
            entries.append(entry)
            onAppend?(entry)
            nextID += 1
        }
        // Trim in chunks so the O(n) removal is amortised across many appends.
        if entries.count > capacity + capacity / 10 {
            let overflow = entries.count - capacity
            droppedCount += overflow
            entries.removeFirst(overflow)
        }
    }

    public func clear() {
        entries.removeAll()
        droppedCount = 0
    }

    public static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static func format(_ entry: LogEntry) -> String {
        var line = "\(timestampFormatter.string(from: entry.timestamp)) \(entry.direction.rawValue) [\(entry.kind.label)]"
        if let endpoint = entry.endpointName { line += " <\(endpoint)>" }
        line += " \(entry.summary)"
        if !entry.bytes.isEmpty { line += "\n    \(entry.hex)" }
        return line
    }

    public func exportText() -> String {
        var text = entries.map(Self.format).joined(separator: "\n")
        if droppedCount > 0 { text = "(\(droppedCount) older entries dropped)\n" + text }
        return text
    }
}
