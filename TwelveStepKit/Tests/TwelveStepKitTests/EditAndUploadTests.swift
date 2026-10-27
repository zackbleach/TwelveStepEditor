// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Testing
@testable import TwelveStepKit

struct UploadPolicyTests {
    @Test func acceptsOnlyFormatterOutput() throws {
        let factory = try PresetFolderContents.factory()
        let setlist = try #require(PresetImageFormatter.setlistMessage(for: factory.resolvedSetlist()))
        #expect(UploadPolicy.classify(setlist) == .setlist(presetCount: 21))
        #expect(UploadPolicy.classify(PresetImageFormatter.settingsMessage(for: factory.settings)) == .settings)
    }

    @Test func refusesEverythingElse() {
        let refused: [[UInt8]] = [
            TwelveStepMessages.enterBootloader, TwelveStepMessages.tetherOn, TwelveStepMessages.tetherOff,
            TwelveStepMessages.standaloneOn, TwelveStepMessages.identityRequest,
            // REQUEST_PRESET (category 2, type 0), the retired probe.
            KMIFraming.encode(KMIPacket(pid: 22, category: KMICategory.preset, type: KMIPresetType.requestPreset)),
            KMIFraming.encode(KMIPacket(pid: 22, category: 1, type: KMICalibrationType.resetCVCalToFactory)),
            // Right shape but wrong PID / padding / count.
            KMIFraming.encode(KMIPacket(pid: 22, packetType: 9, blocks: [[0, 0, 1, 0, 0, 1], Array(repeating: 0, count: 191)]), headerPadding: 10),
            KMIFraming.encode(KMIPacket(pid: 20, packetType: 9, blocks: [[0, 0, 1, 0, 0, 2], Array(repeating: 0, count: 191)]), headerPadding: 10),
            KMIFraming.encode(KMIPacket(pid: 20, packetType: 9, blocks: [[0, 0, 1, 0, 0, 1], Array(repeating: 0, count: 190)]), headerPadding: 10),
        ]
        for message in refused {
            #expect(UploadPolicy.classify(message) == nil)
        }
    }
}

@MainActor
struct SessionUploadTests {
    @Test func uploadsAndLogsAWrite() async throws {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()
        let message = try #require(PresetImageFormatter.setlistMessage(for: try PresetFolderContents.factory().resolvedSetlist()))
        let kind = try await session.upload(message)
        #expect(kind == .setlist(presetCount: 21))
        #expect(mock.sentMessages.last == message)
        #expect(session.log.entries.contains { $0.summary.hasPrefix("WRITE: Setlist upload (21 presets)") })
        #expect(!session.isUploading)
    }

    @Test func refusesNonUploadBytes() async {
        let mock = MockMIDITransport()
        let session = DiagnosticsSession(transport: mock)
        session.start()
        await #expect(throws: TransportError.messageRejectedBySafetyPolicy) {
            try await session.upload(TwelveStepMessages.enterBootloader)
        }
        #expect(!mock.sentMessages.contains(TwelveStepMessages.enterBootloader))
    }
}

@MainActor
struct PresetSaveTests {
    let defaults = UserDefaults(suiteName: "PresetSaveTests-\(UUID().uuidString)")!

    func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let factory = try #require(Bundle.module.url(forResource: "FactoryPresets", withExtension: nil))
        for file in PresetFolderContents.requiredFiles {
            try FileManager.default.copyItem(at: factory.appendingPathComponent(file), to: folder.appendingPathComponent(file))
        }
        return folder
    }

    @Test func savesOnlyTheEditedValue() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let libraryURL = folder.appendingPathComponent("12Step.json")
        let before = try String(contentsOf: libraryURL, encoding: .utf8)

        let store = PresetFolderStore(defaults: defaults)
        store.useFolder(folder)
        var preset = try #require(store.contents?.library[key: "Preset_001"])
        preset.setProgramChange(42, voice: .a)
        try store.save(preset)

        let after = try String(contentsOf: libraryURL, encoding: .utf8)
        let changed = zip(before.split(separator: "\n"), after.split(separator: "\n")).filter { $0 != $1 }
        #expect(changed.count == 1)
        #expect(changed.first?.1.contains("\"voice_a_programchange\": 42") == true)

        store.reload()
        #expect(store.contents?.library[key: "Preset_001"]?.voice(.a).programChange == 42)
    }

    @Test func refusesToOverwriteExternalChanges() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PresetFolderStore(defaults: defaults)
        store.useFolder(folder)
        var preset = try #require(store.contents?.library[key: "Preset_000"])

        // Simulate the desktop editor saving in the meantime.
        let libraryURL = folder.appendingPathComponent("12Step.json")
        var external = try PresetLibrary(data: Data(contentsOf: libraryURL))
        external[key: "Preset_005"]?.setProgramChange(7, voice: .b)
        try external.jsonData().write(to: libraryURL)

        preset.setProgramChange(10, voice: .a)
        #expect(throws: PresetFolderError.changedOnDisk(file: "12Step.json")) { try store.save(preset) }
        #expect(store.contents?.library[key: "Preset_005"]?.voice(.b).programChange == 7)
        #expect(try PresetLibrary(data: Data(contentsOf: libraryURL))[key: "Preset_000"]?.voice(.a).programChange == -1)
    }
}
