import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Fetching and recommendations", "拉取与推荐"),
                     systemImage: "books.vertical",
                     warning: nil) {
            fetchCard
            recommendationCard
        }
    }

    // MARK: - Fetch

    private var fetchCard: some View {
        SettingsCard(title: L10n.pick("OpenAlex Fetch", "OpenAlex 拉取"), systemImage: "magnifyingglass",
                     subtitle: L10n.pick("How many results Fetch pulls and how it filters them.",
                                         "“拉取”获取的结果数量与过滤方式。")) {
            numberRow(L10n.pick("Results per Page", "每页结果"), systemImage: "list.number",
                      value: $settings.perPage, range: 1...200)
            SettingsDivider()
            numberRow(L10n.pick("Max Results", "最大结果数"), systemImage: "number",
                      value: $settings.defaultMaxResults, range: 1...1000)
            SettingsDivider()
            SettingsRow(title: L10n.pick("Topic Filter", "主题过滤"), systemImage: "line.3.horizontal.decrease.circle") {
                TextField(L10n.pick("optional OpenAlex filter", "可选 OpenAlex 过滤"), text: $settings.topicFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            ProjectEditorHelp(L10n.pick("The contact email lives in Integrations → OpenAlex.",
                                        "联系邮箱位于「集成 → OpenAlex」。"))
                .padding(.leading, 28)
        }
    }

    // MARK: - Recommendations

    private var recommendationCard: some View {
        SettingsCard(title: L10n.pick("Daily Recommendations", "每日推荐"), systemImage: "sparkles",
                     subtitle: L10n.pick("Tunes how the daily recommendation slots are filled.",
                                         "调整每日推荐名额的分配方式。")) {
            stepperRow(L10n.pick("Daily Count", "每日数量"), systemImage: "number.circle",
                       value: $settings.dailyCount, range: 1...20)
            SettingsDivider()
            stepperRow(L10n.pick("Quality Slots", "高分名额"), systemImage: "star.circle",
                       value: $settings.qualitySlots, range: 0...20)
            SettingsDivider()
            stepperRow(L10n.pick("High-Score Threshold", "高分阈值"), systemImage: "chart.line.uptrend.xyaxis",
                       value: $settings.highScoreThreshold, range: 0...100)
            SettingsDivider()
            stepperRow(L10n.pick("Recent Window (days)", "近期窗口（天）"), systemImage: "calendar.badge.clock",
                       value: $settings.recentDays, range: 1...365)
        }
    }

    // MARK: - Helpers

    private func numberRow(_ title: String, systemImage: String,
                           value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func stepperRow(_ title: String, systemImage: String,
                            value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            HStack(spacing: 4) {
                TextField("", value: clamped(value, to: range), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: value, in: range)
                    .labelsHidden().controlSize(.mini)
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
