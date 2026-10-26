import Foundation

/// Typed access to every preset field the desktop editor exposes, using the same JSON keys and
/// value spellings, so files stay interchangeable with the 12 Step Editor.
extension Preset {
    public static let keyCount = 13
    public static let notesPerKey = 5
    /// Modlines that actually reach the device (the desktop formatter never sends modline 6).
    public static let sentModlineCount = 5
    /// Modline numbers stored in the JSON (1-based).
    public static let storedModlineCount = 6

    // MARK: Identity

    public var nameValue: String {
        get { name }
        set { values["preset_name"] = .string(newValue) }
    }

    /// The 4 display characters; characters outside the device's set are shown as-is but can't be picked.
    public var displayCharacters: [Character] {
        get {
            (1...4).map { self["preset_displayname_\($0)"].stringValue.first ?? " " }
        }
        set {
            for index in 1...4 {
                let character = index - 1 < newValue.count ? newValue[index - 1] : " "
                // The desktop stores an empty string for a blank position.
                values["preset_displayname_\(index)"] = .string(character == " " ? "" : String(character))
            }
        }
    }

    /// Characters the 12 Step's display can show (the desktop editor's display-name menu), plus space.
    public static let displayCharacterSet: [Character] = Array(" -_0123456789ABCDEFGHIJLNOPQRSTUYZ")

    // MARK: Keys

    static func noteKey(key: Int, note: Int) -> String {
        String(format: "key%02d_note%d", key, note)
    }

    /// The notes assigned to a key (1...13), in stored order, without empty slots.
    public func notes(forKey key: Int) -> [Int] {
        (1...Self.notesPerKey).compactMap { note in
            let value = self[Self.noteKey(key: key, note: note)].intValue
            return (0...127).contains(value) ? value : nil
        }
    }

    /// Stores up to 5 notes, compacted to the front and padded with -1, like the desktop's reorder.
    public mutating func setNotes(_ notes: [Int], forKey key: Int) {
        let kept = Array(notes.filter { (0...127).contains($0) }.prefix(Self.notesPerKey))
        for slot in 1...Self.notesPerKey {
            values[Self.noteKey(key: key, note: slot)] = .int(slot <= kept.count ? kept[slot - 1] : -1)
        }
    }

    /// The desktop's Transpose Up/Down: shifts and clips to 0...127.
    public mutating func transposeKey(_ key: Int, by semitones: Int) {
        setNotes(notes(forKey: key).map { min(127, max(0, $0 + semitones)) }, forKey: key)
    }

    public mutating func transposeAllKeys(by semitones: Int) {
        for key in 1...Self.keyCount { transposeKey(key, by: semitones) }
    }

    public mutating func clearAllKeys() {
        for key in 1...Self.keyCount { setNotes([], forKey: key) }
    }

    // MARK: Voices

    public mutating func setVoice(_ settings: VoiceSettings, voice: Voice) {
        let prefix = voice.keyPrefix
        values["\(prefix)_channel"] = .int(settings.channel)
        values["\(prefix)_programchange"] = .int(settings.programChange)
        values["\(prefix)_bank"] = .int(settings.bankLSB)
        values["\(prefix)_bank_msb"] = .int(settings.bankMSB)
        values["\(prefix)_transpose"] = .int(settings.transpose)
    }

    // MARK: Behaviour

    public enum NoteMode: String, CaseIterable, Sendable {
        case normal = "Normal", legato = "Legato", toggle = "Toggle", hold = "Hold"
    }

    /// "Key Mode" in the desktop UI (stored as `settings_key_safety_mode`).
    public enum KeyMode: String, CaseIterable, Sendable {
        case mono = "Mono", poly = "Poly"
    }

    public var noteMode: NoteMode {
        get { NoteMode(rawValue: self["settings_note_mode"].stringValue) ?? .normal }
        set { values["settings_note_mode"] = .string(newValue.rawValue) }
    }

    public var keyMode: KeyMode {
        get {
            // Older files use "Single Key" / "Multi Key" (and without spaces); same meaning.
            switch self["settings_key_safety_mode"].stringValue {
            case "Mono", "Single Key", "SingleKey": .mono
            default: .poly
            }
        }
        set { values["settings_key_safety_mode"] = .string(newValue.rawValue) }
    }

    // MARK: CV (12 Step2)

    public enum CVOutput: Int, CaseIterable, Sendable {
        case one = 1, two = 2
        public var defaultLocalLabel: String { self == .one ? "Default (Gate)" : "Default (Pitch)" }
    }

    public static let cvLocalModes = ["Default", "Gate", "Pitch", "Velocity", "Pressure", "Tilt", "Expression Pedal", "Disabled"]
    public static let cvUSBModes = ["Gate", "Pitch", "Velocity", "Bend / Mod"]
    public static let cvUSBChannels = ["Ch 1", "Ch 2"]

    /// Local mode label, with "Default" standing for the output's "Default (Gate)/(Pitch)".
    public func cvLocalMode(_ output: CVOutput) -> String {
        let value = self["settings_cv\(output.rawValue)_local"].stringValue
        return value.hasPrefix("Default") || value.isEmpty ? "Default" : value
    }

    public mutating func setCVLocalMode(_ mode: String, _ output: CVOutput) {
        values["settings_cv\(output.rawValue)_local"] = .string(mode == "Default" ? output.defaultLocalLabel : mode)
    }

    public func cvUSBMode(_ output: CVOutput) -> String {
        let value = self["settings_cv\(output.rawValue)_usb"].stringValue
        return Self.cvUSBModes.contains(value) ? value : "Gate"
    }

    public mutating func setCVUSBMode(_ mode: String, _ output: CVOutput) {
        values["settings_cv\(output.rawValue)_usb"] = .string(mode)
    }

    public func cvUSBChannel(_ output: CVOutput) -> String {
        let value = self["settings_cv\(output.rawValue)_usb_ch"].stringValue
        return Self.cvUSBChannels.contains(value) ? value : "Ch 1"
    }

    public mutating func setCVUSBChannel(_ channel: String, _ output: CVOutput) {
        values["settings_cv\(output.rawValue)_usb_ch"] = .string(channel)
    }

    // MARK: Modlines

    public func modline(_ number: Int) -> Modline {
        func field(_ name: String) -> JSONValue { self["modline\(number)_\(name)"] }
        return Modline(destination: field("destination").stringValue.isEmpty ? "Off" : field("destination").stringValue,
                       ccNumber: field("cc_number").intValue,
                       sourceA: field("source_a").stringValue.isEmpty ? "Off" : field("source_a").stringValue,
                       sourceB: field("source_b").stringValue.isEmpty ? "Off" : field("source_b").stringValue,
                       gain: field("gain").doubleValue,
                       offset: field("offset").intValue,
                       curve: field("table").stringValue.isEmpty ? "Linear" : field("table").stringValue,
                       min: field("min").intValue,
                       max: values["modline\(number)_max"] == nil ? 127 : field("max").intValue,
                       smooth: field("smooth").intValue)
    }

    public mutating func setModline(_ modline: Modline, _ number: Int) {
        func set(_ name: String, _ value: JSONValue) { values["modline\(number)_\(name)"] = value }
        set("destination", .string(modline.destination))
        set("cc_number", .int(modline.ccNumber))
        set("source_a", .string(modline.sourceA))
        set("source_b", .string(modline.sourceB))
        // Keep integers as integers so saved files match the desktop's.
        set("gain", modline.gain == modline.gain.rounded() ? .int(Int(modline.gain)) : .double(modline.gain))
        set("offset", .int(modline.offset))
        set("table", .string(modline.curve))
        set("min", .int(modline.min))
        set("max", .int(modline.max))
        set("smooth", .int(modline.smooth))
    }

    /// Modline numbers (2...5) currently in use beyond the fixed Note modline.
    public var activeExtraModlines: [Int] {
        (2...Self.sentModlineCount).filter { modline($0).isActive }
    }

    /// True if modline 6 holds settings that the desktop editor's formatter never sends.
    public var hasUnsentModlineSix: Bool { modline(6).isActive }
}

public struct Modline: Equatable, Sendable {
    public var destination: String
    public var ccNumber: Int
    public var sourceA: String
    public var sourceB: String
    public var gain: Double
    public var offset: Int
    public var curve: String
    public var min: Int
    public var max: Int
    public var smooth: Int

    public var isActive: Bool { destination != "Off" && (sourceA != "Off" || sourceB != "Off") }

    /// Modline 1 is always "Note" (velocity) in the desktop editor; others choose from these.
    public static let destinations = ["Off", "Bend", "CC", "Channel Pressure", "Poly Aftertouch"]
    public static let sources = PresetImageFormatter.sourceMenu
    public static let curves = PresetImageFormatter.tableMenu

    /// The desktop's fresh modline (Blank.twelvesteppreset).
    public static let off = Modline(destination: "Off", ccNumber: -1, sourceA: "Off", sourceB: "Off", gain: 1,
                                    offset: 0, curve: "Linear", min: 0, max: 127, smooth: 0)
}

// MARK: - Notes and chords

public enum NoteNames {
    static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// "C4" for 60 (middle C = C4, as in the Monitor).
    public static func name(_ note: Int) -> String {
        "\(names[((note % 12) + 12) % 12])\(note / 12 - 1)"
    }

    public static func pitchClass(_ note: Int) -> String {
        names[((note % 12) + 12) % 12]
    }

    /// The natural pitch of a key on the 12 Step's one-octave layout, starting from C3 (48),
    /// which is what the factory Chromatic preset uses.
    public static func naturalNote(forKey key: Int) -> Int { 47 + key }

    /// The physical layout: keys 2, 4, 7, 9, 11 are the raised ("black") keys.
    public static func isRaised(key: Int) -> Bool { [2, 4, 7, 9, 11].contains(key) }

    /// A short label for a set of notes: a chord name when recognisable, otherwise note names.
    public static func label(for notes: [Int]) -> String {
        guard let lowest = notes.min() else { return "—" }
        if notes.count == 1 { return name(lowest) }
        if let chord = Chord.identify(notes) { return chord }
        return notes.sorted().map(name).joined(separator: " ")
    }
}

public struct Chord: Equatable, Sendable, Identifiable {
    public enum Group: String, CaseIterable, Sendable {
        case basic = "Single notes"
        case major = "Major"
        case minor = "Minor"
        case dominant = "Dominant"
        case suspended = "Suspended"
        case diminished = "Diminished & augmented"
    }

    public let name: String
    public let suffix: String
    /// Semitones above the root.
    public let intervals: [Int]
    public let group: Group
    public var id: String { name }

    public static let quickPicks: [Chord] = [
        Chord(name: "Single", suffix: "", intervals: [0], group: .basic),
        Chord(name: "Octave", suffix: " oct", intervals: [0, 12], group: .basic),
        Chord(name: "Power", suffix: " 5th", intervals: [0, 7], group: .basic),
        Chord(name: "Major", suffix: "", intervals: [0, 4, 7], group: .major),
        Chord(name: "6", suffix: "6", intervals: [0, 4, 7, 9], group: .major),
        Chord(name: "maj7", suffix: "maj7", intervals: [0, 4, 7, 11], group: .major),
        Chord(name: "add9", suffix: "add9", intervals: [0, 4, 7, 14], group: .major),
        Chord(name: "maj9", suffix: "maj9", intervals: [0, 4, 7, 11, 14], group: .major),
        Chord(name: "Minor", suffix: "m", intervals: [0, 3, 7], group: .minor),
        Chord(name: "m6", suffix: "m6", intervals: [0, 3, 7, 9], group: .minor),
        Chord(name: "m7", suffix: "m7", intervals: [0, 3, 7, 10], group: .minor),
        Chord(name: "m9", suffix: "m9", intervals: [0, 3, 7, 10, 14], group: .minor),
        Chord(name: "7", suffix: "7", intervals: [0, 4, 7, 10], group: .dominant),
        Chord(name: "9", suffix: "9", intervals: [0, 4, 7, 10, 14], group: .dominant),
        Chord(name: "7♭9", suffix: "7♭9", intervals: [0, 4, 7, 10, 13], group: .dominant),
        Chord(name: "7♯9", suffix: "7♯9", intervals: [0, 4, 7, 10, 15], group: .dominant),
        // Altered dominant: 1, 3, ♭7, ♯9, ♭13 (the usual 5-note voicing; no 5th).
        Chord(name: "7alt", suffix: "7alt", intervals: [0, 4, 10, 15, 20], group: .dominant),
        Chord(name: "Sus2", suffix: "sus2", intervals: [0, 2, 7], group: .suspended),
        Chord(name: "Sus4", suffix: "sus4", intervals: [0, 5, 7], group: .suspended),
        Chord(name: "7sus4", suffix: "7sus4", intervals: [0, 5, 7, 10], group: .suspended),
        Chord(name: "Dim", suffix: "dim", intervals: [0, 3, 6], group: .diminished),
        Chord(name: "dim7", suffix: "dim7", intervals: [0, 3, 6, 9], group: .diminished),
        Chord(name: "m7♭5 (ø7)", suffix: "m7♭5", intervals: [0, 3, 6, 10], group: .diminished),
        Chord(name: "Aug", suffix: "aug", intervals: [0, 4, 8], group: .diminished),
    ]

    /// Notes for this chord on a root, clipped to the MIDI range.
    public func notes(root: Int) -> [Int] {
        intervals.map { root + $0 }.filter { (0...127).contains($0) }
    }

    /// Names a chord from its notes: first with the lowest note as the root, then as an inversion
    /// with a slash bass (e.g. "A7/C♯").
    public static func identify(_ notes: [Int]) -> String? {
        guard let bass = notes.min() else { return nil }
        if Set(notes.map { (($0 - bass) % 12 + 12) % 12 }) == [0] { return "\(NoteNames.name(bass)) oct" }
        if let name = match(notes, root: bass) { return name }
        for root in Set(notes.map { $0 % 12 }).sorted() where root != bass % 12 {
            if let name = match(notes, root: root) { return name + "/" + NoteNames.pitchClass(bass) }
        }
        return nil
    }

    private static func match(_ notes: [Int], root: Int) -> String? {
        let classes = Set(notes.map { (($0 - root) % 12 + 12) % 12 })
        for chord in quickPicks where chord.intervals.count > 1 && chord.name != "Octave" {
            if Set(chord.intervals.map { $0 % 12 }) == classes {
                return NoteNames.pitchClass(root) + chord.suffix
            }
        }
        return nil
    }
}
