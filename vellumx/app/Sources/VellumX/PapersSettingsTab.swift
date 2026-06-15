import SwiftUI

struct PapersSettingsTab: View {
    @State private var store = PaperStore.shared
    @State private var settings = AppSettings.shared
    @State private var automation = AutomationPreferences.shared
    @State private var newCollectionName = ""

    var body: some View {
        Form {
            Section(L10n.t(.dailyRecommendations)) {
                stepperRow(L10n.t(.dailyCount), value: $settings.dailyCount, in: 1...20)
                stepperRow(L10n.t(.qualitySlots), value: $settings.qualitySlots, in: 0...20)
                stepperRow(L10n.t(.highScoreThreshold), value: $settings.highScoreThreshold, in: 0...100)
                stepperRow(L10n.t(.recentWindow), value: $settings.recentDays, in: 1...365)
            }

            Section(L10n.t(.openAlexFetch)) {
                TextField(L10n.t(.contactEmail), text: $settings.openAlexMailto)
                    .textFieldStyle(.roundedBorder)

                LabeledContent(L10n.t(.perPage)) {
                    TextField("", value: $settings.perPage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                LabeledContent(L10n.t(.fetchDays)) {
                    TextField("", value: $settings.defaultDays, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                LabeledContent(L10n.t(.maxResults)) {
                    TextField("", value: $settings.defaultMaxResults, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                TextField(L10n.t(.topicFilter), text: $settings.topicFilter)
                    .textFieldStyle(.roundedBorder)
            }

            Section(L10n.t(.automation)) {
                Toggle(L10n.t(.enableAutomation), isOn: $automation.automationEnabled)

                if automation.automationEnabled {
                    HStack {
                        Text(L10n.t(.monthlyFetch))
                        Spacer()
                        if automation.autoFetchEnabled {
                            Picker("", selection: $automation.fetchDay) {
                                ForEach(1 ... 28, id: \.self) { d in
                                    Text("\(d)").tag(d)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 56)
                            DatePicker("", selection: $automation.fetchTime,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        Toggle("", isOn: $automation.autoFetchEnabled).labelsHidden()
                    }

                    HStack {
                        Text(L10n.t(.dailyRecommend))
                        Spacer()
                        if automation.autoRecommendEnabled {
                            DatePicker("", selection: $automation.recommendTime,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        Toggle("", isOn: $automation.autoRecommendEnabled).labelsHidden()
                    }
                }
            }

            Section("Collections") {
                if store.allCollections.isEmpty {
                    Text("No collections yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.allCollections) { collection in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(collectionColor(collection))
                            Text(collection.name)
                            Spacer()
                            Button(role: .destructive) {
                                store.deleteCollection(id: collection.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("New collection name", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        _ = store.createCollection(name: newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines))
                        newCollectionName = ""
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func collectionColor(_ collection: PaperCollection) -> Color {
        if let colorName = collection.color, let labelColor = LabelColor(rawValue: colorName) {
            return labelColor.color
        }
        return .accentColor
    }

    private func stepperRow(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: clamped(value, to: range), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
