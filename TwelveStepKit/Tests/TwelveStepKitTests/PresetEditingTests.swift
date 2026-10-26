import Foundation
import Testing
@testable import TwelveStepKit

struct PresetEditingTests {
    var factory: PresetFolderContents { try! PresetFolderContents.factory() }

    @Test func notesCompactPadAndClipLikeTheDesktop() throws {
        var preset = try #require(factory.library[key: "Preset_000"])
        preset.setNotes([60, -1, 64, 67, 72, 76, 79], forKey: 3)
        #expect(preset.notes(forKey: 3) == [60, 64, 67, 72, 76])
        #expect(preset["key03_note5"] == .int(76))
        preset.setNotes([126], forKey: 3)
        #expect(preset["key03_note2"] == .int(-1))
        preset.transposeKey(3, by: 5)
        #expect(preset.notes(forKey: 3) == [127])
        preset.transposeAllKeys(by: -12)
        #expect(preset.notes(forKey: 1) == [36])
        preset.clearAllKeys()
        #expect((1...13).allSatisfy { preset.notes(forKey: $0).isEmpty })
    }

    @Test func displayCharactersUseEmptyStringsForBlanks() throws {
        var preset = try #require(factory.library[key: "Preset_000"])
        preset.displayCharacters = ["A", " ", "1", "-"]
        #expect(preset["preset_displayname_2"] == .string(""))
        #expect(preset.displayName == "A 1-")
    }

    @Test func modlineRoundTripKeepsIntegerGain() throws {
        var preset = try #require(factory.library[key: "Preset_000"])
        var modline = Modline.off
        modline.destination = "CC"; modline.ccNumber = 11; modline.sourceA = "Pressure"
        preset.setModline(modline, 3)
        #expect(preset.modline(3) == modline)
        #expect(preset["modline3_gain"] == .int(1))
        #expect(preset.activeExtraModlines.contains(3))
    }

    @Test func fillPatternsReproduceFactoryPresets() throws {
        let presets = factory.library.presets
        func keys(_ name: String) -> [[Int]] {
            let preset = presets.first { $0.name == name }!
            return (1...13).map { preset.notes(forKey: $0) }
        }
        #expect(KeyPattern(octave: 2, layout: .chromatic, voicing: .single).notesForKeys() == keys("Chromatic"))
        #expect(KeyPattern(octave: 2, layout: .chromatic, voicing: .fifths).notesForKeys() == keys("Fifths"))
        // Keys stay chromatic: key 1 = C, key 3 = D, key 8 = G, key 13 = C an octave up.
        let major = KeyPattern(octave: 3, layout: .major, voicing: .triads).notesForKeys()
        #expect(major[0] == [60, 64, 67])   // C
        #expect(major[1] == [])             // C♯: outside the scale, silent by default
        #expect(major[2] == [62, 65, 69])   // Dm
        #expect(major[7] == [67, 71, 74])   // G
        #expect(major[12] == [72, 76, 79])  // C
        #expect(KeyPattern.parseIntervals("+7, +12 x") == [7, 12])

        var pattern = KeyPattern(octave: 3, layout: .major, voicing: .triads, outOfScale: .nearest)
        #expect(pattern.notesForKeys()[1] == [60, 64, 67])          // C♯ → C (tie goes down)
        pattern.outOfScale = .leadingDiminished
        #expect(pattern.notesForKeys()[1] == [61, 64, 67, 70])      // C♯dim7 → Dm
        pattern.outOfScale = .secondaryDominant
        #expect(pattern.notesForKeys()[1] == [61, 64, 67, 69])      // A7/C♯ → Dm
        #expect(pattern.notesForKeys()[6] == [66, 69, 72, 74])      // D7/F♯ → G
        #expect(NoteNames.label(for: pattern.notesForKeys()[1]) == "A7/C♯")
        #expect(NoteNames.label(for: pattern.notesForKeys()[6]) == "D7/F♯")
        #expect(NoteNames.label(for: [64, 67, 72]) == "C/E")

        // Another key: key 1 stays C. F major 7ths → C7, (C♯ silent), Dm7, …, F on key 6.
        let fMajor = KeyPattern(octave: 3, tonic: 5, layout: .major, voicing: .sevenths).notesForKeys()
        #expect(NoteNames.label(for: fMajor[0]) == "C7")
        #expect(fMajor[1] == [])
        #expect(NoteNames.label(for: fMajor[2]) == "Dm7")
        #expect(NoteNames.label(for: fMajor[5]) == "Fmaj7")
        #expect(fMajor[5].min() == 65)          // F4, on the F key
        #expect(NoteNames.label(for: fMajor[10]) == "A♯maj7")  // B♭maj7 (names use sharps)
        #expect(NoteNames.label(for: fMajor[12]) == "C7")

        // Nearest in a pentatonic scale picks the closer note, not always the one below.
        let pentatonic = KeyPattern(octave: 3, layout: .majorPentatonic, voicing: .single, outOfScale: .nearest).notesForKeys()
        #expect(pentatonic[5] == [64])  // F → E (1 below) rather than G (2 above)
        #expect(pentatonic[6] == [67])  // F♯ → G (1 above) rather than E (2 below)
    }

    @Test func chordsAreNamed() {
        #expect(NoteNames.label(for: [60]) == "C3")  // desktop convention: middle C = C3
        #expect(NoteNames.label(for: [60, 64, 67]) == "C")
        #expect(NoteNames.label(for: [62, 65, 69]) == "Dm")
        #expect(NoteNames.label(for: [48, 55]) == "C 5th")
        #expect(NoteNames.label(for: [48, 60]) == "C2 oct")
        #expect(NoteNames.label(for: [60, 61]) == "C3 C♯3")
        #expect(Chord.quickPicks.first { $0.name == "maj7" }?.notes(root: 60) == [60, 64, 67, 71])
        #expect(NoteNames.label(for: [60, 63, 66, 69]) == "Cdim7")
        #expect(NoteNames.label(for: [59, 62, 65, 69]) == "Bm7♭5")
        #expect(Chord.quickPicks.first { $0.name == "7alt" }?.notes(root: 60) == [60, 64, 70, 75, 80])
        #expect(NoteNames.label(for: [60, 64, 67, 70, 75]) == "C7♯9")
        #expect(Chord.quickPicks.allSatisfy { $0.intervals.count <= Preset.notesPerKey })
        // Every quick pick except Single/Octave is named back from its own notes.
        for chord in Chord.quickPicks where chord.intervals.count > 1 && chord.name != "Octave" {
            #expect(NoteNames.label(for: chord.notes(root: 60)) == "C" + chord.suffix, "\(chord.name)")
        }
    }

    @Test func libraryOperationsFollowDesktopSemantics() throws {
        var contents = factory
        #expect(contents.uniqueName(for: "Legato") == "Legato copy1")
        #expect(contents.uniqueName(for: "Brand New") == "Brand New")

        let duplicated = contents.duplicatePreset(key: "Preset_001")
        let copy = try #require(duplicated)
        #expect(copy == "Preset_021")
        #expect(contents.library[key: copy]?.name == "Legato copy1")
        #expect(contents.uniqueName(for: "Legato copy1") == "Legato copy2")

        contents.renamePreset(key: "Preset_001", to: "Smooth")
        #expect(contents.setlist.slots[1] == "Smooth")

        contents.deletePreset(key: "Preset_001")
        #expect(contents.setlist.slots[1] == nil)
        #expect(contents.library.presets.count == 21)
        #expect(contents.orderedPresets.map(\.key) == (0..<21).map { PresetLibrary.key(forIndex: $0) })

        let new = contents.newPreset()
        #expect(contents.library[key: new]?.voice(.a).channel == 1)
        #expect(contents.library[key: new]?.name == "New Preset")
        #expect(contents.library[key: new]?.displayName == "NEPR")      // W and spaces are skipped
        let named = contents.newPreset(name: "Bass 2")
        #expect(contents.library[key: named]?.displayName == "BASS")
        #expect(Preset.suggestedDisplay(for: "x") == [" ", " ", " ", " "])
    }

    @Test func importExportRoundTrip() throws {
        var contents = factory
        let data = try #require(contents.exportPreset(key: "Preset_003"))
        let key = try contents.importPreset(data: data)
        #expect(contents.library[key: key]?.name == "Hold copy1")
        #expect(throws: PresetFolderError.self) { try contents.importPreset(data: Data("[1]".utf8)) }
    }

    @Test func setlistEditing() {
        var contents = factory
        contents.clearSetlist()
        #expect(contents.setlist.entries.isEmpty)
        contents.autoPopulateSetlist()
        #expect(contents.setlist.entries.count == 21)
        contents.setlist.setEntries(["A", "B"])
        #expect(contents.setlist.slots[0...2] == ["A", "B", nil])
        #expect(factory.listedPresets.count == 20)
        #expect(!factory.listedPresets.contains { $0.name == "init" })
        #expect(!contents.setlist.hasGaps)
        contents.setlist.slots[5] = "C"
        #expect(contents.setlist.hasGaps)
    }

    @Test func settingsConversionsMatchDesktop() throws {
        var settings = factory.settings
        #expect(settings.keySensitivitySlider == 386)
        settings.keySensitivitySlider = 100
        #expect(settings["globalSensitivity"] == .int(1))
        settings.keySensitivitySlider = 250
        #expect(settings["globalSensitivity"] == .double(2.5))
        #expect(settings.programChangeChannel == 9)
        settings.fullVolumeOnPresetChange = true
        #expect(settings["midiVolume"] == .int(1))
    }

    @Test func savedFilesKeepDesktopFormatting() throws {
        let folder = Bundle.module.url(forResource: "FactoryPresets", withExtension: nil)!
        let contents = factory
        #expect(String(decoding: contents.setlist.jsonData(), as: UTF8.self) == (try String(contentsOf: folder.appendingPathComponent("setlist.json"), encoding: .utf8)))
        #expect(String(decoding: contents.settings.jsonData(), as: UTF8.self) == (try String(contentsOf: folder.appendingPathComponent("settings.json"), encoding: .utf8)))
    }
}
