// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

// MARK: - Overview: the 12 Step's 13 keys in their physical layout

/// 8 lower keys (C D E F G A B C) with 5 raised keys between them, like the hardware.
struct KeyboardOverview: View {
    let preset: Preset
    let onSelect: (Int) -> Void

    private static let lowerKeys = [1, 3, 5, 6, 8, 10, 12, 13]
    /// Raised keys and the lower-key boundary (0-based) they sit over.
    private static let raisedKeys: [(key: Int, boundary: CGFloat)] = [(2, 1), (4, 2), (7, 4), (9, 5), (11, 6)]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.lowerKeys.enumerated()), id: \.element) { index, key in
                    keyButton(key, raised: false)
                        .frame(width: width - 4, height: 84)
                        .offset(x: CGFloat(index) * width + 2, y: 70)
                }
                ForEach(Self.raisedKeys, id: \.key) { raised in
                    keyButton(raised.key, raised: true)
                        .frame(width: width - 4, height: 64)
                        .offset(x: raised.boundary * width - width / 2 + 2, y: 0)
                }
            }
        }
        .frame(height: 156)
        // A fixed-size picture of the hardware: cap its text so labels stay inside the keys.
        // VoiceOver still reads each key's full notes.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }

    private func keyButton(_ key: Int, raised: Bool) -> some View {
        let notes = preset.notes(forKey: key)
        return Button { onSelect(key) } label: {
            VStack(spacing: 2) {
                Text("\(key)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(notes.isEmpty ? "—" : NoteNames.label(for: notes))
                    .font(.caption.weight(.medium))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if notes.count > 1 {
                    Text("\(notes.count) notes").font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(raised ? Color(.systemGray4) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Key \(key): \(notes.isEmpty ? "no notes" : notes.map(NoteNames.name).joined(separator: ", "))")
    }
}

struct TransposeButtons: View {
    let transpose: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button("−12") { transpose(-12) }.accessibilityLabel("Down an octave")
            Button("−1") { transpose(-1) }.accessibilityLabel("Down a semitone")
            Button("+1") { transpose(1) }.accessibilityLabel("Up a semitone")
            Button("+12") { transpose(12) }.accessibilityLabel("Up an octave")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.callout.monospacedDigit())
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - One key

/// Chooses up to 5 notes for one key: chips, a compact piano and chord quick picks.
struct KeyEditorSheet: View {
    @Binding var preset: Preset
    let key: Int
    @Environment(\.dismiss) private var dismiss
    @State private var octave = 2
    @State private var originalNotes: [Int]?

    private var notes: [Int] { preset.notes(forKey: key) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if notes.isEmpty {
                            Text("No notes — this key is silent.").foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(notes.sorted(), id: \.self) { note in
                                    Button {
                                        setNotes(notes.filter { $0 != note })
                                    } label: {
                                        Label(NoteNames.name(note), systemImage: "xmark.circle.fill")
                                            .labelStyle(ChipLabelStyle())
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Remove \(NoteNames.name(note))")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Notes (\(notes.count) of \(Preset.notesPerKey))")
                } footer: {
                    if let chord = notes.count > 1 ? Chord.identify(notes) : nil {
                        Text("Plays \(chord).")
                    }
                }

                Section {
                    HStack {
                        Button { octave = max(NoteNames.octaveRange.lowerBound, octave - 1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Lower octave")
                        Spacer()
                        Text("C\(octave) – B\(octave + 1)").font(.subheadline.monospacedDigit())
                        Spacer()
                        Button { octave = min(NoteNames.octaveRange.upperBound - 1, octave + 1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Higher octave")
                    }
                    .buttonStyle(.borderless)
                    MiniPiano(firstNote: NoteNames.c(inOctave: octave), octaves: 2, selected: Set(notes),
                              highlight: NoteNames.naturalNote(forKey: key)) { toggle($0) }
                        .frame(height: 110)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Tap notes to add or remove")
                } footer: {
                    if notes.count >= Preset.notesPerKey {
                        Text("A key holds at most 5 notes. Remove one to add another.")
                    }
                }

                Section {
                    ForEach(Chord.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                                ForEach(Chord.quickPicks.filter { $0.group == group }) { chord in
                                    ChordButton(chord: chord, isCurrent: isCurrent(chord)) { setNotes(chord.notes(root: root)) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Chord on \(NoteNames.name(root))")
                } footer: {
                    Text("Builds on the key's lowest note (or its natural pitch when empty) and replaces the current notes.")
                }

                Section {
                    HStack {
                        Text("Transpose")
                        Spacer()
                        TransposeButtons { preset.transposeKey(key, by: $0) }
                    }
                    Button { KeyClipboard.notes = notes } label: { Label("Copy key", systemImage: "doc.on.doc") }
                    if let copied = KeyClipboard.notes {
                        Button { setNotes(copied) } label: { Label("Paste key (\(NoteNames.label(for: copied)))", systemImage: "doc.on.clipboard") }
                    }
                    Button(role: .destructive) { setNotes([]) } label: { Label("Clear key", systemImage: "xmark.circle") }
                }
            }
            .navigationTitle("Key \(key)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Puts the key back as it was when the editor opened.
                    Button("Cancel") {
                        if let originalNotes { setNotes(originalNotes) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if originalNotes == nil { originalNotes = notes }
                octave = max(NoteNames.octaveRange.lowerBound, min(NoteNames.octaveRange.upperBound - 1,
                                  NoteNames.octave(of: notes.min() ?? NoteNames.naturalNote(forKey: key))))
            }
        }
        .presentationDetents([.large])
        // Swiping down would keep the changes silently; make the choice explicit once something changed.
        .interactiveDismissDisabled(originalNotes != nil && notes != originalNotes)
    }

    private var root: Int { notes.min() ?? NoteNames.naturalNote(forKey: key) }

    /// True when the key's notes are exactly this chord on its root.
    private func isCurrent(_ chord: Chord) -> Bool {
        notes.sorted() == chord.notes(root: root)
    }

    private func setNotes(_ newNotes: [Int]) {
        preset.setNotes(newNotes, forKey: key)
    }

    private func toggle(_ note: Int) {
        if notes.contains(note) {
            setNotes(notes.filter { $0 != note })
        } else if notes.count < Preset.notesPerKey {
            setNotes((notes + [note]).sorted())
        }
    }
}

private struct ChordButton: View {
    let chord: Chord
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        let label = Text(chord.name).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
        Group {
            if isCurrent {
                Button(action: action) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }.buttonStyle(.bordered)
            }
        }
        .font(.callout)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Copy/Paste Key across keys and presets.
@MainActor
enum KeyClipboard {
    static var notes: [Int]?
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title.font(.body.monospacedDigit())
            configuration.icon.font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mini piano

/// A compact piano of whole octaves. Selected notes are filled with the accent colour.
struct MiniPiano: View {
    let firstNote: Int
    let octaves: Int
    let selected: Set<Int>
    var highlight: Int? = nil
    let onTap: (Int) -> Void

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// Black key offsets and the white-key boundary they sit on.
    private static let blackOffsets: [(offset: Int, boundary: CGFloat)] = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)]

    var body: some View {
        GeometryReader { geometry in
            let whiteCount = 7 * octaves
            let whiteWidth = geometry.size.width / CGFloat(whiteCount)
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<whiteCount, id: \.self) { index in
                    let note = firstNote + 12 * (index / 7) + Self.whiteOffsets[index % 7]
                    key(note, black: false)
                        .frame(width: whiteWidth - 1, height: height)
                        .offset(x: CGFloat(index) * whiteWidth)
                }
                ForEach(0..<octaves, id: \.self) { octave in
                    ForEach(Self.blackOffsets, id: \.offset) { black in
                        let note = firstNote + 12 * octave + black.offset
                        key(note, black: true)
                            .frame(width: whiteWidth * 0.62, height: height * 0.6)
                            .offset(x: (CGFloat(7 * octave) + black.boundary) * whiteWidth - whiteWidth * 0.31)
                    }
                }
            }
        }
    }

    private func key(_ note: Int, black: Bool) -> some View {
        let isSelected = selected.contains(note)
        let valid = (0...127).contains(note)
        return Button { if valid { onTap(note) } } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : (black ? Color.primary : Color(.systemBackground)))
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator))
                if !black && note % 12 == 0 {
                    Text(NoteNames.name(note)).font(.caption2).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(isSelected ? .white : .secondary).padding(.bottom, 3)
                }
                if note == highlight && !isSelected {
                    Circle().fill(Color.accentColor.opacity(0.5)).frame(width: 6, height: 6).padding(.bottom, black ? 4 : 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!valid)
        .accessibilityLabel(NoteNames.name(note))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Fill all keys

struct FillKeysSheet: View {
    @Environment(AppModel.self) private var model
    @Binding var preset: Preset
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = KeyPattern()
    @State private var customText = "+7"

    private var previewPreset: Preset {
        var copy = preset
        copy.apply(pattern)
        return copy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $pattern.octave, in: NoteNames.octaveRange.lowerBound...(NoteNames.octaveRange.upperBound - 1)) {
                        LabeledContent("Key 1 plays", value: "C\(pattern.octave)")
                    }
                } footer: {
                    Text("The keys always run C to C, like the 12 Step itself: key 1 is C\(pattern.octave), key 13 is C\(pattern.octave + 1).")
                }
                Section {
                    Picker("Layout", selection: $pattern.layout) {
                        ForEach(KeyPattern.Layout.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if pattern.layout != .chromatic {
                        Picker("Key", selection: $pattern.tonic) {
                            ForEach(0..<12, id: \.self) { Text(NoteNames.pitchClass($0)).tag($0) }
                        }
                    }
                    Picker("Each key plays", selection: $pattern.voicing) {
                        ForEach(KeyPattern.Voicing.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if pattern.voicing == .custom {
                        LabeledContent("Intervals") {
                            TextField("+7 +12", text: $customText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .onChange(of: customText) { _, text in pattern.customIntervals = KeyPattern.parseIntervals(text) }
                        }
                    }
                } footer: {
                    Text(pattern.layout == .chromatic
                         ? "Every key plays its own semitone, like the factory presets."
                         : "Keys on notes of \(NoteNames.pitchClass(pattern.tonic)) \(pattern.layout.rawValue.lowercased()) play that note, or the triad or 7th chord the scale builds on it.")
                }
                if pattern.layout != .chromatic {
                    Section {
                        Picker("Keys outside the scale", selection: $pattern.outOfScale) {
                            ForEach(KeyPattern.OutOfScale.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } footer: {
                        let outside = (0..<Preset.keyCount).filter { pattern.isOutOfScale(keyIndex: $0) }.map { String($0 + 1) }
                        Text("\(pattern.outOfScale.explanation) Here that's keys \(outside.joined(separator: ", ")).")
                    }
                }
                Section("Preview") {
                    KeyboardOverview(preset: previewPreset) { _ in }
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
            }
            .navigationTitle("Fill all keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { preset.apply(pattern); dismiss() }
                }
            }
            .onAppear {
                // Start from the octave key 1 currently plays in.
                if let first = preset.notes(forKey: 1).min() { pattern.octave = max(NoteNames.octaveRange.lowerBound, min(NoteNames.octaveRange.upperBound - 1, NoteNames.octave(of: first))) }
                #if DEBUG
                let options = model.launchRoute.fillOptions
                if let layout = KeyPattern.Layout.allCases.first(where: { "\($0)" == options["-fillLayout"] }) { pattern.layout = layout }
                if let voicing = KeyPattern.Voicing.allCases.first(where: { "\($0)" == options["-fillVoicing"] }) { pattern.voicing = voicing }
                if let outside = KeyPattern.OutOfScale.allCases.first(where: { "\($0)" == options["-fillOutside"] }) { pattern.outOfScale = outside }
                if let key = options["-fillKey"].flatMap(Int.init), (0..<12).contains(key) { pattern.tonic = key }
                #endif
            }
        }
    }
}

