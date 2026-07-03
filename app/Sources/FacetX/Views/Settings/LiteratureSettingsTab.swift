import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared
    @State private var automation = AutomationPreferences.shared

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Recommendation strategy and abstract translation", "推荐策略与摘要翻译"),
                     systemImage: "books.vertical",
                     warning: nil) {
            recommendationAndAutomationCard
            translationCard
        }
    }

    // MARK: - Recommendations

    private var recommendationAndAutomationCard: some View {
        SettingsCard(title: L10n.pick("Strategy & Automation", "推荐策略与自动化"), systemImage: "sparkles",
                     subtitle: L10n.pick("Configure daily recommendation rules and automate background tasks.",
                                         "配置每日文献推荐规则，并设置后台自动运行计划。")) {
            HStack(spacing: 10) {
                recommendationLane(title: L10n.pick("High Score", "高分"),
                                   value: "\(settings.qualitySlots)",
                                   systemImage: "star.fill",
                                   tint: .yellow) {
                    compactStepperRow(L10n.pick("Papers", "篇数"),
                                      value: $settings.qualitySlots,
                                      range: 0...20,
                                      unit: L10n.pick("papers", "篇"),
                                      valueWidth: recommendationValueWidth)
                    compactDivider
                    compactStepperRow(L10n.pick("Minimum", "分数下限"),
                                      value: $settings.highScoreThreshold,
                                      range: 0...100,
                                      unit: L10n.pick("score", "分"),
                                      valueWidth: recommendationValueWidth)
                }

                recommendationLane(title: L10n.pick("Recent", "近期"),
                                   value: "\(settings.recentSlots)",
                                   systemImage: "clock.badge",
                                   tint: .blue) {
                    compactStepperRow(L10n.pick("Papers", "篇数"),
                                      value: $settings.recentSlots,
                                      range: 0...20,
                                      unit: L10n.pick("papers", "篇"),
                                      valueWidth: recommendationValueWidth)
                    compactDivider
                    compactStepperRow(L10n.pick("Window", "时间窗口"),
                                      value: $settings.recentDays,
                                      range: 1...365,
                                      unit: L10n.pick("days", "天"),
                                      valueWidth: recommendationValueWidth)
                }
            }

            SettingsRow(title: L10n.pick("Enable Automation", "启用自动化"), systemImage: "power") {
                Toggle("", isOn: $automation.automationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 10) {
                automationPlan(title: L10n.pick("Monthly Fetch", "每月拉取"),
                               enabled: $automation.autoFetchEnabled,
                               enabledValue: automation.autoFetchEnabled,
                               systemImage: "calendar.badge.plus",
                               tint: .blue,
                               lastRun: automation.lastAutoFetchAt) {
                    HStack(spacing: 8) {
                        Picker("", selection: clamped($automation.fetchDay, to: 1...28)) {
                            ForEach(1...28, id: \.self) { day in
                                Text(L10n.pick("Day \(day)", "\(day) 日")).tag(day)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 92)
                        DatePicker("", selection: $automation.fetchTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 88)
                    }
                }

                automationPlan(title: L10n.pick("Daily Recommend", "每日推荐"),
                               enabled: $automation.autoRecommendEnabled,
                               enabledValue: automation.autoRecommendEnabled,
                               systemImage: "sparkles",
                               tint: .purple,
                               lastRun: automation.lastAutoRecommendAt) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $automation.recommendTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 88)
                        Spacer()
                    }
                }
            }
            .disabled(!automation.automationEnabled)
        }
    }

    // MARK: - Translation

    private var translationCard: some View {
        SettingsCard(title: L10n.pick("Translation", "翻译"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("Translate paper abstracts with DeepSeek. Credentials live in Integrations.",
                                         "使用 DeepSeek 翻译文献摘要，凭据位于「集成」。")) {
            SettingsRow(title: L10n.pick("Abstract Translation", "摘要翻译"), systemImage: "globe") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $settings.translateEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    TextField(L10n.pick("Target Language", "目标语言"), text: $settings.targetLanguage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(!settings.translateEnabled)
                        .opacity(settings.translateEnabled ? 1 : 0.55)
                }
                .frame(width: SettingsUI.controlWidth, alignment: .trailing)
            }
        }
    }

    // MARK: - Helpers

    private var recommendationValueWidth: CGFloat { 52 }

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
                .frame(width: 48, alignment: .leading)
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



    private func automationPlan<Content: View>(title: String,
                                               enabled: Binding<Bool>,
                                               enabledValue: Bool,
                                               systemImage: String,
                                               tint: Color,
                                               lastRun: Date?,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SettingsUI.smallFont)
                        .foregroundStyle(.secondary)
                    Text(enabledValue ? L10n.pick("On", "已启用") : L10n.pick("Off", "未启用"))
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            content()
                .opacity(enabledValue ? 1 : 0.45)
                .disabled(!enabledValue)

            if let lastRun {
                Label(lastRun.formatted(date: .abbreviated, time: .shortened), systemImage: "clock.arrow.circlepath")
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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

}
