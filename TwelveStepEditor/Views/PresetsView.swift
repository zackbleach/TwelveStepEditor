// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit
import UniformTypeIdentifiers

/// The preset library: the desktop's preset menu plus Save As, Delete, Import and Export.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var importing = false
    @State private var settingUpSync = false
    @State private var namingNewPreset = false
    @State private var newName = ""
    @State private var message: String?
    @State private var deleting: Preset?
    @State private var path: [String] = []

    var body: some View {
        let store = model.presets
        NavigationStack(path: $path) {
            Group {
                if let contents = store.contents {
                    let inSetlist = Set(contents.setlist.entries)
                    let presets = contents.listedPresets.filter {
                        search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                    }
                    List {
                        if store.source == .onDevice && search.isEmpty {
                            MacSyncCard { settingUpSync = true }
                        }
                        ForEach(presets, id: \.key) { preset in
                            NavigationLink(value: preset.key) {
                                PresetRow(preset: preset, inSetlist: inSetlist.contains(preset.name))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleting = preset } label: { Label("Delete", systemImage: "trash") }
                                Button { duplicate(preset) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    .tint(.indigo)
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search presets")
                    .overlay {
                        if presets.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                } else {
                    ContentUnavailableView("Presets unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(store.loadError ?? "Loading…"))
                }
            }
            .navigationTitle("Presets")
            .navigationDestination(for: String.self) { PresetEditorView(presetKey: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { VersionBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { newName = ""; namingNewPreset = true } label: { Label("New preset", systemImage: "plus") }
                        Button { importing = true } label: { Label("Import preset…", systemImage: "square.and.arrow.down") }
                        if let copied = PresetClipboard.shared.values {
                            Button { add { $0.appendPreset(values: copied, name: copied["preset_name"]?.stringValue ?? "Pasted") } } label: {
                                Label("Paste as new preset", systemImage: "doc.on.clipboard")
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(store.contents == nil)
                }
            }
            .refreshable { store.reload() }
            .onAppear {
                #if DEBUG
                // -syncWizard: open the Mac sync wizard (for screenshots).
                if ProcessInfo.processInfo.arguments.contains("-syncWizard") { settingUpSync = true }
                if ProcessInfo.processInfo.arguments.contains("-newPreset") { namingNewPreset = true }
                #endif
                if let key = model.launchRoute.presetKey, path.isEmpty {
                    path = [key]
                    model.launchRoute.presetKey = nil
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.twelveStepPreset, .json], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .sheet(isPresented: $settingUpSync) { SyncWizard() }
            .alert("New Preset", isPresented: $namingNewPreset) {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    add { $0.newPreset(name: $0.uniqueName(for: name.isEmpty ? "New Preset" : name)) }
                }
            } message: {
                Text("The 4 letters shown on the 12 Step's display are filled in from this name. You can change either later.")
            }
            .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let key = deleting?.key { save { $0.deletePreset(key: key) } }
                }
            } message: {
                Text("Setlist slots using this preset become empty.")
            }
            .messageAlert("Presets", message: $message)
        }
    }

    private func save(_ change: (inout PresetFolderContents) -> Void) {
        do { try model.presets.update(change) } catch { message = error.localizedDescription }
    }

    private func add(_ create: (inout PresetFolderContents) -> String) {
        var key: String?
        save { key = create(&$0) }
        if let key { path.append(key) }
    }

    private func duplicate(_ preset: Preset) {
        save { _ = $0.duplicatePreset(key: preset.key) }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var imported = 0
        save { contents in
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), (try? contents.importPreset(data: data)) != nil { imported += 1 }
            }
        }
        message = "Imported \(imported) of \(urls.count) preset\(urls.count == 1 ? "" : "s")."
    }
}

private struct PresetRow: View {
    let preset: Preset
    let inSetlist: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility text sizes the name gets the full width, with the display below it.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name)
                    if inSetlist {
                        Image(systemName: "music.note.list").font(.caption).foregroundStyle(.tint)
                            .accessibilityLabel("In setlist")
                    }
                }
                Text(preset.voiceSummary).font(.caption).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            DisplayPreview(text: preset.displayName, font: .system(.caption, design: .monospaced).weight(.semibold))
        }
    }
}

/// In-app clipboard for whole-preset Copy / Paste (the desktop's Edit menu).
@MainActor
final class PresetClipboard {
    static let shared = PresetClipboard()
    var values: [String: JSONValue]?
}

extension UTType {
    /// `.twelvesteppreset` files (JSON). A dynamic type, so no Info.plist declaration is needed.
    static let twelveStepPreset = UTType(filenameExtension: "twelvesteppreset", conformingTo: .data) ?? .data
}
