import Foundation
import Testing
@testable import TwelveStepKit

@MainActor
struct PresetFolderStoreTests {
    let defaults = UserDefaults(suiteName: "PresetFolderStoreTests-\(UUID().uuidString)")!
    let onDevice = FileManager.default.temporaryDirectory.appendingPathComponent("ondevice-\(UUID().uuidString)")

    func makeFolder(copying files: [String] = PresetFolderContents.requiredFiles) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let factory = try #require(Bundle.module.url(forResource: "FactoryPresets", withExtension: nil))
        for file in files {
            try FileManager.default.copyItem(at: factory.appendingPathComponent(file), to: folder.appendingPathComponent(file))
        }
        return folder
    }

    @Test func seedsAnEditableOnDeviceFolderFromFactoryPresets() throws {
        defer { try? FileManager.default.removeItem(at: onDevice) }
        let store = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        store.reload()
        #expect(store.source == .onDevice)
        #expect(store.contents?.library.presets.count == 21)
        #expect(PresetFolderContents.missingFiles(in: onDevice).isEmpty)

        var preset = try #require(store.contents?.library[key: "Preset_000"])
        preset.setProgramChange(5, voice: .a)
        try store.save(preset)
        let reloaded = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        reloaded.reload()
        #expect(reloaded.contents?.library[key: "Preset_000"]?.voice(.a).programChange == 5)

        try reloaded.restoreFactoryPresets()
        reloaded.reload()
        #expect(reloaded.contents?.library[key: "Preset_000"]?.voice(.a).programChange == -1)
    }

    @Test func backgroundUpdatesShowAtOnceAndSaveInOrder() async throws {
        defer { try? FileManager.default.removeItem(at: onDevice) }
        let store = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        store.reload()
        let original = try #require(store.contents?.setlist.entries)
        var failures = 0
        for _ in 0..<5 {
            try store.updateInBackground({ contents in
                var entries = contents.setlist.entries
                entries.append(entries.removeFirst())
                contents.setlist.setEntries(entries)
            }, onError: { _ in failures += 1 })
        }
        let rotated = Array(original[5...] + original[..<5])
        #expect(store.contents?.setlist.entries == rotated)  // visible before any write finishes
        await store.waitForPendingWrites()
        #expect(failures == 0)
        let reloaded = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        reloaded.reload()
        #expect(reloaded.contents?.setlist.entries == rotated)
    }

    @Test func remembersPickedFolderAcrossLaunches() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        store.useFolder(folder)
        #expect(store.contents?.setlist.usedSlotCount == 21)

        let relaunched = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        guard case .folder(let restored) = relaunched.source else {
            Issue.record("folder not restored")
            return
        }
        #expect(restored.standardizedFileURL.resolvingSymlinksInPath() == folder.standardizedFileURL.resolvingSymlinksInPath())
        #expect(throws: PresetFolderError.readOnlySource) { try relaunched.restoreFactoryPresets() }

        relaunched.useOnDeviceFolder()
        #expect(PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice).source == .onDevice)
        try? FileManager.default.removeItem(at: onDevice)
    }

    @Test func explainsAFolderWithMissingFiles() throws {
        let folder = try makeFolder(copying: ["12Step.json", "setlist.json"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        store.useFolder(folder)
        #expect(store.contents == nil)
        #expect(store.loadError?.contains("Blank.twelvesteppreset, settings.json") == true)
    }

    @Test func commitWritesOnlyChangedFilesAndRefusesConflicts() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PresetFolderStore(defaults: defaults, onDeviceFolder: onDevice)
        store.useFolder(folder)
        let libraryBefore = try Data(contentsOf: folder.appendingPathComponent("12Step.json"))

        try store.update { $0.setlist.setEntries(["Legato", "Hold"]) }
        #expect(try Data(contentsOf: folder.appendingPathComponent("12Step.json")) == libraryBefore)
        #expect(try Setlist(data: Data(contentsOf: folder.appendingPathComponent("setlist.json"))).entries == ["Legato", "Hold"])

        // Another device edits settings.json; our settings save must refuse and reload.
        var external = try #require(store.contents?.settings)
        external.backlightBrightness = 3
        try external.jsonData().write(to: folder.appendingPathComponent("settings.json"))
        #expect(throws: PresetFolderError.changedOnDisk(file: "settings.json")) {
            try store.update { $0.settings.backlightBrightness = 20 }
        }
        #expect(store.contents?.settings.backlightBrightness == 3)
    }
}
