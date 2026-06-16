import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
            DefaultsSettingsTab()
                .tabItem { Label(L10n.t(.tabDefaults), systemImage: "tray.and.arrow.down") }
            SourcesSettingsTab()
                .tabItem { Label(L10n.t(.tabSources), systemImage: "square.stack.3d.up") }
            IntegrationsSettingsTab()
                .tabItem { Label(L10n.t(.tabIntegrations), systemImage: "curlybraces") }
            ShortcutsSettingsTab()
                .tabItem { Label(L10n.t(.tabShortcuts), systemImage: "keyboard") }
        }
        .frame(width: 720, height: 600)
        // tabItem labels are cached by TabView and do not refresh when L10n
        // changes; rebuild the whole tab bar when the language switches.
        .id(settings.language)
    }
}
