import AppKit
import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared
    @State private var metadata = MetadataStore.shared
    @EnvironmentObject private var toast: ToastController

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Fetch scope, recommendation strategy and scoring rules", "拉取范围、推荐策略与评分规则"),
                     systemImage: "books.vertical",
                     warning: nil) {
            fetchCard
            recommendationCard
            translationCard
            VenueRulesCard(metadata: metadata)
            TierRulesCard(metadata: metadata)
            CitationRulesCard(metadata: metadata)
            rulesActions
        }
    }

    private var rulesActions: some View {
        HStack(spacing: 10) {
            Button {
                let changed = PaperStore.shared.refreshVenueMetadata()
                metadata.markRulesApplied()
                toast.show(L10n.pick("Recomputed \(changed) papers", "已重算 \(changed) 篇"), type: .success)
            } label: {
                Label(L10n.pick("Apply to Library", "应用到文献库"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!metadata.rulesDirty)
            .help(L10n.pick("Re-score every paper using the current rules.",
                            "用当前规则重新为所有文献评分。"))

            Button {
                exportRules()
            } label: {
                Label(L10n.pick("Export", "导出"), systemImage: "square.and.arrow.up")
            }
            .help(L10n.pick("Export venues, tiers and scoring rules to a file.",
                            "将会议、等级与评分规则导出到文件。"))

            Button {
                importRules()
            } label: {
                Label(L10n.pick("Import", "导入"), systemImage: "square.and.arrow.down")
            }
            .help(L10n.pick("Replace the current rules with a configuration file.",
                            "用配置文件替换当前规则。"))

            Spacer()

            Button(role: .destructive) {
                metadata.resetToPreset()
                toast.show(L10n.pick("Rules reset to preset", "规则已重置为预设"), type: .info)
            } label: {
                Label(L10n.pick("Reset to Preset", "重置为预设"), systemImage: "arrow.counterclockwise")
            }
        }
        .controlSize(.small)
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "facetx-literature-rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try metadata.exportMetadata().write(to: url)
            toast.show(L10n.pick("Rules exported", "规则已导出"), type: .success)
        } catch {
            toast.show(L10n.pick("Export failed: \(error.localizedDescription)",
                                 "导出失败：\(error.localizedDescription)"), type: .error)
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try metadata.importMetadata(from: Data(contentsOf: url))
            toast.show(L10n.pick("Rules imported", "规则已导入"), type: .success)
        } catch {
            toast.show(L10n.pick("Import failed: \(error.localizedDescription)",
                                 "导入失败：\(error.localizedDescription)"), type: .error)
        }
    }

    // MARK: - Fetch

    private var fetchCard: some View {
        SettingsCard(title: L10n.pick("OpenAlex Fetch Scope", "OpenAlex 拉取范围"), systemImage: "magnifyingglass",
                     subtitle: L10n.pick("Controls how much each library fetch asks OpenAlex for.",
                                         "控制每次文献库拉取向 OpenAlex 请求多少内容。")) {
            stepperRow(L10n.pick("Publication Window", "发表时间窗口"), systemImage: "calendar.badge.clock",
                       value: $settings.defaultDays, range: 1...365,
                       unit: L10n.pick("days", "天"), valueWidth: 56)
            SettingsDivider()
            stepperRow(L10n.pick("Results per Request", "每次请求数量"), systemImage: "list.number",
                       value: $settings.perPage, range: 1...200,
                       unit: L10n.pick("items", "条"), valueWidth: 56)
            SettingsDivider()
            stepperRow(L10n.pick("Total Cap per Library", "单库总上限"), systemImage: "number",
                       value: $settings.defaultMaxResults, range: 1...1000,
                       unit: L10n.pick("items", "条"), valueWidth: 64)
            SettingsDivider()
            SettingsRow(title: L10n.pick("OpenAlex Filter", "OpenAlex 过滤"), systemImage: "line.3.horizontal.decrease.circle") {
                TextField(L10n.pick("topics.field.id:17", "topics.field.id:17"), text: $settings.topicFilter)
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
        SettingsCard(title: L10n.pick("Recommendation Strategy", "推荐策略"), systemImage: "sparkles",
                     subtitle: L10n.pick("Controls how daily recommendation slots are balanced.",
                                         "控制每日推荐名额如何分配。")) {
            stepperRow(L10n.pick("Daily Slots", "每日名额"), systemImage: "number.circle",
                       value: $settings.dailyCount, range: 1...20,
                       unit: L10n.pick("papers", "篇"), valueWidth: 48)
            SettingsDivider()
            stepperRow(L10n.pick("High-Score Slots", "高分名额"), systemImage: "star.circle",
                       value: $settings.qualitySlots, range: 0...20,
                       unit: L10n.pick("slots", "个"), valueWidth: 48)
            SettingsDivider()
            stepperRow(L10n.pick("High-Score Minimum", "高分下限"), systemImage: "chart.line.uptrend.xyaxis",
                       value: $settings.highScoreThreshold, range: 0...100,
                       unit: L10n.pick("score", "分"), valueWidth: 48)
            SettingsDivider()
            stepperRow(L10n.pick("Recent Priority Window", "近期优先窗口"), systemImage: "calendar.badge.clock",
                       value: $settings.recentDays, range: 1...365,
                       unit: L10n.pick("days", "天"), valueWidth: 56)
        }
    }

    // MARK: - Translation

    private var translationCard: some View {
        SettingsCard(title: L10n.pick("Translation", "翻译"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("Translate paper abstracts. Provider and API key live in Integrations → LLM API.",
                                         "翻译文献摘要。服务商与密钥位于「集成 → 大模型 API」。")) {
            SettingsRow(title: L10n.pick("Enable Translation", "启用翻译"), systemImage: "globe") {
                Toggle("", isOn: $settings.translateEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Target Language", "目标语言"), systemImage: "text.bubble") {
                TextField("", text: $settings.targetLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
        }
    }

    // MARK: - Helpers

    private func stepperRow(_ title: String, systemImage: String,
                            value: Binding<Int>, range: ClosedRange<Int>,
                            unit: String, valueWidth: CGFloat) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            HStack(spacing: 6) {
                TextField("", value: clamped(value, to: range), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: valueWidth)
                    .textFieldStyle(.roundedBorder)
                Text(unit)
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
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
