import SwiftUI
import TwelveStepKit

@main
struct TwelveStepEditorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
