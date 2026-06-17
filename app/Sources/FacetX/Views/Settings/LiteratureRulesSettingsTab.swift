import AppKit
import SwiftUI

struct LiteratureRulesSettingsTab: View {
    @State private var metadata = MetadataStore.shared
    @EnvironmentObject private var toast: ToastController

    var body: some View {
        SettingsPage(title: L10n.pick("Rules", "规则"),
                     subtitle: L10n.pick("Fields, venue tiers and citation scoring", "领域、会议等级与引用评分"),
                     systemImage: "slider.horizontal.3",
                     warning: nil) {
            rulesSummary
            FieldRulesCard(metadata: metadata)
            TierRulesCard(metadata: metadata)
            VenueRulesCard(metadata: metadata)
            CitationRulesCard(metadata: metadata)
            rulesActions
        }
    }

    private var rulesSummary: some View {
        SettingsCard(title: L10n.pick("Scoring Rules", "评分规则"), systemImage: "slider.horizontal.3") {
            HStack(spacing: 8) {
                rulesMetric(title: L10n.pick("Fields", "领域"),
                            value: "\(metadata.fields.count)",
                            systemImage: "square.grid.2x2",
                            tint: .blue)
                rulesMetric(title: L10n.pick("Venues", "会议"),
                            value: "\(metadata.venues.count)",
                            systemImage: "building.2",
                            tint: .indigo)
                rulesMetric(title: L10n.pick("Tiers", "等级"),
                            value: "\(metadata.tiers.count)",
                            systemImage: "rosette",
                            tint: .orange)
                rulesMetric(title: L10n.pick("Citation Ranges", "引用区间"),
                            value: "\(metadata.citationBreakpoints.count)",
                            systemImage: "quote.bubble",
                            tint: .teal)
            }

            Label(metadata.rulesDirty ? L10n.pick("Rules need applying", "规则待应用")
                                       : L10n.pick("Rules are applied", "规则已应用"),
                  systemImage: metadata.rulesDirty ? "exclamationmark.circle" : "checkmark.circle")
                .font(SettingsUI.smallFont)
                .foregroundStyle(metadata.rulesDirty ? .orange : .secondary)
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

            Button {
                exportRules()
            } label: {
                Label(L10n.pick("Export", "导出"), systemImage: "square.and.arrow.up")
            }

            Button {
                importRules()
            } label: {
                Label(L10n.pick("Import", "导入"), systemImage: "square.and.arrow.down")
            }

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

    private func rulesMetric(title: String, value: String, systemImage: String, tint: Color) -> some View {
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
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(FacetTheme.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}
