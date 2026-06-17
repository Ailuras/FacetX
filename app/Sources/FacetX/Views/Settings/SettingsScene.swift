import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showRestartPrompt = false

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
            ProjectSettingsTab()
                .tabItem { Label(L10n.pick("Project", "项目"), systemImage: "folder") }
            LiteratureSettingsTab()
                .tabItem { Label(L10n.pick("Literature", "文献"), systemImage: "books.vertical") }
            LiteratureRulesSettingsTab()
                .tabItem { Label(L10n.pick("Rules", "规则"), systemImage: "slider.horizontal.3") }
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
