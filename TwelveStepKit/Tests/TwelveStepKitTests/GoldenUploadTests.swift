// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Testing
@testable import TwelveStepKit

/// Compares the Swift formatter with bytes from the official C++ (Tools/golden-harness).
struct GoldenUploadTests {
    struct Golden {
        let setlist: [UInt8]?
        let settings: [UInt8]

        init(contentsOf url: URL) throws {
            var setlist: [UInt8]?
            var settings: [UInt8] = []
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let parts = line.split(separator: " ")
                let bytes = parts.dropFirst().map { UInt8($0, radix: 16)! }
                if parts.first == "SETLIST" { setlist = bytes.isEmpty ? nil : bytes }
                if parts.first == "SETTINGS" { settings = bytes }
            }
            self.setlist = setlist
            self.settings = settings
        }
    }

    static func compare(_ contents: PresetFolderContents, with golden: Golden) throws {
        let setlist = PresetImageFormatter.setlistMessage(for: contents.resolvedSetlist())
        #expect(setlist?.count == golden.setlist?.count)
        if let setlist, let expected = golden.setlist, setlist != expected {
            let index = zip(setlist, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(setlist.count, expected.count)
            Issue.record("setlist differs from C++ at byte \(index)")
        }
        #expect(PresetImageFormatter.settingsMessage(for: contents.settings) == golden.settings)

        // And the decoded payloads round-trip through our framing decoder.
        if let setlist {
            let packet = try KMIFraming.decode(setlist)
            #expect(packet.packetType == 9)
            #expect(packet.blocks.count == contents.resolvedSetlist().imageCount + 1)
            #expect(packet.blocks.dropFirst().allSatisfy { $0.count == PresetImageFormatter.imageSize })
        }
    }

    @Test func factoryPresetsMatchOfficialEditorBytes() throws {
        let golden = try Golden(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Golden/factory-presets.golden"))
        try Self.compare(PresetFolderContents.factory(), with: golden)
    }

    /// `TWELVESTEP_FOLDER=<folder> TWELVESTEP_GOLDEN=<golden file> swift test --filter userFolderMatches`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TWELVESTEP_GOLDEN"] != nil))
    func userFolderMatchesOfficialEditorBytes() throws {
        let environment = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: try #require(environment["TWELVESTEP_FOLDER"]))
        let golden = try Golden(contentsOf: URL(fileURLWithPath: try #require(environment["TWELVESTEP_GOLDEN"])))
        try Self.compare(PresetFolderContents.load(from: folder), with: golden)
    }

    @Test func imageAndSettingsLayoutSizes() throws {
        #expect(PresetImageFormatter.image(for: nil, slot: 3).count == 191)
        let blank = PresetImageFormatter.image(for: nil, slot: 3)
        #expect(blank[0] == 3)
        #expect(Array(blank[100...103]) == Array("    ".utf8)) // display defaults to spaces
        #expect(PresetImageFormatter.settingsBytes(GlobalSettings(values: [:])).count == 15)
    }

    @Test func modlineSixIsIgnoredLikeTheDesktopEditor() {
        var values: [String: JSONValue] = ["modline6_destination": .string("Bend"), "modline6_gain": .int(1)]
        let withSix = PresetImageFormatter.image(for: Preset(key: "Preset_000", values: values), slot: 0)
        values = ["modline5_destination": .string("Bend"), "modline5_gain": .int(1)]
        let withFive = PresetImageFormatter.image(for: Preset(key: "Preset_000", values: values), slot: 0)
        #expect(withSix == PresetImageFormatter.image(for: nil, slot: 0).replacingDisplay(with: withSix))
        #expect(Array(withFive[12...15]) == [0x00, 0x01, 0x00, 0x00]) // bend gain 1.0 in 16.16, big-endian
    }

    @Test func emptySetlistSendsNothing() {
        let resolved = ResolvedSetlist(setlist: Setlist(slots: Array(repeating: nil, count: 64)), library: PresetLibrary(presets: []))
        #expect(PresetImageFormatter.setlistMessage(for: resolved) == nil)
    }
}

private extension Array where Element == UInt8 {
    func replacingDisplay(with other: [UInt8]) -> [UInt8] {
        var copy = self
        copy.replaceSubrange(100...103, with: other[100...103])
        return copy
    }
}
