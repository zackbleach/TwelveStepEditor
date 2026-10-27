// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

/// One preset from the desktop editor's `12Step.json`, kept as its raw key/value map so that
/// unknown or future keys survive a read → write round trip.
public struct Preset: Equatable, Sendable {
    /// The library key, e.g. `Preset_007`.
    public let key: String
    public var values: [String: JSONValue]

    public init(key: String, values: [String: JSONValue]) {
        self.key = key
        self.values = values
    }

    public subscript(_ name: String) -> JSONValue {
        values[name] ?? .null
    }

    public var name: String { self["preset_name"].stringValue }

    /// The 4-character display text, one character per `preset_displayname_N` key.
    public var displayName: String {
        (1...4).map { index in
            let value = self["preset_displayname_\(index)"].stringValue
            return value.first.map(String.init) ?? " "
        }.joined()
    }

    /// Sets a voice's program change; -1 disables program change (and bank) messages.
    public mutating func setProgramChange(_ value: Int, voice: Voice) {
        precondition((-1...127).contains(value), "program change must be -1...127")
        values["\(voice.keyPrefix)_programchange"] = .int(value)
    }

    public func voice(_ voice: Voice) -> VoiceSettings {
        let prefix = voice.keyPrefix
        return VoiceSettings(channel: self["\(prefix)_channel"].intValue,
                             programChange: self["\(prefix)_programchange"].intValue,
                             bankLSB: self["\(prefix)_bank"].intValue,
                             bankMSB: self["\(prefix)_bank_msb"].intValue,
                             transpose: self["\(prefix)_transpose"].intValue)
    }

    public enum Voice: String, CaseIterable, Sendable {
        case a, b
        var keyPrefix: String { "voice_\(rawValue)" }
    }

    /// Values as the desktop editor stores them. -1 disables program change and bank messages.
    public struct VoiceSettings: Equatable, Sendable {
        public var channel: Int
        public var programChange: Int
        public var bankLSB: Int
        public var bankMSB: Int
        public var transpose: Int
    }
}

/// The desktop editor's preset library (`12Step.json`): `Preset_000`, `Preset_001`, …
public struct PresetLibrary: Equatable, Sendable {
    public var presets: [Preset]
    /// Top-level entries that aren't preset objects, kept so saving doesn't drop them.
    public var otherEntries: [String: JSONValue] = [:]

    public init(presets: [Preset]) {
        self.presets = presets
    }

    public init(data: Data) throws {
        let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        presets = object.keys.sorted().compactMap { key in
            object[key]?.objectValue.map { Preset(key: key, values: $0) }
        }
        otherEntries = object.filter { $0.value.objectValue == nil }
    }

    /// The file contents, formatted exactly as the desktop editor saves them.
    public func jsonData() -> Data {
        var object = otherEntries
        for preset in presets { object[preset.key] = .object(preset.values) }
        return Data(JSONValue.object(object).qtIndentedJSON().utf8)
    }

    public subscript(key key: String) -> Preset? {
        get { presets.first { $0.key == key } }
        set {
            guard let index = presets.firstIndex(where: { $0.key == key }) else { return }
            if let newValue { presets[index] = newValue } else { presets.remove(at: index) }
        }
    }

    /// Presets in the order the desktop editor scans them: it counts the entries, then looks up
    /// `Preset_000 ..< Preset_<count>` (`presetinterface.cpp:315-356`), so a gap in the numbering
    /// hides the highest-numbered presets from upload.
    public func presetsInEditorOrder() -> [Preset] {
        let byKey = Dictionary(presets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let count = presets.filter { $0.key.contains("Preset") }.count // slotGetNumPresetsInJson
        return (0..<count).compactMap { byKey[Self.key(forIndex: $0)] }
    }

    /// `PresetInterface::slotGetPresetStringFromInt`.
    public static func key(forIndex index: Int) -> String {
        String(format: "Preset_%03d", index)
    }
}

/// The 64-slot setlist (`setlist.json`): slot number → preset name, or `[EMPTY]`.
public struct Setlist: Equatable, Sendable {
    public static let slotCount = 64
    public static let emptyMarker = "[EMPTY]"

    /// Index = slot number; nil = empty.
    public var slots: [String?]

    public init(slots: [String?]) {
        self.slots = slots
    }

    public init(data: Data) throws {
        let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        var slots = [String?](repeating: nil, count: Self.slotCount)
        for (key, value) in object {
            guard let index = Int(key), slots.indices.contains(index) else { continue }
            let name = value.stringValue
            slots[index] = name == Self.emptyMarker ? nil : name
        }
        self.slots = slots
    }

    public var usedSlotCount: Int { slots.compactMap { $0 }.count }
}

/// Global settings (`settings.json`, the `Global` object).
public struct GlobalSettings: Equatable, Sendable {
    public var values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }

    public init(data: Data) throws {
        let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        values = object["Global"]?.objectValue ?? [:]
    }

    public subscript(_ name: String) -> JSONValue {
        values[name] ?? .null
    }
}

/// The four files the desktop editor keeps in its preset folder.
public struct PresetFolderContents: Equatable, Sendable {
    public static let libraryFile = "12Step.json"
    public static let setlistFile = "setlist.json"
    public static let settingsFile = "settings.json"
    public static let blankPresetFile = "Blank.twelvesteppreset"
    /// The desktop editor refuses to start without all four (`mainwindow.cpp:451`).
    public static let requiredFiles = [libraryFile, blankPresetFile, setlistFile, settingsFile]

    public var library: PresetLibrary
    public var setlist: Setlist
    public var settings: GlobalSettings
    /// `Blank.twelvesteppreset`: the values for a new or cleared preset.
    public var blank: Preset?

    public init(library: PresetLibrary, setlist: Setlist, settings: GlobalSettings, blank: Preset? = nil) {
        self.library = library
        self.setlist = setlist
        self.settings = settings
        self.blank = blank
    }

    /// Reads the files from a folder. Pass a reader to coordinate access (e.g. `NSFileCoordinator`).
    public static func load(from folder: URL,
                            read: (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> PresetFolderContents {
        func data(_ name: String) throws -> Data {
            let url = folder.appendingPathComponent(name)
            do {
                return try read(url)
            } catch {
                throw PresetFolderError.unreadable(file: name, underlying: error.localizedDescription)
            }
        }
        func parse<T>(_ name: String, _ make: (Data) throws -> T) throws -> T {
            let contents = try data(name)
            do {
                return try make(contents)
            } catch {
                throw PresetFolderError.invalid(file: name, underlying: String(describing: error))
            }
        }
        let blank = try? parse(blankPresetFile) { data -> Preset? in
            try JSONDecoder().decode(JSONValue.self, from: data).objectValue.map { Preset(key: "", values: $0) }
        }
        return PresetFolderContents(library: try parse(libraryFile, PresetLibrary.init(data:)),
                                    setlist: try parse(setlistFile, Setlist.init(data:)),
                                    settings: try parse(settingsFile, GlobalSettings.init(data:)),
                                    blank: blank ?? nil)
    }

    /// The factory presets shipped with the official editor, bundled with this package.
    public static func factory() throws -> PresetFolderContents {
        guard let folder = Bundle.module.url(forResource: "FactoryPresets", withExtension: nil) else {
            throw PresetFolderError.unreadable(file: "FactoryPresets", underlying: "missing from bundle")
        }
        return try load(from: folder)
    }

    /// Which required files are missing from a folder. The desktop editor treats any missing file
    /// as a broken install and offers to wipe the folder, so this is checked before using one.
    public static func missingFiles(in folder: URL, fileManager: FileManager = .default) -> [String] {
        requiredFiles.filter { !fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// The setlist as the desktop editor resolves it before upload (`MainWindow::slotSendPresets`).
    public func resolvedSetlist() -> ResolvedSetlist {
        ResolvedSetlist(setlist: setlist, library: library)
    }
}

public enum PresetFolderError: Error, Equatable, LocalizedError {
    case unreadable(file: String, underlying: String)
    case invalid(file: String, underlying: String)
    case changedOnDisk(file: String)
    case readOnlySource

    public var errorDescription: String? {
        switch self {
        case .changedOnDisk(let file): "\(file) changed since it was loaded (perhaps saved by the desktop editor or synced from another device). Nothing was saved; the latest version has been reloaded."
        case .readOnlySource: "The factory presets are read-only. Choose a folder to edit presets."
        case .unreadable(let file, let underlying): "Couldn't read \(file): \(underlying)"
        case .invalid(let file, let underlying): "\(file) isn't valid: \(underlying)"
        }
    }
}

/// Setlist slots matched to library presets by name, exactly as the desktop editor does it.
///
/// Quirks reproduced from `mainwindow.cpp:1567-1598` and `imageformatter.cpp:52-60`, because they
/// decide what actually reaches the device:
/// - Slots are matched by preset *name*; if several library presets share a name, the last one
///   in `Preset_NNN` order wins.
/// - Only matched slots are counted (`numScenes`), and images are then looked up by slot numbers
///   `0..<numScenes`. A gap in the setlist therefore produces a blank image at the gap and drops
///   the highest-numbered presets.
public struct ResolvedSetlist: Equatable, Sendable {
    /// Matched presets keyed by setlist slot.
    public let matched: [Int: Preset]
    /// Slots naming a preset that isn't in the library (sent as nothing).
    public let missingNames: [Int: String]
    /// Names that appear more than once in the library.
    public let duplicateNames: Set<String>

    public init(setlist: Setlist, library: PresetLibrary) {
        let ordered = library.presetsInEditorOrder()
        var byName: [String: Preset] = [:]
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for preset in ordered {
            if !seen.insert(preset.name).inserted { duplicates.insert(preset.name) }
            byName[preset.name] = preset // last one wins, like the desktop loop
        }
        var matched: [Int: Preset] = [:]
        var missing: [Int: String] = [:]
        for (slot, name) in setlist.slots.enumerated() {
            guard let name else { continue }
            if let preset = byName[name] { matched[slot] = preset } else { missing[slot] = name }
        }
        self.matched = matched
        missingNames = missing
        duplicateNames = duplicates
    }

    /// Number of images the desktop editor sends.
    public var imageCount: Int { matched.count }

    /// Image contents in upload order: index i holds the preset matched to slot i, or nil, which
    /// the editor sends as a blank image.
    public var uploadOrder: [Preset?] {
        (0..<imageCount).map { matched[$0] }
    }

    /// Slots whose preset won't reach the device because of a gap earlier in the setlist.
    public var slotsDroppedByGaps: [Int] {
        matched.keys.filter { $0 >= imageCount }.sorted()
    }
}
