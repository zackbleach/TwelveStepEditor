import SwiftUI
import TwelveStepKit

/// Global settings (the desktop's Settings tab) and where the preset files live.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: GlobalSettings?
    @State private var choosingFolder = false
    @State private var settingUpSync = false
    @AppStorage("macSyncCardDismissed") private var syncCardDismissed = false
    @State private var confirmingRestore = false
    @State private var message: String?
    @State private var sending = false

    private var saved: GlobalSettings? { model.presets.contents?.settings }
    private var isDirty: Bool { draft != nil && draft != saved }

    var body: some View {
        NavigationStack {
            Form {
                filesSection
                if let binding = Binding($draft) {
                    deviceSections(binding)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                if isDirty {
                    ToolbarItem(placement: .cancellationAction) { Button("Revert") { draft = saved } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                }
            }
            .onAppear { if draft == nil { draft = saved } }
            .onChange(of: saved) { _, latest in if !isDirty { draft = latest } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let folder) = result { model.presets.useFolder(folder); draft = model.presets.contents?.settings }
            }
            .sheet(isPresented: $settingUpSync, onDismiss: { draft = model.presets.contents?.settings }) { SyncWizard() }
            .confirmationDialog("Restore the factory presets?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("Restore Factory Presets", role: .destructive) {
                    do { try model.presets.restoreFactoryPresets(); draft = model.presets.contents?.settings }
                    catch { message = error.localizedDescription }
                }
            } message: {
                Text("Replaces the presets, setlist and settings stored on this \(deviceName) with the 12 Step Editor's factory set.")
            }
            .messageAlert("Settings", message: $message)
        }
    }

    // MARK: Preset files

    private var filesSection: some View {
        let store = model.presets
        return Section {
            LabeledContent("Using", value: store.source == .onDevice ? "On this \(deviceName)" : store.source.title)
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Button("Choose folder…") { choosingFolder = true }
            if store.source == .onDevice {
                Button("Sync with Your Mac…") { settingUpSync = true }
            }
            if store.source == .onDevice {
                Button("Restore factory presets…", role: .destructive) { confirmingRestore = true }
            } else {
                Button("Use presets on this \(deviceName) instead") {
                    store.useOnDeviceFolder()
                    draft = store.contents?.settings
                    syncCardDismissed = false // offer Mac sync again on the Presets tab
                }
            }
            Button("Reload") { store.reload() }
        } header: {
            Text("Preset files")
        } footer: {
            Text(store.source == .onDevice
                 ? "Presets are stored on this \(deviceName) (Files › On My \(deviceName) › 12 Step). To share them with the desktop 12 Step Editor, use Sync with Your Mac (free)."
                 : "Shared with the desktop 12 Step Editor. Quit the desktop editor while editing here, or it may overwrite your changes.")
        }
    }

    // MARK: Device settings

    @ViewBuilder
    private func deviceSections(_ settings: Binding<GlobalSettings>) -> some View {
        Section {
            SliderRow(title: "Global key sensitivity", value: settings.keySensitivitySlider, range: 1...500,
                      label: { "\(Double($0) / 5, specifier: "%g")%" }, reset: 100)
            SliderRow(title: "On threshold", value: Binding(get: { settings.wrappedValue.onThreshold }, set: { value in
                settings.wrappedValue.onThreshold = value
                if settings.wrappedValue.offThreshold >= value { settings.wrappedValue.offThreshold = max(10, value - 1) }
            }), range: 15...64, label: { "\($0)" }, reset: nil)
            SliderRow(title: "Off threshold", value: Binding(get: { settings.wrappedValue.offThreshold }, set: { value in
                settings.wrappedValue.offThreshold = value
                if value >= settings.wrappedValue.onThreshold { settings.wrappedValue.onThreshold = min(64, value + 1) }
            }), range: 10...64, label: { "\($0)" }, reset: nil)
            Button("Reset thresholds") {
                settings.wrappedValue.onThreshold = 20
                settings.wrappedValue.offThreshold = 15
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("Higher sensitivity makes lighter presses louder. A key turns on above the on threshold and off below the off threshold.")
        }

        Section("Select button") {
            SliderRow(title: "Hold time", value: settings.selectHoldTime, range: 1...127,
                      label: { "\(Double($0) * 0.05, specifier: "%.2f") s" }, reset: 10)
        }

        Section {
            SliderRow(title: "Backlight brightness", value: settings.backlightBrightness, range: 0...29,
                      label: { "\(Int(Double($0) / 29 * 100))%" }, reset: nil)
            Toggle("Send full volume on preset change", isOn: settings.fullVolumeOnPresetChange)
            Toggle("Velocity override (all notes 127)", isOn: settings.velocityOverride)
            Picker("Program change preset control", selection: settings.programChangeChannel) {
                ForEach(0..<16, id: \.self) { Text("Channel \($0 + 1)").tag($0) }
                Text("Disabled").tag(16)
            }
        } header: {
            Text("Device")
        } footer: {
            Text("Backlight brightness applies to the 12 Step2. Program change preset control lets incoming program changes on that channel select presets.")
        }

        Section {
            Button {
                Task { await saveAndSend() }
            } label: {
                HStack {
                    Label(isDirty ? "Save and send to 12 Step" : "Send settings to 12 Step", systemImage: "square.and.arrow.up")
                    if sending { Spacer(); ProgressView() }
                }
            }
            .disabled(!model.canSend || sending)
        } footer: {
            Text(model.session.selectedDestination == nil ? "Connect the 12 Step to send." : "Sends only the global settings; presets are unchanged.")
        }
    }

    // MARK: Actions

    @discardableResult
    private func save() -> Bool {
        guard let draft else { return false }
        do {
            try model.presets.update { $0.settings = draft }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func saveAndSend() async {
        if isDirty, !save() { return }
        sending = true
        message = await model.sendSettings()
        sending = false
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> LocalizedStringKey
    let reset: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(label(value)).monospacedDigit().foregroundStyle(.secondary)
                if let reset, value != reset {
                    Button("Reset") { value = reset }.buttonStyle(.borderless).font(.caption)
                }
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
        }
    }
}
