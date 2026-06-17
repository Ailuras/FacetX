import AppKit
import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared
    @State private var metadata = MetadataStore.shared
    @State private var automation = AutomationPreferences.shared
    @EnvironmentObject private var toast: ToastController

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Fetching, recommendations and scoring rules", "拉取、推荐与评分规则"),
                     systemImage: "books.vertical",
                     warning: nil) {
            fetchCard
            recommendationCard
            automationCard
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

    // MARK: - Automation

    private var automationCard: some View {
        SettingsCard(title: L10n.pick("Automation", "自动化"), systemImage: "clock.badge.checkmark",
                     subtitle: L10n.pick("Run literature fetch and recommendation while FacetX is open.",
                                         "在 FacetX 运行时自动拉取文献并生成推荐。")) {
            SettingsRow(title: L10n.pick("Enable Automation", "启用自动化"), systemImage: "power") {
                Toggle("", isOn: $automation.automationEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Monthly Fetch", "每月拉取"), systemImage: "calendar.badge.plus") {
                HStack(spacing: 8) {
                    if automation.autoFetchEnabled {
                        Picker("", selection: clamped($automation.fetchDay, to: 1...28)) {
                            ForEach(1...28, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .labelsHidden().frame(width: 58)
                        DatePicker("", selection: $automation.fetchTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().frame(width: 86)
                    }
                    Toggle("", isOn: $automation.autoFetchEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                .disabled(!automation.automationEnabled)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Daily Recommend", "每日推荐"), systemImage: "sparkles") {
                HStack(spacing: 8) {
                    if automation.autoRecommendEnabled {
                        DatePicker("", selection: $automation.recommendTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().frame(width: 86)
                    }
                    Toggle("", isOn: $automation.autoRecommendEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                .disabled(!automation.automationEnabled)
            }
            if automation.lastAutoFetchAt != nil || automation.lastAutoRecommendAt != nil {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 5) {
                    if let last = automation.lastAutoFetchAt {
                        Text(L10n.pick("Last fetch: \(last.formatted(date: .abbreviated, time: .shortened))",
                                       "上次拉取：\(last.formatted(date: .abbreviated, time: .shortened))"))
                    }
                    if let last = automation.lastAutoRecommendAt {
                        Text(L10n.pick("Last recommend: \(last.formatted(date: .abbreviated, time: .shortened))",
                                       "上次推荐：\(last.formatted(date: .abbreviated, time: .shortened))"))
                    }
                }
                .font(SettingsUI.smallFont)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
            }
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
