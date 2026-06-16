import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showRestartPrompt = false

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
            DefaultsSettingsTab()
                .tabItem { Label(L10n.t(.tabDefaults), systemImage: "tray.and.arrow.down") }
            SourcesSettingsTab()
                .tabItem { Label(L10n.t(.tabSources), systemImage: "square.stack.3d.up") }
            LiteratureSettingsTab()
                .tabItem { Label(L10n.pick("Literature", "文献"), systemImage: "books.vertical") }
            IntegrationsSettingsTab()
                .tabItem { Label(L10n.t(.tabIntegrations), systemImage: "curlybraces") }
            ShortcutsSettingsTab()
                .tabItem { Label(L10n.t(.tabShortcuts), systemImage: "keyboard") }
        }
        .frame(width: 720, height: 600)
        .onChange(of: settings.language) { showRestartPrompt = true }
        .alert(L10n.t(.restartTitle), isPresented: $showRestartPrompt) {
            Button(L10n.t(.restartNow)) { AppRelauncher.relaunch() }
            Button(L10n.t(.restartLater), role: .cancel) {}
        } message: {
            Text(L10n.t(.restartMessage))
        }
    }
}
