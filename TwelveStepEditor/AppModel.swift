// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Observation
import TwelveStepKit
import UIKit

/// Owns the active diagnostics session and lets the user swap between real Core MIDI and the simulator.
@MainActor
@Observable
final class AppModel {
    private(set) var session: DiagnosticsSession
    let presets = PresetFolderStore()
    /// Debug-only deep link from launch arguments (for screenshots); empty in release builds.
    var launchRoute = LaunchRoute(arguments: ProcessInfo.processInfo.arguments)

    var useSimulator: Bool {
        didSet {
            guard useSimulator != oldValue else { return }
            session.stop()
            session = Self.makeSession(simulated: useSimulator)
            session.start()
        }
    }

    init() {
        let simulated = ProcessInfo.processInfo.arguments.contains("-simulate")
        useSimulator = simulated
        session = Self.makeSession(simulated: simulated)
        session.start()
        presets.reload()
    }

    private static func makeSession(simulated: Bool) -> DiagnosticsSession {
        let transport: MIDITransport = simulated ? MockMIDITransport() : CoreMIDITransport()
        let session = DiagnosticsSession(transport: transport)
        session.autoIdentify = true
        // Mirror every log line to stdout: it shows in Xcode's console (also over wireless debugging)
        // and in `xcrun devicectl device process launch --console`. print() avoids os_log truncation
        // of long SysEx hex.
        session.log.onAppend = { entry in
            print("[12Step] " + DiagnosticLog.format(entry))
        }
        return session
    }

    // MARK: Sending to the device

    var canSend: Bool { session.selectedDestination != nil && !session.isUploading }

    /// Sends the saved setlist. Returns a message for the user.
    func sendSetlist() async -> String {
        guard let contents = presets.contents,
              let message = PresetImageFormatter.setlistMessage(for: contents.resolvedSetlist()) else {
            return "The setlist is empty, so there's nothing to send."
        }
        do {
            _ = try await session.upload(message)
            let count = contents.resolvedSetlist().imageCount
            return "Sent \(count) preset\(count == 1 ? "" : "s") to the 12 Step. Its display should briefly show how many it received."
        } catch {
            return "Not sent: \(error.localizedDescription)"
        }
    }

    /// Sends `settings` as soon as the device is free (an upload in progress is waited out, as
    /// the desktop's `slotSendSettings` retries). Used for live updates; throws on failure.
    func sendSettingsWhenFree(_ settings: GlobalSettings) async throws {
        while session.isUploading || session.isQuerying {
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await session.upload(PresetImageFormatter.settingsMessage(for: settings))
    }


    /// True when the connected device identified itself as a 12 Step2 (CV outputs, backlight).
    var isTwelveStep2: Bool {
        if case .identified(_, let reply) = session.status { reply.product == .twelveStep2 } else { false }
    }

    /// Prints the full diagnostic report to the console, framed so it can be found and copied.
    func printReport() {
        print("[12Step] ===== BEGIN DIAGNOSTIC REPORT =====\n\(makeReport())\n[12Step] ===== END DIAGNOSTIC REPORT =====")
    }

    var appVersion: String {
        "12 Step Editor (iOS) \(shortVersion)"
    }

    /// e.g. "0.1.1 (2)": marketing version and build number, shown on screen and in reports.
    var shortVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    func makeReport() -> String {
        let device = UIDevice.current
        return session.diagnosticReport(appVersion: appVersion,
                                        osVersion: "\(device.systemName) \(device.systemVersion)",
                                        deviceModel: Self.hardwareModel)
    }

    /// Writes the report to a temporary file for sharing.
    func writeReportFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("12step-diagnostics-\(formatter.string(from: Date())).txt")
        try makeReport().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// e.g. "iPhone16,1" — identifies the exact iPhone model (and so its USB-C power budget).
    static var hardwareModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// `-tab presets|setlist|settings|device`, `-preset Preset_000`, `-key 3`, `-fill` (DEBUG builds only).
struct LaunchRoute {
    var tab: String?
    var presetKey: String?
    var key: Int?
    var fill = false
    /// `-fillLayout major -fillVoicing triads -fillOutside secondaryDominant -fillKey 5` (enum case names; key 0–11).
    var fillOptions: [String: String] = [:]

    init(arguments: [String]) {
        #if DEBUG
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        tab = value("-tab")
        presetKey = value("-preset")
        key = value("-key").flatMap(Int.init)
        fill = arguments.contains("-fill")
        for name in ["-fillLayout", "-fillVoicing", "-fillOutside", "-fillKey"] {
            if let option = value(name) { fillOptions[name] = option }
        }
        #endif
    }
}
