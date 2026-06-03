import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DefaultsSettingsTab()
                .tabItem { Label("Defaults", systemImage: "tray.and.arrow.down") }
            SourcesSettingsTab()
                .tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
            IntegrationsSettingsTab()
                .tabItem { Label("Integrations", systemImage: "curlybraces") }
        }
        .frame(width: 720, height: 600)
    }
}
