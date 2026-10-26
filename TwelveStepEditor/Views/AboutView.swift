import SwiftUI

/// Version, affiliation, privacy and licensing. MPL-2.0 requires telling people where the source
/// of the MPL-covered files can be found.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    /// Public source repository. TODO.org tracks creating it; keep this in step with its URL.
    static let sourceURL = URL(string: "https://github.com/zackbleach/TwelveStepEditor")!
    static let licenseURL = URL(string: "https://mozilla.org/MPL/2.0/")!
    static let desktopEditorURL = URL(string: "https://github.com/Muse-Kinetics/12-step-editor-qt6")!

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: model.shortVersion)
            } footer: {
                Text("An independent editor for the 12 Step foot controller. Not made or endorsed by Muse Kinetics (Keith McMillen Instruments). 12 Step is their trademark.")
            }

            Section("Privacy") {
                Text("The app collects no data. Presets stay in the folder you choose, and the app talks only to the 12 Step over USB.")
            }

            Section {
                Link(destination: Self.sourceURL) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: Self.licenseURL) { Label("Mozilla Public License 2.0", systemImage: "doc.text") }
                Link(destination: Self.desktopEditorURL) { Label("Official 12 Step Editor source", systemImage: "arrow.up.forward.square") }
            } header: {
                Text("Open source")
            } footer: {
                Text("The SysEx framing, the preset upload format and the factory presets are derived from Muse Kinetics' 12 Step Editor, used under the Mozilla Public License 2.0. The source code of this app is available at the link above.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
