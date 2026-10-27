// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI

/// Version, affiliation, privacy and licensing. MPL-2.0 requires telling people where the source
/// of the MPL-covered files can be found.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    /// Public source repository.
    static let sourceURL = URL(string: "https://github.com/zackbleach/TwelveStepEditor")!
    static let licenseURL = URL(string: "https://github.com/zackbleach/TwelveStepEditor/blob/main/LICENSE.md")!
    static let desktopEditorURL = URL(string: "https://github.com/Muse-Kinetics/12-step-editor-qt6")!

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: model.shortVersion)
            } footer: {
                Text("An independent editor for the 12 Step foot controller, not made by Muse Kinetics (Keith McMillen Instruments). 12 Step is their trademark, used with permission.")
            }

            Section("Privacy") {
                Text("The app collects no data. Presets stay in the folder you choose, and the app talks only to the 12 Step over USB.")
            }

            Section {
                Link(destination: Self.sourceURL) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: Self.licenseURL) { Label("Licence", systemImage: "doc.text") }
                Link(destination: Self.desktopEditorURL) { Label("Official 12 Step Editor source", systemImage: "arrow.up.forward.square") }
            } header: {
                Text("Source code")
            } footer: {
                Text("The source is free for noncommercial use (PolyForm Noncommercial 1.0.0). The SysEx framing, preset upload format and factory presets come from Muse Kinetics' 12 Step Editor and remain under the Mozilla Public License 2.0.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
