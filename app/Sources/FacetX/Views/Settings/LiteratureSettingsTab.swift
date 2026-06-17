import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Recommendation strategy and abstract translation", "推荐策略与摘要翻译"),
                     systemImage: "books.vertical",
                     warning: nil) {
            recommendationCard
            translationCard
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
        }
    }

    // MARK: - Translation

    private var translationCard: some View {
        SettingsCard(title: L10n.pick("Translation", "翻译"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("Translate paper abstracts. Provider and API key live in Integrations → LLM API.",
                                         "翻译文献摘要。服务商与密钥位于「集成 → 大模型 API」。")) {
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
