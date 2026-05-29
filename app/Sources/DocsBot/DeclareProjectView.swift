import SwiftUI

/// Sheet to declare a new project. Offers project names auto-discovered from
/// existing item prefixes, or lets the user type a new one.
struct DeclareProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: Settings

    @State private var name = ""
    @State private var tagline = ""
    @State private var discovered: [String] = []
    @State private var loadingDiscovery = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Declare a project").font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Project name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Regulus", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("Items whose title starts with “\(name.isEmpty ? "Name" : name):” will be gathered.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tagline (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("Short description", text: $tagline)
                    .textFieldStyle(.roundedBorder)
            }

            if loadingDiscovery {
                HStack { ProgressView().controlSize(.small); Text("Scanning your items…").font(.caption) }
            } else if !discovered.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found these prefixes in your data:").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(discovered, id: \.self) { n in
                                Button(n) { name = n }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Declare") { declare() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .task {
            discovered = await ek.discoverProjectNames(
                enabledContainers: settings.enabledContainerNames)
            loadingDiscovery = false
        }
    }

    private func declare() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.declare(name: trimmed, tagline: tagline.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}
