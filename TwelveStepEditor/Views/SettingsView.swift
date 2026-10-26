import SwiftUI
import TwelveStepKit

/// Global settings (the desktop's Settings tab) and where the preset files live.
///
/// Like the desktop editor, every change is saved straight away and sent to the connected 12 Step
/// a moment after you stop moving the control (settings.cpp `slotValueChanged` →
/// `MainWindow::slotSendSettings`). Only the settings packet is sent; presets and setlist are not.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: GlobalSettings?
    @State private var saveTask: Task<Void, Never>?
    @State private var sendTask: Task<Void, Never>?
    @State private var liveStatus: LiveStatus = .idle
    @State private var choosingFolder = false
    @State private var settingUpSync = false
    @AppStorage("macSyncCardDismissed") private var syncCardDismissed = false
    @State private var confirmingRestore = false
    @State private var message: String?

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
            .onAppear {
                if draft == nil { draft = saved }
                #if DEBUG
                // -liveSettingsTest: three quick backlight changes; expect one save and one send.
                if ProcessInfo.processInfo.arguments.contains("-liveSettingsTest") {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        for level in [5, 12, 20] { draft?.backlightBrightness = level; try? await Task.sleep(for: .milliseconds(40)) }
                    }
                }
                #endif
            }
            .onChange(of: saved) { _, latest in if !isDirty && saveTask == nil { draft = latest } }
            .onChange(of: draft) { old, new in
                // Ignore the initial load and reloads from disk; react to edits.
                guard let old, let new, old != new, new != saved else { return }
                settingsChanged(new)
            }
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
            SliderRow(title: "Key sensitivity", value: settings.keySensitivitySlider, range: 1...500,
                      label: { "\(Double($0) / 5, specifier: "%g")%" }, reset: 100,
                      help: "The overall sensitivity of the keys and Select button. Higher makes velocity, pressure and tilt values larger, and keys turn on with less force.")
            SliderRow(title: "On threshold", value: Binding(get: { settings.wrappedValue.onThreshold }, set: { value in
                settings.wrappedValue.onThreshold = value
                if settings.wrappedValue.offThreshold >= value { settings.wrappedValue.offThreshold = max(10, value - 1) }
            }), range: 15...64, label: { "\($0)" }, reset: nil,
                      help: "The pressure needed to turn a key on. Higher needs more pressure; lower makes keys more sensitive.")
            SliderRow(title: "Off threshold", value: Binding(get: { settings.wrappedValue.offThreshold }, set: { value in
                settings.wrappedValue.offThreshold = value
                if value >= settings.wrappedValue.onThreshold { settings.wrappedValue.onThreshold = min(64, value + 1) }
            }), range: 10...64, label: { "\($0)" }, reset: nil,
                      help: "The pressure below which a held key turns off. Lower makes a key easier to keep held; higher makes fast repeated notes easier. Always below the on threshold.")
            Button("Reset thresholds") {
                settings.wrappedValue.onThreshold = 20
                settings.wrappedValue.offThreshold = 15
            }
        } header: {
            Text("Keys")
        }

        Section("Select button") {
            SliderRow(title: "Hold time", value: settings.selectHoldTime, range: 1...127,
                      label: { "\(Double($0) * 0.05, specifier: "%.2f") s" }, reset: 10,
                      help: "How long you hold the Select key before Select Mode starts, for changing presets and octaves. From 0.05 to 6 seconds.")
        }

        Section {
            SliderRow(title: "Backlight", value: settings.backlightBrightness, range: 0...29,
                      label: { "\(Int(Double($0) / 29 * 100))%" }, reset: nil,
                      help: "Brightness of the key backlights. 12 Step2 only. It can also be set with CC 69 on the Change preset by MIDI channel.")
            HelpRow("Full volume on preset change",
                    help: "Sends CC 7 (volume) at 127 whenever you change preset.") {
                Toggle("", isOn: settings.fullVolumeOnPresetChange).labelsHidden()
            }
            HelpRow("Full velocity",
                    help: "Every note plays at full velocity (127), ignoring the velocity settings in your presets' modlines.") {
                Toggle("", isOn: settings.velocityOverride).labelsHidden()
            }
            HelpRow("Change preset by MIDI",
                    help: "The channel the 12 Step listens on for program changes: program change 23 loads the 23rd preset in the setlist. Backlight (CC 69) and display messages are received on this channel too. Off ignores them.") {
                Picker("", selection: settings.programChangeChannel) {
                    ForEach(0..<16, id: \.self) { Text("Channel \($0 + 1)").tag($0) }
                    Text("Off").tag(16)
                }
                .labelsHidden()
            }
        } header: {
            Text("Device")
        } footer: {
            liveStatusText
        }
    }

    /// Settings are always sent live, like the desktop editor; this line shows what happened.
    @ViewBuilder private var liveStatusText: some View {
        switch liveStatus {
        case .idle:
            EmptyView()
        case .sending:
            Label("Sending to the 12 Step…", systemImage: "arrow.up.circle")
        case .sent:
            Label("Sent to the 12 Step.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let reason):
            Label("Not sent: \(reason)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    enum LiveStatus: Equatable { case idle, sending, sent, failed(String) }

    /// Saves (in the background, after a short pause so a slider drag writes once) and, with live
    /// updates on and the 12 Step connected, sends the new settings.
    private func settingsChanged(_ settings: GlobalSettings) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try model.presets.updateInBackground({ $0.settings = settings }) { error in
                    message = "Couldn't save settings: \(error.localizedDescription) The latest files have been reloaded."
                    draft = model.presets.contents?.settings
                }
            } catch {
                message = error.localizedDescription
            }
            saveTask = nil
        }

        guard model.session.selectedDestination != nil else { return }
        sendTask?.cancel()
        sendTask = Task {
            // Same pause as the desktop: its 1 ms timer sends once 11 ticks pass with no change
            // (settings.cpp slotSaveSettingsTimeout).
            try? await Task.sleep(for: .milliseconds(11))
            guard !Task.isCancelled else { return }
            liveStatus = .sending
            do {
                try await model.sendSettingsWhenFree(settings)
                if !Task.isCancelled { liveStatus = .sent }
            } catch is CancellationError {
            } catch {
                liveStatus = .failed(error.localizedDescription)
            }
        }
    }

}

private struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> LocalizedStringKey
    let reset: Int?
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).holdForHelp(title, help)
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

/// A setting whose name explains itself on touch and hold, with its control on the trailing side.
private struct HelpRow<Control: View>: View {
    let title: String
    let help: String
    @ViewBuilder let control: Control

    init(_ title: String, help: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.help = help
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).holdForHelp(title, help)
            Spacer(minLength: 8)
            control
        }
    }
}
