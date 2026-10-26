import SwiftUI
import TwelveStepKit

/// The 64-slot setlist: what the 12 Step holds after a Send. Changes are saved immediately.
struct SetlistView: View {
    @Environment(AppModel.self) private var model
    @State private var picking: SlotPick?
    @State private var confirmingSend = false
    @State private var confirmingClear = false
    @State private var message: String?
    @State private var sending = false

    var body: some View {
        let store = model.presets
        NavigationStack {
            Group {
                if let contents = store.contents {
                    list(contents)
                } else {
                    ContentUnavailableView("Setlist unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(store.loadError ?? "Loading…"))
                }
            }
            .navigationTitle("Setlist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { picking = SlotPick(slot: nil) } label: { Label("Add preset", systemImage: "plus") }
                        Button { save { $0.autoPopulateSetlist() } } label: { Label("Fill from library", systemImage: "text.badge.plus") }
                        Button(role: .destructive) { confirmingClear = true } label: { Label("Clear setlist", systemImage: "trash") }
                    } label: {
                        Label("Setlist actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(store.contents == nil)
                }
            }
            .sheet(item: $picking) { pick in
                PresetPicker(title: pick.slot == nil ? "Add to setlist" : "Slot \(pick.slot! + 1)",
                             presets: store.contents?.orderedPresets ?? []) { name in
                    save { contents in
                        var entries = contents.setlist.entries
                        if let slot = pick.slot, entries.indices.contains(slot) { entries[slot] = name } else { entries.append(name) }
                        contents.setlist.setEntries(entries)
                    }
                }
            }
            .confirmationDialog("Replace the presets on your 12 Step?", isPresented: $confirmingSend, titleVisibility: .visible) {
                Button("Send \(store.contents?.resolvedSetlist().imageCount ?? 0) presets", role: .destructive) {
                    Task { sending = true; message = await model.sendSetlist(); sending = false }
                }
            } message: {
                Text("Every preset currently on the 12 Step is overwritten by this setlist. There's no undo on the device, but you can send again any time.")
            }
            .confirmationDialog("Clear the setlist?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Setlist", role: .destructive) { save { $0.clearSetlist() } }
            } message: {
                Text("Presets stay in the library. The 12 Step isn't changed until you send.")
            }
            .messageAlert("Setlist", message: $message)
        }
    }

    private func list(_ contents: PresetFolderContents) -> some View {
        let resolved = contents.resolvedSetlist()
        let entries = contents.setlist.entries
        let library = Dictionary(contents.orderedPresets.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        return List {
            Section {
                Button {
                    confirmingSend = true
                } label: {
                    HStack {
                        Label("Send to 12 Step", systemImage: "square.and.arrow.up.on.square")
                            .font(.headline)
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(entries.isEmpty || !model.canSend || sending)
            } footer: {
                Text(model.session.selectedDestination == nil
                     ? "Connect the 12 Step to send."
                     : "Replaces every preset on the 12 Step. If its display shows “PRST ERR SEND AGAN”, send again.")
            }

            if contents.setlist.hasGaps || !resolved.missingNames.isEmpty || !resolved.duplicateNames.isEmpty {
                Section("Needs attention") {
                    if contents.setlist.hasGaps {
                        Button {
                            save { $0.setlist.setEntries($0.setlist.entries) }
                        } label: {
                            Label("Empty slots in the middle stop later presets from being sent. Tap to close the gaps.", systemImage: "arrow.up.to.line")
                        }
                    }
                    ForEach(resolved.missingNames.sorted { $0.key < $1.key }, id: \.key) { slot, name in
                        Label("“\(name)” isn't in the library, so it won't be sent.", systemImage: "questionmark.folder")
                    }
                    ForEach(resolved.duplicateNames.sorted(), id: \.self) { name in
                        Label("Several presets are named “\(name)”; the last one is used.", systemImage: "doc.on.doc")
                    }
                }
                .foregroundStyle(.orange)
            }

            Section {
                ForEach(Self.rows(entries)) { row in
                    let index = row.index, name = row.name
                    Button {
                        picking = SlotPick(slot: index)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 26, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).foregroundStyle(library[name] == nil ? .orange : .primary)
                                if let preset = library[name] {
                                    Text(preset.voiceSummary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let preset = library[name] {
                                DisplayPreview(text: preset.displayName, font: .system(.caption, design: .monospaced).weight(.semibold))
                            }
                        }
                    }
                    .tint(.primary)
                }
                .onMove { from, to in
                    save { contents in
                        var entries = contents.setlist.entries
                        entries.move(fromOffsets: from, toOffset: to)
                        contents.setlist.setEntries(entries)
                    }
                }
                .onDelete { offsets in
                    save { contents in
                        var entries = contents.setlist.entries
                        entries.remove(atOffsets: offsets)
                        contents.setlist.setEntries(entries)
                    }
                }
                if entries.count < Setlist.slotCount {
                    Button { picking = SlotPick(slot: nil) } label: { Label("Add preset", systemImage: "plus") }
                }
            } header: {
                Text("\(entries.count) of \(Setlist.slotCount) slots")
            } footer: {
                Text("Tap a slot to change it. Swipe to remove, or tap Edit to reorder. The order here is the order on the 12 Step.")
            }
        }
    }

    /// Shows the change at once and writes the files in the background, so reordering is smooth.
    private func save(_ change: (inout PresetFolderContents) -> Void) {
        do {
            try model.presets.updateInBackground(change) { error in
                message = "Couldn't save the setlist: \(error.localizedDescription) The latest files have been reloaded."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Rows identified by preset name (and which repeat of that name), not by position, so a
    /// moved row keeps its identity and the list animates the move instead of redrawing every row.
    private struct Row: Identifiable {
        let id: String
        let index: Int
        let name: String
    }

    private static func rows(_ entries: [String]) -> [Row] {
        var seen: [String: Int] = [:]
        return entries.enumerated().map { index, name in
            let repeatNumber = seen[name, default: 0]
            seen[name] = repeatNumber + 1
            return Row(id: "\(name)#\(repeatNumber)", index: index, name: name)
        }
    }
}

private struct SlotPick: Identifiable {
    let slot: Int?
    var id: Int { slot ?? -1 }
}

private struct PresetPicker: View {
    let title: String
    let presets: [Preset]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(presets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.key) { preset in
                Button {
                    onPick(preset.name)
                    dismiss()
                } label: {
                    HStack {
                        Text(preset.name)
                        Spacer()
                        DisplayPreview(text: preset.displayName, font: .system(.caption, design: .monospaced).weight(.semibold))
                    }
                }
                .tint(.primary)
            }
            .searchable(text: $search, prompt: "Search presets")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
