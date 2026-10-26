import Foundation

/// Library and setlist operations with the desktop editor's semantics (`presetinterface.cpp`,
/// `setlist.cpp`, `copypastehandler.cpp`, `importexporthandler.cpp`), so files edited on either
/// side stay consistent.
extension Preset {
    /// The factory "init" preset (see `PresetFolderContents.listedPresets`).
    public var isInitTemplate: Bool { name.caseInsensitiveCompare("init") == .orderedSame }
}

extension PresetFolderContents {
    /// Presets in library order (`Preset_000` …).
    public var orderedPresets: [Preset] { library.presetsInEditorOrder() }

    /// Presets to list for editing: everything except the factory library's "init" entry, a
    /// blank template the desktop ships as the last preset. It stays in the files (and in the
    /// setlist, if a slot uses it); the app just doesn't offer it for editing or picking.
    public var listedPresets: [Preset] { orderedPresets.filter { !$0.isInitTemplate } }

    /// The desktop's "Save As" naming: "Name", then "Name copy1", "Name copy2", …
    public func uniqueName(for proposed: String) -> String {
        let names = Set(library.presets.map(\.name))
        let trimmed = proposed.trimmingCharacters(in: .whitespaces)
        var base = trimmed.isEmpty ? "New Preset" : trimmed
        // Strip an existing " copyN" so duplicating a copy doesn't produce "x copy1 copy1".
        if let range = base.range(of: #" copy\d*$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        if !names.contains(trimmed), !trimmed.isEmpty { return trimmed }
        var number = 1
        while names.contains("\(base) copy\(number)") { number += 1 }
        return "\(base) copy\(number)"
    }

    /// Appends a preset at the end of the library with a unique name; returns its key.
    @discardableResult
    public mutating func appendPreset(values: [String: JSONValue], name: String) -> String {
        var values = values
        values["preset_name"] = .string(uniqueName(for: name))
        values["presetVersion"] = .int(1)
        let ordered = orderedPresets
        let key = PresetLibrary.key(forIndex: ordered.count)
        library.presets = ordered + [Preset(key: key, values: values)]
        return key
    }

    /// Save As / Paste as new preset.
    @discardableResult
    public mutating func duplicatePreset(key: String) -> String? {
        guard let source = library[key: key] else { return nil }
        return appendPreset(values: source.values, name: source.name)
    }

    /// A new preset from `Blank.twelvesteppreset` (the desktop's Clear Preset values).
    @discardableResult
    /// Appends a blank preset (unique name, display suggested from the name). Returns its key.
    public mutating func newPreset(name: String = "New Preset") -> String {
        let key = appendPreset(values: blankPreset.values, name: name)
        if var preset = library[key: key] {
            preset.displayCharacters = Preset.suggestedDisplay(for: preset.name)
            library[key: key] = preset
        }
        return key
    }

    /// Deletes a preset, renumbers the library, and empties setlist slots that used it
    /// (`Setlist::slotPopulateSetlistAfterDelete`).
    public mutating func deletePreset(key: String) {
        guard let removed = library[key: key] else { return }
        let remaining = orderedPresets.filter { $0.key != key }
        library.presets = remaining.enumerated().map { Preset(key: PresetLibrary.key(forIndex: $0.offset), values: $0.element.values) }
        if !library.presets.contains(where: { $0.name == removed.name }) {
            setlist.slots = setlist.slots.map { $0 == removed.name ? nil : $0 }
        }
    }

    /// Renames a preset and updates setlist slots that referred to the old name.
    /// (The desktop matches slots by name, so without this they would silently become empty.)
    public mutating func renamePreset(key: String, to proposed: String) {
        guard var preset = library[key: key] else { return }
        let oldName = preset.name
        let trimmed = proposed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        let newName = uniqueName(for: trimmed)
        preset.nameValue = newName
        library[key: key] = preset
        if !library.presets.contains(where: { $0.name == oldName }) {
            setlist.slots = setlist.slots.map { $0 == oldName ? newName : $0 }
        }
    }

    /// Replaces a preset's settings with another's, keeping its name (Paste).
    public mutating func pasteSettings(_ values: [String: JSONValue], into key: String) {
        guard var preset = library[key: key] else { return }
        let name = preset.name
        preset.values = values
        preset.nameValue = name
        library[key: key] = preset
    }

    /// Resets a preset to the blank preset's values, keeping its name (Clear Preset).
    public mutating func clearPreset(key: String) {
        pasteSettings(blankPreset.values, into: key)
    }

    /// `Blank.twelvesteppreset` from the folder, or the bundled one.
    public var blankPreset: Preset {
        blank ?? (try? PresetFolderContents.factory().blank) ?? Preset(key: "", values: [:])
    }

    /// Imports a `.twelvesteppreset` file (one preset's JSON object). Returns the new key.
    @discardableResult
    public mutating func importPreset(data: Data) throws -> String {
        guard case .object(let values) = try JSONDecoder().decode(JSONValue.self, from: data),
              values["preset_name"] != nil || values["key01_note1"] != nil else {
            throw PresetFolderError.invalid(file: "preset", underlying: "not a 12 Step preset")
        }
        let name = values["preset_name"]?.stringValue ?? "Imported"
        return appendPreset(values: values, name: name)
    }

    /// The `.twelvesteppreset` contents for export.
    public func exportPreset(key: String) -> Data? {
        library[key: key].map { Data(JSONValue.object($0.values).qtIndentedJSON().utf8) }
    }

    // MARK: Setlist

    /// Edit → Auto-populate setlist: library order into slots 1… (up to 64).
    public mutating func autoPopulateSetlist() {
        let names = orderedPresets.prefix(Setlist.slotCount).map(\.name)
        setlist.slots = (0..<Setlist.slotCount).map { $0 < names.count ? names[$0] : nil }
    }

    public mutating func clearSetlist() {
        setlist.slots = Array(repeating: nil, count: Setlist.slotCount)
    }
}

extension Setlist {
    /// The used slots in order (compacted).
    public var entries: [String] { slots.compactMap { $0 } }

    /// Replaces the setlist with these names, compacted from slot 1, so uploads have no gaps.
    public mutating func setEntries(_ names: [String]) {
        let kept = Array(names.prefix(Self.slotCount))
        slots = (0..<Self.slotCount).map { $0 < kept.count ? kept[$0] : nil }
    }

    /// True if an empty slot comes before a used one (such gaps drop presets on upload).
    public var hasGaps: Bool {
        guard let last = slots.lastIndex(where: { $0 != nil }) else { return false }
        return slots[...last].contains { $0 == nil }
    }

    /// `setlist.json` exactly as the desktop writes it: "0"…"63" → name or "[EMPTY]".
    public func jsonData() -> Data {
        var object: [String: JSONValue] = [:]
        for (index, name) in slots.enumerated() {
            object[String(index)] = .string(name ?? Self.emptyMarker)
        }
        return Data(JSONValue.object(object).qtIndentedJSON().utf8)
    }
}

extension GlobalSettings {
    /// `settings.json`: `{"Global": {…}}`.
    public func jsonData() -> Data {
        Data(JSONValue.object(["Global": .object(values)]).qtIndentedJSON().utf8)
    }

    // Typed views using the desktop Settings tab's ranges and conversions (`settings.cpp`).

    /// Slider 1...500, stored as slider / 100. Shown as slider / 5 percent.
    public var keySensitivitySlider: Int {
        get { Int((self["globalSensitivity"].doubleValue * 100).rounded()) }
        set { values["globalSensitivity"] = Self.number(Double(newValue) / 100) }
    }

    public var onThreshold: Int {
        get { values["onThreshold"]?.intValue ?? 15 }
        set { values["onThreshold"] = .int(newValue) }
    }

    public var offThreshold: Int {
        get { values["offThreshold"]?.intValue ?? 5 }
        set { values["offThreshold"] = .int(newValue) }
    }

    /// 1...127, × 50 ms.
    public var selectHoldTime: Int {
        get { self["selectSensitivity"].intValue }
        set { values["selectSensitivity"] = .int(newValue) }
    }

    /// 0...29 (12 Step2 only).
    public var backlightBrightness: Int {
        get { self["backlightBrightness"].intValue }
        set { values["backlightBrightness"] = .int(newValue) }
    }

    public var fullVolumeOnPresetChange: Bool {
        get { self["midiVolume"].intValue != 0 }
        set { values["midiVolume"] = .int(newValue ? 1 : 0) }
    }

    public var velocityOverride: Bool {
        get { self["velocityOverride"].intValue != 0 }
        set { values["velocityOverride"] = .int(newValue ? 1 : 0) }
    }

    /// 0...15 = channel 1...16, 16 = disabled. Defaults to channel 10.
    public var programChangeChannel: Int {
        get { values["progchgRXchannel"]?.intValue ?? 9 }
        set { values["progchgRXchannel"] = .int(newValue) }
    }

    static func number(_ value: Double) -> JSONValue {
        value == value.rounded() ? .int(Int(value)) : .double(value)
    }
}
