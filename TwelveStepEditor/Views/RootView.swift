// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = "presets"

    var body: some View {
        TabView(selection: $tab) {
            PresetsView().simulatedBanner(model.useSimulator)
                .tabItem { Label("Presets", systemImage: "square.grid.3x2") }.tag("presets")
            SetlistView().simulatedBanner(model.useSimulator)
                .tabItem { Label("Setlist", systemImage: "music.note.list") }.tag("setlist")
            SettingsView().simulatedBanner(model.useSimulator)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag("settings")
            NavigationStack { DeviceView() }.simulatedBanner(model.useSimulator)
                .tabItem { Label("Device", systemImage: "cable.connector") }.tag("device")
        }
        .onAppear { if let route = model.launchRoute.tab { tab = route } }
        .onChange(of: scenePhase) { _, phase in
            // Pick up edits synced from the Mac while the app was in the background.
            if phase == .active { model.presets.reload() }
        }
    }
}

extension View {
    /// An orange strip above the tab bar while the simulated device is in use.
    func simulatedBanner(_ shown: Bool) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if shown && !isScreenshotMode {
                Text("SIMULATED DEVICE — not real hardware")
                    .font(.caption.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.orange)
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

#Preview {
    RootView().environment(AppModel())
}
