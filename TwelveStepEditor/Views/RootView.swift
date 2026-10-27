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
        .demoAccessory(model.useSimulator && !isScreenshotMode)
        .onAppear { if let route = model.launchRoute.tab { tab = route } }
        .onChange(of: scenePhase) { _, phase in
            // Pick up edits synced from the Mac while the app was in the background.
            if phase == .active { model.presets.reload() }
        }
    }
}

extension View {
    /// iOS 26+: a small "Demo mode" bar floating above the tab bar (the system's tab-bar accessory),
    /// instead of a full-width strip that would tint the glass tab bar orange.
    @ViewBuilder func demoAccessory(_ shown: Bool) -> some View {
        if #available(iOS 26.0, *), shown {
            tabViewBottomAccessory {
                Label("Demo mode · simulated 12 Step", systemImage: "play.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .accessibilityLabel("Demo mode: a simulated 12 Step, not real hardware")
            }
        } else {
            self
        }
    }

    /// iOS 17–25: an orange strip above the tab bar while the simulated device is in use.
    /// (On iOS 26+ `demoAccessory` shows it instead.)
    func simulatedBanner(_ shown: Bool) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if #available(iOS 26.0, *) {
                EmptyView()
            } else if shown && !isScreenshotMode {
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
