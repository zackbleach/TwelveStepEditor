// Command-line probe for macOS: lists MIDI endpoints and runs the same allow-listed read-only
// queries as the iOS diagnostics app, to separate iOS issues from device/protocol issues.
//
//   swift run twelvestep-probe                 # list endpoints, run identity request
//   swift run twelvestep-probe --query cv      # identity | cv | legacy
//   swift run twelvestep-probe --query preset-experimental --i-have-a-backup   # EXPERIMENTAL
//   swift run twelvestep-probe --monitor 10    # also print incoming MIDI for 10 s
//   swift run twelvestep-probe --dest "12Step Control Surface"

import Foundation
import TwelveStepKit

@MainActor
func runProbe() async -> Int32 {
    var arguments = Array(CommandLine.arguments.dropFirst())
    func option(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        defer { arguments.removeSubrange(index...(index + 1)) }
        return arguments[index + 1]
    }

    let commandName = option("--query") ?? "identity"
    let destinationName = option("--dest")
    let monitorSeconds = option("--monitor").flatMap(Double.init) ?? 0
    let commands: [String: SafeCommand] = ["identity": .identityRequest, "cv": .cvCalibrationRequest, "legacy": .legacyFirmwareQuery,
                                           "preset-experimental": .presetRequestProbe]
    guard let command = commands[commandName] else {
        print("Unknown query '\(commandName)'. Use identity, cv, legacy or preset-experimental.")
        return 2
    }
    if command.isExperimental && !arguments.contains("--i-have-a-backup") {
        print("'\(commandName)' is experimental and its effect on the device is unknown.")
        print("Back up your presets in the desktop editor first, then add --i-have-a-backup.")
        return 2
    }

    let session = DiagnosticsSession(transport: CoreMIDITransport())
    session.start()
    if case .transportUnavailable(let message) = session.status {
        print("Core MIDI unavailable: \(message)")
        return 1
    }

    print("Sources:")
    session.endpoints.sources.forEach { print("  \(describe($0))") }
    print("Destinations:")
    session.endpoints.destinations.forEach { print("  \(describe($0))") }

    if let destinationName {
        guard let match = session.endpoints.destinations.first(where: { $0.displayName == destinationName || $0.name == destinationName }) else {
            print("No destination named '\(destinationName)'.")
            return 1
        }
        session.selectDestination(match.id)
    }
    print("\nStatus: \(session.status.title)")
    guard let destination = session.selectedDestination else {
        print("No 12 Step control port found; pass --dest \"<name>\" to choose one.")
        return 1
    }

    print("Sending \(command.title) to \(destination.displayName): \(Hex.string(command.bytes))")
    let result = await session.run(command)
    switch result.outcome {
    case .reply(let bytes, let latency, let decoded):
        print("Reply in \(Int(latency * 1000)) ms: \(Hex.string(bytes))\nDecoded: \(decoded)")
    case .timeout(let seconds):
        print("No reply within \(seconds) s.")
    case .failed(let message):
        print("Failed: \(message)")
    }
    for other in result.otherSysExDuringWait {
        print("Other SysEx during wait: \(Hex.string(other))")
    }

    if monitorSeconds > 0 {
        print("\nMonitoring for \(Int(monitorSeconds)) s…")
        let startCount = session.log.entries.count
        try? await Task.sleep(for: .seconds(monitorSeconds))
        for entry in session.log.entries.dropFirst(startCount) {
            print(DiagnosticLog.format(entry))
        }
    }
    session.stop()
    if case .reply = result.outcome { return 0 }
    return 1
}

func describe(_ endpoint: EndpointInfo) -> String {
    var text = "[\(endpoint.id)] \(endpoint.displayName)"
    if let match = DeviceDiscovery.match(endpoint) { text += "  ← 12 Step \(match.role.rawValue)" }
    if endpoint.isOffline { text += " (offline)" }
    return text
}

let exitCode = await runProbe()
exit(exitCode)
