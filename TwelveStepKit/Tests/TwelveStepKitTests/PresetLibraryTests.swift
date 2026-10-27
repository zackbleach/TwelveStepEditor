// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Testing
@testable import TwelveStepKit

struct PresetLibraryTests {
    @Test func loadsBundledFactoryPresets() throws {
        let contents = try PresetFolderContents.factory()
        #expect(contents.library.presets.count == 21)
        #expect(contents.setlist.slots.count == 64)
        #expect(contents.setlist.usedSlotCount == 21)
        #expect(contents.setlist.slots[0] == "Chromatic")
        #expect(contents.setlist.slots[21] == nil)
        #expect(contents.settings["globalSensitivity"] == .double(3.86))
        #expect(contents.settings["backlightBrightness"] == .int(15))
    }

    @Test func readsPresetFields() throws {
        let chromatic = try #require(try PresetFolderContents.factory().library.presets.first { $0.key == "Preset_000" })
        #expect(chromatic.name == "Chromatic")
        #expect(chromatic.displayName == "CHRO")
        #expect(chromatic.voice(.a) == .init(channel: 1, programChange: -1, bankLSB: -1, bankMSB: -1, transpose: 0))
    }

    @Test func factorySetlistResolvesCompletely() throws {
        let resolved = try PresetFolderContents.factory().resolvedSetlist()
        #expect(resolved.imageCount == 21)
        #expect(resolved.missingNames.isEmpty)
        #expect(resolved.duplicateNames.isEmpty)
        #expect(resolved.slotsDroppedByGaps.isEmpty)
        #expect(resolved.uploadOrder.map { $0?.name } == (0..<21).map { resolved.matched[$0]?.name })
    }

    @Test func reproducesEditorGapAndDuplicateQuirks() {
        let library = PresetLibrary(presets: [
            Preset(key: "Preset_000", values: ["preset_name": .string("A"), "voice_a_channel": .int(1)]),
            Preset(key: "Preset_001", values: ["preset_name": .string("B")]),
            Preset(key: "Preset_002", values: ["preset_name": .string("A"), "voice_a_channel": .int(2)]),
        ])
        var slots = [String?](repeating: nil, count: 64)
        slots[0] = "A"
        slots[2] = "B"        // gap at slot 1
        slots[3] = "Missing"
        let resolved = ResolvedSetlist(setlist: Setlist(slots: slots), library: library)
        #expect(resolved.duplicateNames == ["A"])
        #expect(resolved.matched[0]?.voice(.a).channel == 2) // last duplicate wins
        #expect(resolved.missingNames == [3: "Missing"])
        #expect(resolved.imageCount == 2)
        #expect(resolved.uploadOrder.map { $0?.name } == ["A", nil]) // gap sent blank
        #expect(resolved.slotsDroppedByGaps == [2])                  // "B" never sent
    }

    @Test func libraryNumberingGapHidesHighestPresets() {
        let library = PresetLibrary(presets: [
            Preset(key: "Preset_000", values: ["preset_name": .string("A")]),
            Preset(key: "Preset_002", values: ["preset_name": .string("C")]),
        ])
        #expect(library.presetsInEditorOrder().map(\.name) == ["A"])
    }

    @Test func jsonValueKeepsIntegersAndMirrorsQVariant() throws {
        let decoded = try JSONDecoder().decode([String: JSONValue].self,
                                               from: Data(#"{"a":5,"b":3.86,"c":"12","d":true,"e":"x"}"#.utf8))
        #expect(decoded["a"] == .int(5))
        #expect(decoded["b"] == .double(3.86))
        #expect(decoded["c"]?.intValue == 12)
        #expect(decoded["d"] == .bool(true))
        #expect(decoded["e"]?.intValue == 0)
        #expect(JSONValue.null.stringValue == "")
        let reencoded = try JSONEncoder().encode(decoded)
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: reencoded) == decoded)
    }

    @Test func reportsMissingFilesAndBadJSON() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{".utf8).write(to: folder.appendingPathComponent("12Step.json"))
        #expect(PresetFolderContents.missingFiles(in: folder) == ["Blank.twelvesteppreset", "setlist.json", "settings.json"])
        #expect {
            try PresetFolderContents.load(from: folder)
        } throws: { error in
            if case .invalid(let file, _) = error as? PresetFolderError { file == "12Step.json" } else { false }
        }
    }
}

/// Opt-in check against a real preset folder, e.g. your backup:
/// `TWELVESTEP_FOLDER=../backups/desktop-presets-20261024 swift test --filter UserFolderTests`
struct UserFolderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TWELVESTEP_FOLDER"] != nil))
    func loadsUserFolder() throws {
        let path = try #require(ProcessInfo.processInfo.environment["TWELVESTEP_FOLDER"])
        let folder = URL(fileURLWithPath: path)
        #expect(PresetFolderContents.missingFiles(in: folder).isEmpty)
        let contents = try PresetFolderContents.load(from: folder)
        let resolved = contents.resolvedSetlist()
        print("library: \(contents.library.presets.count) presets; setlist: \(contents.setlist.usedSlotCount) slots used")
        for (slot, preset) in resolved.uploadOrder.enumerated() {
            let voice = preset?.voice(.a)
            print("  slot \(slot): \(preset?.name ?? "<blank>") [\(preset?.displayName ?? "    ")] voice A ch \(voice?.channel ?? 0) PC \(voice?.programChange ?? 0)")
        }
        print("missing: \(resolved.missingNames) duplicates: \(resolved.duplicateNames) dropped by gaps: \(resolved.slotsDroppedByGaps)")
    }
}

struct QtJSONWriterTests {
    static let factoryFolder = Bundle.module.url(forResource: "FactoryPresets", withExtension: nil)!

    /// Every file the desktop editor wrote must re-serialise byte for byte.
    static func assertRoundTrips(folder: URL) throws {
        for file in ["12Step.json", "setlist.json", "settings.json", "Blank.twelvesteppreset"] {
            let original = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(original.utf8))
            #expect(value.qtIndentedJSON() == original, "\(file) did not round-trip")
        }
    }

    @Test func factoryFilesRoundTripExactly() throws {
        try Self.assertRoundTrips(folder: Self.factoryFolder)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TWELVESTEP_FOLDER"] != nil))
    func userFilesRoundTripExactly() throws {
        try Self.assertRoundTrips(folder: URL(fileURLWithPath: ProcessInfo.processInfo.environment["TWELVESTEP_FOLDER"]!))
    }

    @Test func escapesLikeQt() {
        #expect(JSONValue.object(["a": .string("q\"\\\n\u{01}é")]).qtIndentedJSON() == "{\n    \"a\": \"q\\\"\\\\\\n\\u0001é\"\n}\n")
        #expect(JSONValue.object([:]).qtIndentedJSON() == "{\n}\n")
    }
}
