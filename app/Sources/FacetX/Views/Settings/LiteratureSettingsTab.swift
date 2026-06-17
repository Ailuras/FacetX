import AppKit
import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared
    @State private var metadata = MetadataStore.shared
    @EnvironmentObject private var toast: ToastController

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Recommendation strategy, translation and scoring rules", "推荐策略、翻译与评分规则"),
                     systemImage: "books.vertical",
                     warning: nil) {
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

    // MARK: - Recommendations

    private var recommendationCard: some View {
        SettingsCard(title: L10n.pick("Recommendation Strategy", "推荐策略"), systemImage: "sparkles",
                     subtitle: L10n.pick("Set how many high-score and recent papers are recommended each day.",
                                         "分别设置每天推荐几篇高分文献和近期文献。")) {
            HStack(spacing: 10) {
                recommendationLane(title: L10n.pick("High Score", "高分"),
                                   value: "\(settings.qualitySlots)",
                                   systemImage: "star.fill",
                                   tint: .yellow) {
                    compactStepperRow(L10n.pick("Papers", "篇数"),
                                      value: $settings.qualitySlots,
                                      range: 0...20,
                                      unit: L10n.pick("papers", "篇"),
                                      valueWidth: 42)
                    compactDivider
                    compactStepperRow(L10n.pick("Minimum", "分数下限"),
                                      value: $settings.highScoreThreshold,
                                      range: 0...100,
                                      unit: L10n.pick("score", "分"),
                                      valueWidth: 42)
                }

                recommendationLane(title: L10n.pick("Recent", "近期"),
                                   value: "\(settings.recentSlots)",
                                   systemImage: "clock.badge",
                                   tint: .blue) {
                    compactStepperRow(L10n.pick("Papers", "篇数"),
                                      value: $settings.recentSlots,
                                      range: 0...20,
                                      unit: L10n.pick("papers", "篇"),
                                      valueWidth: 42)
                    compactDivider
                    compactStepperRow(L10n.pick("Window", "时间窗口"),
                                      value: $settings.recentDays,
                                      range: 1...365,
                                      unit: L10n.pick("days", "天"),
                                      valueWidth: 52)
                }
            }

            ProjectEditorHelp(L10n.pick("Daily total: \(settings.qualitySlots + settings.recentSlots) papers. High-score picks use the score threshold; recent picks use the publication-date window.",
                                        "每日总数：\(settings.qualitySlots + settings.recentSlots) 篇。高分推荐使用分数下限；近期推荐使用发表时间窗口。"))
                .padding(.leading, 28)
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

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private func recommendationLane<Content: View>(title: String, value: String,
                                                   systemImage: String, tint: Color,
                                                   @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SettingsUI.smallFont)
                        .foregroundStyle(.secondary)
                    Text(L10n.pick("\(value) papers", "\(value) 篇"))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer()
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FacetTheme.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func compactStepperRow(_ title: String,
                                   value: Binding<Int>, range: ClosedRange<Int>,
                                   unit: String, valueWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(SettingsUI.rowFont)
                .lineLimit(1)
            Spacer()
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: valueWidth)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .font(SettingsUI.smallFont)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.36)
            .padding(.leading, 2)
    }
}
