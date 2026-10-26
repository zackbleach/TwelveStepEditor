import AppKit
import SwiftUI
import SyncCore

@main
struct SyncSetupApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = SyncModel()

    var body: some Scene {
        Window("12 Step Sync", id: "main") {
            ContentView()
                .environment(model)
                .tint(.brand)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SyncSetup --render-icon <dir>` writes the app icon PNGs for build-app.sh, then exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated { AppIconView.renderIconSet(to: URL(filePath: arguments[index + 1])) }
            exit(0)
        }
        // `SyncSetup --snapshot <file.png> [dark]` draws the window offscreen (for docs and review).
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated {
                Self.snapshot(to: URL(filePath: arguments[index + 1]), dark: arguments.contains("dark"))
            }
            exit(0)
        }
    }

    @MainActor private static func snapshot(to file: URL, dark: Bool) {
        let host = NSHostingView(rootView: ContentView().environment(SyncModel()).tint(.brand))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        // Draw it as the active window, so prominent buttons get their colour.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Main window

struct ContentView: View {
    @Environment(SyncModel.self) private var model
    @State private var confirmingDisable = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 22) {
            header
            FlowDiagram(synced: model.isSynced)
            if let outcome = model.lastResult {
                OutcomeBanner(outcome: outcome)
            }
            if model.isSynced {
                NextSteps()
            } else {
                Checklist()
            }
            actions
            FactoryDefaultWarning()
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 500)
        .background(.background)
        .alert("Couldn't change sync", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.error ?? "")
        }
        .confirmationDialog("Turn off iCloud sync?", isPresented: $confirmingDisable) {
            Button("Turn Off Sync") { model.disable() }
        } message: {
            Text("The latest presets in iCloud Drive are copied back to this Mac, and the 12 Step Editor uses its own folder again. The iPhone app keeps using iCloud Drive until you change it there.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppIconView().frame(width: 84, height: 84)
            Text("12 Step Sync").font(.largeTitle.weight(.semibold))
            Text("Share your 12 Step Editor presets with the iPhone app through iCloud Drive.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if model.isSynced {
                HStack {
                    Button("Show in Finder") { model.reveal(model.syncedFolder) }
                    Button("Turn Off Sync…") { confirmingDisable = true }
                        .disabled(model.status.editorRunning)
                }
                .controlSize(.large)
            } else {
                Button { model.enable() } label: {
                    Text("Turn On iCloud Sync").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canEnable)
                .keyboardShortcut(.defaultAction)
            }
            Button {
                model.reveal(model.backupRoot)
            } label: {
                Text("Your presets are backed up before every change. ") + Text("Show backups").foregroundColor(.brand)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            .disabled(!FileManager.default.fileExists(atPath: model.backupRoot.path))
        }
    }
}

// MARK: - Pieces

/// This Mac → iCloud Drive → iPhone, lit up when sync is on.
private struct FlowDiagram: View {
    let synced: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                node("laptopcomputer", "This Mac")
                link
                node("icloud.fill", "iCloud Drive")
                link
                node("iphone", "iPhone app")
            }
            Label(synced ? "Sync is on" : "Sync is off", systemImage: synced ? "checkmark.circle.fill" : "circle.dashed")
                .font(.callout.weight(.semibold))
                .foregroundStyle(synced ? .green : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(synced ? AnyShapeStyle(.green.opacity(0.14)) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(synced ? "Sync is on: this Mac, iCloud Drive and the iPhone app share presets" : "Sync is off")
    }

    private func node(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(synced ? Color.brand : .secondary)
                .frame(height: 36)
            Text(title).font(.callout)
        }
        .frame(width: 104)
    }

    private var link: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.title3.weight(.semibold))
            .foregroundStyle(synced ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
            .offset(y: -12)
            .frame(maxWidth: .infinity)
    }
}

/// What has to be true before sync can be turned on, updated live.
private struct Checklist: View {
    @Environment(SyncModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let status = model.status
        VStack(alignment: .leading, spacing: 12) {
            CheckRow(ok: !status.editorRunning,
                     title: status.editorRunning ? "The 12 Step Editor is open" : "The 12 Step Editor is closed",
                     detail: status.editorRunning ? "Quit it so it doesn't overwrite the files while they move." : nil) {
                if status.editorRunning { Button("Quit Editor") { model.quitEditor() } }
            }
            CheckRow(ok: status.iCloudAvailable,
                     title: status.iCloudAvailable ? "iCloud Drive is on" : "iCloud Drive is off",
                     detail: status.iCloudAvailable ? nil : "Turn it on in System Settings › Apple Account › iCloud.") {
                if !status.iCloudAvailable {
                    Button("Open Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!) }
                }
            }
            CheckRow(ok: status.missingFiles.isEmpty,
                     title: status.missingFiles.isEmpty ? "Found the editor's presets" : "The editor's presets aren't there yet",
                     detail: status.missingFiles.isEmpty ? nil : "Open the 12 Step Editor once so it creates its files, then quit it.") { EmptyView() }
            switch status.cloudContents {
            case .empty:
                EmptyView()
            case .complete:
                Divider()
                Toggle(isOn: $model.useExistingCloudFiles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Drive already has presets, perhaps from another Mac")
                        Text("Use those. This Mac's current presets stay in the backup.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            case .partial:
                CheckRow(ok: false, title: "iCloud Drive › 12 Step Editor has only some files",
                         detail: "Move that folder somewhere else, then try again.") {
                    Button("Show") { model.reveal(model.syncedFolder) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CheckRow<Accessory: View>: View {
    let ok: Bool
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .accessibilityLabel(ok ? "Done" : "Needs attention")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

/// Shown once sync is on.
private struct NextSteps: View {
    @Environment(SyncModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish setting up").font(.headline)
            step(1, "In Finder, right-click iCloud Drive › 12 Step Editor and choose **Keep Downloaded**, so the files are always on this Mac.")
            step(2, "Open the 12 Step Editor and check your presets and setlist look right.")
            step(3, "In the iPhone app: **Settings › Choose folder… › iCloud Drive › 12 Step Editor**.")
            step(4, "Quit the desktop editor while you edit on the iPhone. It doesn't notice changes made elsewhere.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.brand, in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OutcomeBanner: View {
    let outcome: SyncModel.Outcome

    var body: some View {
        Label {
            switch outcome {
            case .enabled(let result):
                Text(result.copiedFiles ? "Sync is on. Your presets are now in iCloud Drive." : "Sync is on, using the presets already in iCloud Drive.")
            case .disabled:
                Text("Sync is off. The latest presets were copied back to this Mac.")
            }
        } icon: {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The one mistake that loses data.
private struct FactoryDefaultWarning: View {
    var body: some View {
        Label {
            Text("If the 12 Step Editor ever says a file is missing, choose **Exit Application**, never **Factory Default**. Factory Default deletes the folder on every synced device.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// The one big action: a filled capsule in the brand colour.
private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .background(isEnabled ? Color.brandDeep : Color.gray.opacity(0.45), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Icon

extension Color {
    /// The iOS app's accent colour (#00AEED), so the two apps feel related.
    static let brand = Color(red: 0, green: 0.682, blue: 0.929)
    /// A deeper shade (#0090CA) for filled buttons: white bold text on it is 3.6:1.
    static let brandDeep = Color(red: 0, green: 0.565, blue: 0.792)
}

/// The app icon, also drawn in the window header: an iCloud badge over a 12 Step-style key row.
struct AppIconView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.2), Color(red: 0.0, green: 0.36, blue: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "icloud.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.1)
                HStack(spacing: size * 0.025) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: size * 0.02)
                            .fill(index == 2 ? Color.brand : .white.opacity(0.85))
                            .frame(width: size * 0.1, height: size * 0.16)
                    }
                }
                .offset(y: size * 0.27)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Writes the PNG sizes `iconutil` expects into `folder` (an .iconset).
    @MainActor static func renderIconSet(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(points * scale)
                // macOS icons sit inside a margin of about 10% on each side.
                let renderer = ImageRenderer(content: AppIconView().padding(pixels * 0.1).frame(width: pixels, height: pixels))
                renderer.scale = 1
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try? png.write(to: folder.appending(path: name))
            }
        }
    }
}
