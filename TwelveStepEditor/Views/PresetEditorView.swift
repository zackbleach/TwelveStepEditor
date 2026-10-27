// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

/// Edits one preset on a draft. Save writes `12Step.json` (and the setlist, if a rename affects it).
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let presetKey: String

    @State private var draft: Preset?
    @State private var original: Preset?
    @State private var editingKey: KeySelection?
    @State private var fillingKeys = false
    @State private var confirmingDiscard = false
    @State private var confirmingReset = false
    @State private var message: String?
    @State private var sending = false

    private var isDirty: Bool { draft != original }

    var body: some View {
        Group {
            if let binding = Binding($draft) {
                form(binding)
            } else {
                ContentUnavailableView("Preset not found", systemImage: "questionmark.folder",
                                       description: Text("It may have been removed by a sync."))
            }
        }
        .navigationTitle(draft?.name ?? "Preset")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar { toolbar }
        .onAppear(perform: load)
        .onChange(of: model.presets.contents?.library[key: presetKey]) { _, latest in
            // Follow external changes (e.g. a sync) while there are no local edits.
            if !isDirty, let latest { draft = latest; original = latest }
        }
        .sheet(item: $editingKey) { selection in
            if let binding = Binding($draft) {
                KeyEditorSheet(preset: binding, key: selection.key)
            }
        }
        .sheet(isPresented: $fillingKeys) {
            if let binding = Binding($draft) {
                FillKeysSheet(preset: binding)
            }
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { draft = original; dismiss() }
        }
        .confirmationDialog("Reset this preset to blank?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset to Blank", role: .destructive) { resetToBlank() }
        } message: {
            Text("Keys, voices, modlines and modes go back to the blank preset. The name is kept. Nothing is saved until you tap Save.")
        }
        .messageAlert(draft?.name ?? "Preset", message: $message)
    }

    // MARK: Form

    private func form(_ preset: Binding<Preset>) -> some View {
        let inSetlist = model.presets.contents?.setlist.entries.contains(original?.name ?? "") ?? false
        return Form {
            Section {
                LabeledContent("Name") {
                    TextField("Preset name", text: preset.nameValue)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
                DisplayNameEditor(characters: preset.displayCharacters)
            } footer: {
                Text("Tap the name or the display letters to change them. The 4 letters appear on the 12 Step's display when the preset is selected.")
            }

            Section {
                KeyboardOverview(preset: preset.wrappedValue) { editingKey = KeySelection(key: $0) }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                HStack {
                    Text("Transpose all")
                    Spacer()
                    TransposeButtons { preset.wrappedValue.transposeAllKeys(by: $0) }
                }
                Button { fillingKeys = true } label: { Label("Fill all keys…", systemImage: "wand.and.stars") }
                Button(role: .destructive) { preset.wrappedValue.clearAllKeys() } label: {
                    Label("Clear all keys", systemImage: "xmark.circle")
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("Tap a key to choose its notes or chord (up to 5 notes).")
            }

            VoiceSection(title: "Voice A", voice: .a, preset: preset)
            VoiceSection(title: "Voice B", voice: .b, preset: preset)

            Section("Behaviour") {
                HStack {
                    HelpTitle("Note mode", Help.noteMode)
                    Spacer(minLength: 8)
                    Picker("Note mode", selection: preset.noteMode) {
                        ForEach(Preset.NoteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                HStack {
                    HelpTitle("Key mode", Help.keyMode)
                    Spacer(minLength: 8)
                    Picker("Key mode", selection: preset.keyMode) {
                        ForEach(Preset.KeyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            ModlinesSection(preset: preset)

            CVSection(preset: preset)

            if inSetlist {
                Section {
                    Button {
                        Task { await saveAndSend() }
                    } label: {
                        HStack {
                            Label(isDirty ? "Save and send setlist to 12 Step" : "Send setlist to 12 Step",
                                  systemImage: "square.and.arrow.up.on.square")
                            if sending { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!model.canSend || sending)
                } footer: {
                    Text(model.session.selectedDestination == nil
                         ? "Connect the 12 Step to send. This preset is in the setlist."
                         : "Replaces every preset on the 12 Step with the setlist, like the desktop editor's Send.")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isDirty {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { confirmingDiscard = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if save() { dismiss() } }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { PresetClipboard.shared.values = draft?.values } label: { Label("Copy settings", systemImage: "doc.on.doc") }
                    if PresetClipboard.shared.values != nil {
                        Button { paste() } label: { Label("Paste settings", systemImage: "doc.on.clipboard") }
                    }
                    Button(role: .destructive) { confirmingReset = true } label: { Label("Reset to blank", systemImage: "eraser") }
                    if let file = exportFile() {
                        ShareLink(item: file) { Label("Export preset…", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard draft == nil, let preset = model.presets.contents?.library[key: presetKey] else { return }
        draft = preset
        original = preset
        if let key = model.launchRoute.key { editingKey = KeySelection(key: key); model.launchRoute.key = nil }
        if model.launchRoute.fill { fillingKeys = true; model.launchRoute.fill = false }
    }

    @discardableResult
    private func save() -> Bool {
        guard let draft, let original else { return false }
        do {
            try model.presets.update { contents in
                var edited = draft
                edited.nameValue = original.name
                contents.library[key: presetKey] = edited
                // Renaming also updates setlist slots that use the old name.
                contents.renamePreset(key: presetKey, to: draft.name)
            }
            let saved = model.presets.contents?.library[key: presetKey]
            self.draft = saved
            self.original = saved
            return true
        } catch {
            message = error.localizedDescription
            if case PresetFolderError.changedOnDisk = error {
                message = (message ?? "") + " Your edits are still on screen; tap Save again to apply them on top of the latest version."
                self.original = model.presets.contents?.library[key: presetKey]
            }
            return false
        }
    }

    private func saveAndSend() async {
        if isDirty, !save() { return }
        sending = true
        message = await model.sendSetlist()
        sending = false
    }

    private func duplicate() {
        do {
            try model.presets.update { _ = $0.duplicatePreset(key: presetKey) }
            message = "Saved a copy at the end of the preset list."
        } catch {
            message = error.localizedDescription
        }
    }

    private func paste() {
        guard let values = PresetClipboard.shared.values, var preset = draft else { return }
        let name = preset.name
        preset.values = values
        preset.nameValue = name
        draft = preset
    }

    private func resetToBlank() {
        guard var preset = draft, let blank = model.presets.contents?.blankPreset else { return }
        let name = preset.name
        let display = preset.displayCharacters
        preset.values = blank.values
        preset.nameValue = name
        preset.displayCharacters = display
        draft = preset
    }

    private func exportFile() -> URL? {
        guard let data = model.presets.contents?.exportPreset(key: presetKey), let name = original?.name else { return nil }
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).twelvesteppreset")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

struct KeySelection: Identifiable {
    let key: Int
    var id: Int { key }
}

// MARK: - Display name

private struct DisplayNameEditor: View {
    @Binding var characters: [Character]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                HStack { characterMenus }
            }
        } else {
            HStack {
                Text("Display")
                Spacer()
                characterMenus
            }
        }
    }

    @ViewBuilder private var characterMenus: some View {
        ForEach(0..<4, id: \.self) { index in
            Menu {
                Picker("Character \(index + 1)", selection: binding(index)) {
                    ForEach(Preset.displayCharacterSet, id: \.self) { character in
                        Text(character == " " ? "Space" : String(character)).tag(character)
                    }
                }
            } label: {
                DisplayPreview(text: String(characters.indices.contains(index) ? characters[index] : " "))
            }
            .accessibilityLabel("Display character \(index + 1)")
        }
    }

    private func binding(_ index: Int) -> Binding<Character> {
        Binding(
            get: { characters.indices.contains(index) ? characters[index] : " " },
            set: { newValue in
                var updated = characters
                while updated.count < 4 { updated.append(" ") }
                updated[index] = newValue
                characters = updated
            })
    }
}

// MARK: - Voices

private struct VoiceSection: View {
    let title: String
    let voice: Preset.Voice
    @Binding var preset: Preset

    var body: some View {
        let settings = Binding(get: { preset.voice(voice) }, set: { preset.setVoice($0, voice: voice) })
        Section {
            if voice == .a {
                Stepper(value: settings.channel, in: 1...16) {
                    LabeledContent { Text("\(settings.wrappedValue.channel)") } label: { HelpTitle("MIDI channel", Help.channelA) }
                }
            } else {
                OffStepper(title: "MIDI channel", value: settings.channel, range: 0...16, offValue: 0, help: Help.channelB)
            }
            if voice == .a || settings.wrappedValue.channel != 0 {
                OffStepper(title: "Program change", value: settings.programChange, range: -1...127, offValue: -1, help: Help.programChange)
                OffStepper(title: "Bank MSB", value: settings.bankMSB, range: -1...127, offValue: -1, help: Help.bankMSB)
                OffStepper(title: "Bank LSB", value: settings.bankLSB, range: -1...127, offValue: -1, help: Help.bankLSB)
                Stepper(value: settings.transpose, in: -12...12) {
                    LabeledContent {
                        Text(settings.wrappedValue.transpose > 0 ? "+\(settings.wrappedValue.transpose)" : "\(settings.wrappedValue.transpose)")
                    } label: { HelpTitle("Transpose", Help.transpose) }
                }
            }
        } header: {
            Text(title)
        }
    }
}

// MARK: - Modlines

private struct ModlinesSection: View {
    @Binding var preset: Preset

    var body: some View {
        let extras = (2...Preset.sentModlineCount).filter { preset.modline($0).destination != "Off" }
        Section {
            ModlineRow(number: 1, preset: $preset)
            ForEach(extras, id: \.self) { number in
                ModlineRow(number: number, preset: $preset)
            }
            if extras.count < Preset.sentModlineCount - 1 {
                Menu {
                    ForEach(availableDestinations(excluding: nil), id: \.self) { destination in
                        Button(destination) { add(destination) }
                    }
                } label: {
                    Label("Add expression", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Expression (modlines)")
        } footer: {
            if preset.hasUnsentModlineSix {
                Text("This preset also has a 6th modline. The 12 Step Editor never sends it to the device, so it isn't shown here.")
            }
        }
    }

    /// Bend, Channel Pressure and Poly Aftertouch can each be used once; CC up to twice.
    private func availableDestinations(excluding number: Int?) -> [String] {
        let used = (2...Preset.sentModlineCount).filter { $0 != number }.map { preset.modline($0).destination }
        return Modline.destinations.dropFirst().filter { destination in
            destination == "CC" ? used.filter { $0 == "CC" }.count < 2 : !used.contains(destination)
        }
    }

    private func add(_ destination: String) {
        guard let number = (2...Preset.sentModlineCount).first(where: { preset.modline($0).destination == "Off" }) else { return }
        var modline = Modline.off
        modline.destination = destination
        // The desktop's defaults when a destination is chosen.
        modline.sourceA = destination == "Bend" ? "Tilt" : "Pressure"
        if destination == "CC" { modline.ccNumber = 1 }
        preset.setModline(modline, number)
    }
}

private struct ModlineRow: View {
    let number: Int
    @Binding var preset: Preset
    @State private var expanded = false

    var body: some View {
        let modline = Binding(get: { preset.modline(number) }, set: { preset.setModline($0, number) })
        let voiceBOn = preset.voice(.b).channel != 0
        DisclosureGroup(isExpanded: $expanded) {
            if number > 1 {
                OptionPicker(title: "Destination", selection: modline.destination, options: Modline.destinations, help: Help.destination)
                if modline.wrappedValue.destination == "CC" {
                    Stepper(value: modline.ccNumber, in: 0...127) {
                        LabeledContent { Text("\(modline.wrappedValue.ccNumber)") } label: { HelpTitle("CC number", Help.ccNumber) }
                    }
                }
            }
            OptionPicker(title: "Source A (voice A)", selection: modline.sourceA, options: Modline.sources, help: Help.source)
            if voiceBOn {
                OptionPicker(title: "Source B (voice B)", selection: modline.sourceB, options: Modline.sources, help: Help.source)
            }
            OptionPicker(title: "Curve", selection: modline.curve, options: Modline.curves, help: Help.curve)
            LabeledContent {
                TextField("Gain", value: modline.gain, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 90)
            } label: { HelpTitle("Gain", Help.gain) }
            Stepper(value: modline.offset, in: -999...999) {
                LabeledContent { Text("\(modline.wrappedValue.offset)") } label: { HelpTitle("Offset", Help.offset) }
            }
            Stepper(value: modline.min, in: 0...127) {
                LabeledContent { Text("\(modline.wrappedValue.min)") } label: { HelpTitle("Min", Help.minMax) }
            }
            Stepper(value: modline.max, in: 0...127) {
                LabeledContent { Text("\(modline.wrappedValue.max)") } label: { HelpTitle("Max", Help.minMax) }
            }
            if number > 1 {
                Button("Remove", role: .destructive) { preset.setModline(.off, number) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(number == 1 ? "Note velocity" : title(modline.wrappedValue))
                Text(summary(modline.wrappedValue, voiceBOn: voiceBOn)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ modline: Modline) -> String {
        modline.destination == "CC" ? "CC \(modline.ccNumber)" : modline.destination
    }

    private func summary(_ modline: Modline, voiceBOn: Bool) -> String {
        var parts = ["A: \(modline.sourceA)"]
        if voiceBOn { parts.append("B: \(modline.sourceB)") }
        parts.append(modline.curve)
        return parts.joined(separator: " · ")
    }
}

// MARK: - CV

private struct CVSection: View {
    @Binding var preset: Preset
    /// Collapsed by default; tap to show the CV output settings.
    @State private var showing = false

    var body: some View {
        Section {
            DisclosureGroup("CV outputs (12 Step2)", isExpanded: $showing) {
                ForEach(Preset.CVOutput.allCases, id: \.self) { output in
                    Text("CV Out \(output.rawValue)").font(.subheadline.weight(.semibold))
                    OptionPicker(title: "Control surface",
                                 selection: Binding(get: { preset.cvLocalMode(output) }, set: { preset.setCVLocalMode($0, output) }),
                                 options: Preset.cvLocalModes, help: Help.cvLocal)
                    OptionPicker(title: "USB",
                                 selection: Binding(get: { preset.cvUSBMode(output) }, set: { preset.setCVUSBMode($0, output) }),
                                 options: Preset.cvUSBModes, help: Help.cvUSB)
                    OptionPicker(title: "USB channel",
                                 selection: Binding(get: { preset.cvUSBChannel(output) }, set: { preset.setCVUSBChannel($0, output) }),
                                 options: Preset.cvUSBChannels, help: Help.cvUSBChannel)
                }
            }
        }
    }
}

// MARK: - Help text (from the 12 Step Editor manual v3.0.1 and the desktop editor's tooltips)

private enum Help {
    static let channelA = "The MIDI channel voice A sends on."
    static let channelB = "Voice B plays the same keys on a second MIDI channel, with its own transpose, program change and modline sources, for example to layer two synths. Off turns it off."
    static let programChange = "Sent whenever this preset is loaded, to switch your synth to a matching sound. Off sends nothing."
    static let bankMSB = "A Bank Select (CC 0) sent whenever this preset is loaded. Off sends nothing."
    static let bankLSB = "A Bank Select (CC 32) sent whenever this preset is loaded. Off sends nothing."
    static let transpose = "Shifts every note this voice plays by up to 12 semitones. 3 moves everything up a minor third."
    static let noteMode = """
        Normal: notes play while a key is pressed.
        Legato: notes keep playing after you let go, until another key is pressed.
        Toggle: press a key to start its notes and again to stop them.
        Hold: switch between Normal and Legato with the Select key.
        """
    static let keyMode = "Mono: one key at a time. Poly: several keys at once."
    static let destination = "The MIDI message this modline sends: CC, pitch bend, channel pressure or poly aftertouch. Each can be used once per preset, except CC, which can be used twice."
    static let ccNumber = "The Control Change number to send, such as 1 for the mod wheel or 11 for expression."
    static let source = """
        What drives the modline:
        Velocity: how hard a key is hit.
        Pressure: how hard a key is held; drops to 0 on release.
        Tilt: pressure towards the top of the key versus the bottom; returns to 63 on release.
        KeyNum: which key is played, numbered left to right.
        Pedal: the expression pedal.
        Inverted versions run the other way.
        """
    static let curve = "The response curve applied to the source: Linear, Sine, Cosine, Exponential, Logarithmic, or DeadZone (linear with a flat spot in the middle)."
    static let gain = "Multiplies the source value. 1 leaves it unchanged; a negative number inverts it."
    static let offset = "Adds to the source value after the gain. Use a negative number to subtract."
    static let minMax = "Values below Min or above Max are clipped to them, not ignored. Setting both to 60 always sends 60."
    static let cvLocal = """
        What the 12 Step2's keys do to this CV out (only a key's first note counts):
        Gate: 5 V while a key is pressed.
        Pitch: 1 V/octave for the last key pressed.
        Pressure or Tilt: 0–5 V from the active key.
        Pedal: 0–5 V from the expression pedal.
        Disabled: the keys don't control it.
        """
    static let cvUSB = """
        What USB MIDI sent to the 12 Step2's CV Out port does to this CV out:
        Gate: 5 V while any note is on.
        Pitch: 1 V/octave for the last note.
        Velocity: 0–5 V from the last note's velocity.
        Bend / Mod: 0–5 V from pitch bend or the mod wheel (CC 1).
        If both the keys and USB control a CV out, the most recent wins.
        """
    static let cvUSBChannel = "The USB MIDI channel this CV out listens on (1 or 2)."
}
