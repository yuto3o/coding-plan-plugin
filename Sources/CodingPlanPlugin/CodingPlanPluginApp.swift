import SwiftUI

@main
struct CodingPlanPluginApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        MenuBarExtra(appState.menuBarTitle, systemImage: "cpu") {
            UsagePanelView()
                .environmentObject(appState)
                .environmentObject(languageManager)
        }
        .menuBarExtraStyle(.window)
    }
}
