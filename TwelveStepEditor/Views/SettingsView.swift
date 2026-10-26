import SwiftUI
import TwelveStepKit

/// Global settings (the desktop's Settings tab) and where the preset files live.
///
/// Like the desktop editor, every change is saved straight away and, with Live updates on, sent to
/// the 12 Step a moment after you stop moving the control (settings.cpp `slotValueChanged` →
/// `MainWindow::slotSendSettings`). Only the settings packet is sent; presets and setlist are not.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: GlobalSettings?
    @AppStorage("liveSettingsUpdates") private var liveUpdates = true
    @State private var saveTask: Task<Void, Never>?
    @State private var sendTask: Task<Void, Never>?
    @State private var liveStatus: LiveStatus = .idle
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
            Toggle(isOn: $liveUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live updates")
                    liveStatusText
                }
            }
            if !liveUpdates {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Label("Send settings to 12 Step", systemImage: "square.and.arrow.up")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(!model.canSend || sending)
            }
        } header: {
            Text("12 Step")
        } footer: {
            Text(liveUpdates
                 ? "Changes are saved and sent to the connected 12 Step as you make them, like the desktop editor. Only these global settings are sent; presets and the setlist are not."
                 : "Changes are saved here only. Tap Send to update the 12 Step. Only these global settings are sent; presets and the setlist are not.")
        }
    }

    @ViewBuilder private var liveStatusText: some View {
        switch liveStatus {
        case _ where model.session.selectedDestination == nil:
            Text("12 Step not connected").font(.caption).foregroundStyle(.secondary)
        case .idle:
            Text(liveUpdates ? "Ready" : "Off").font(.caption).foregroundStyle(.secondary)
        case .sending:
            Text("Sending…").font(.caption).foregroundStyle(.secondary)
        case .sent:
            Label("Sent to 12 Step", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let reason):
            Label("Not sent: \(reason)", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: Actions

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

        guard liveUpdates, model.session.selectedDestination != nil else { return }
        sendTask?.cancel()
        sendTask = Task {
            // Wait for the control to settle (the desktop waits ~10 ms; a touch slider needs longer).
            try? await Task.sleep(for: .milliseconds(150))
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

    /// Manual send (live updates off): sends what's on screen, which may be a moment ahead of the file.
    private func send() async {
        guard let draft else { return }
        sending = true
        do {
            try await model.sendSettingsWhenFree(draft)
            message = "Sent the global settings to the 12 Step."
        } catch {
            message = "Not sent: \(error.localizedDescription)"
        }
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
