import SwiftUI
import UniformTypeIdentifiers

struct RulesSettingsTab: View {
    @State private var metadata = MetadataStore.shared
    @Environment(\.settingsAlerts) private var alerts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RuleSection(title: L10n.t(.interestsTracks),
                            icon: "scope",
                            hint: L10n.t(.tracksHint)) {
                    TopicsSummaryList(metadata: metadata)
                }

                RuleSection(title: L10n.t(.venueRatings),
                            icon: "building.2",
                            hint: L10n.t(.venuesHint)) {
                    VenuesEditor(venues: $metadata.venues, availableFields: metadata.allFields)
                }

                RuleSection(title: L10n.t(.tierSettings),
                            icon: "rosette",
                            hint: L10n.t(.tiersHint)) {
                    TiersEditor(tiers: $metadata.tiers)
                }

                RuleSection(title: L10n.t(.citationScoring),
                            icon: "quote.bubble",
                            hint: L10n.t(.citationScoringHint)) {
                    CitationCurveEditor(
                        breakpoints: $metadata.citationBreakpoints,
                        maxPoints: $metadata.maxCitationPoints
                    )
                }

                Divider()

                // Apply (recompute library) | Import / Export / Preset
                HStack(spacing: 12) {
                    Button {
                        let changed = PaperStore.shared.refreshVenueMetadata()
                        metadata.markRulesApplied()
                        NotificationCenter.shared.showToast("\(L10n.t(.venueChangesApplied)) \(changed)", type: .success)
                    } label: {
                        Label(L10n.t(.applyChanges), systemImage: "arrow.clockwise")
                    }
                    .tint(.accentColor)
                    .disabled(!metadata.rulesDirty)
                    .help(L10n.t(.applyChangesHint))

                    Spacer()

                    Button {
                        importRules()
                    } label: {
                        Label(L10n.t(.importRules), systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportRules()
                    } label: {
                        Label(L10n.t(.exportRules), systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        alerts?.present(AlertItem(
                            title: L10n.t(.usePresetTitle),
                            message: L10n.t(.usePresetMessage),
                            actions: [
                                .confirm(L10n.t(.confirm), isDestructive: true, action: {
                                    metadata.resetToPreset()
                                }),
                                .cancel(L10n.t(.cancel))
                            ],
                            textFieldValue: nil, textFieldLabel: nil
                        ))
                    } label: {
                        Label(L10n.t(.usePreset), systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .padding(20)
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try metadata.importMetadata(from: data)
            NotificationCenter.shared.showToast(L10n.t(.importSuccess), type: .success)
        } catch {
            NotificationCenter.shared.showToast("\(L10n.t(.importFailed)) \(error.localizedDescription)", type: .error)
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vellumx-rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try metadata.exportMetadata()
            try data.write(to: url, options: .atomic)
            NotificationCenter.shared.showToast("Exported to \(url.lastPathComponent)", type: .success)
        } catch {
            NotificationCenter.shared.showToast("\(L10n.t(.importFailed)) \(error.localizedDescription)", type: .error)
        }
    }
}

// MARK: - Shared section chrome

/// A unified card for each rules group: an icon + title header, an optional
/// one-line hint, then the editor content. Replaces the bare GroupBoxes so
/// every section on this page shares one look.
private struct RuleSection<Content: View>: View {
    let title: String
    let icon: String
    var hint: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
        )
    }
}

/// Small-caps column header shared by the table-style editors.
private struct RuleColumnHeader: View {
    let title: String
    var width: CGFloat? = nil
    var alignment: Alignment = .leading

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.85))
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// Consistent "+ Add …" affordance used at the bottom of every editor.
private struct AddRuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.top, 2)
    }
}

/// Trash button that always asks for confirmation before deleting. `name`, when
/// present, is shown in the prompt title so the user knows exactly what goes.
private struct RuleDeleteButton: View {
    @Environment(\.settingsAlerts) private var alerts
    var name: String? = nil
    let perform: () -> Void

    var body: some View {
        Button {
            confirmRuleDelete(on: alerts, name: name, perform: perform)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(L10n.t(.delete))
    }
}

@MainActor
private func confirmRuleDelete(on alerts: LocalAlertCenter?, name: String?, perform: @escaping () -> Void) {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = trimmed.isEmpty
        ? L10n.t(.deleteRuleTitle)
        : L10n.pick("Delete \"\(trimmed)\"?", "删除 “\(trimmed)”？")
    alerts?.present(AlertItem(
        title: title,
        message: L10n.t(.deleteRuleMessage),
        actions: [
            .confirm(L10n.t(.delete), isDestructive: true, action: perform),
            .cancel(L10n.t(.cancel))
        ],
        textFieldValue: nil, textFieldLabel: nil
    ))
}

// MARK: - TiersEditor

struct TiersEditor: View {
    @Binding var tiers: [TierPref]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RuleColumnHeader(title: L10n.t(.tierRank), width: 44)
                RuleColumnHeader(title: L10n.t(.name))
                RuleColumnHeader(title: L10n.t(.tierPointsValue), width: 64)
                Spacer().frame(width: 22)
            }

            ForEach($tiers) { $tier in
                HStack(spacing: 8) {
                    Text("\(tier.rank)")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                    TextField(L10n.t(.name), text: $tier.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                    TextField("", value: $tier.points, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 64)
                    RuleDeleteButton(name: tier.name) {
                        tiers.removeAll { $0.rank == tier.rank }
                    }
                }
            }

            AddRuleButton(title: L10n.t(.addTier)) {
                let nextRank = (tiers.map(\.rank).max() ?? 0) + 1
                tiers.append(TierPref(
                    rank: nextRank,
                    name: "Tier \(nextRank)",
                    points: max(1, 12 - 2 * nextRank),
                    color: nil,
                    sortOrder: tiers.count
                ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CitationCurveEditor

struct CitationCurveEditor: View {
    @Binding var breakpoints: [CitationBreakpoint]
    @Binding var maxPoints: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if breakpoints.isEmpty {
                emptyState
            } else {
                segmentTable
                Divider().padding(.vertical, 2)
                maxPointsRow
            }

            AddRuleButton(title: L10n.t(.addBreakpoint)) {
                breakpoints.append(CitationBreakpoint(up_to: nil, points_per_citation: 1.0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(L10n.t(.noBreakpoints))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private var segmentTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RuleColumnHeader(title: L10n.t(.breakpointUpTo), width: 132)
                RuleColumnHeader(title: L10n.t(.pointsPerCitation), width: 72)
                Spacer()
            }

            ForEach(breakpoints.indices, id: \.self) { index in
                segmentRow(index)
            }
        }
    }

    private func segmentRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            // "Up to" cell: a number field with an inline cap toggle. Tapping the
            // toggle flips between a hard cap and the open-ended (∞) tail segment.
            HStack(spacing: 6) {
                if breakpoints[index].up_to != nil {
                    TextField("", value: upToBinding(for: index), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 88)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                        Text(L10n.t(.noCap))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .leading)
                }

                Button {
                    if breakpoints[index].up_to != nil {
                        breakpoints[index].up_to = nil
                    } else {
                        breakpoints[index].up_to = 100
                    }
                } label: {
                    Image(systemName: breakpoints[index].up_to != nil ? "infinity" : "number")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(breakpoints[index].up_to != nil ? L10n.t(.noCap) : L10n.t(.breakpointUpTo))
            }
            .frame(width: 132, alignment: .leading)

            TextField("", value: $breakpoints[index].points_per_citation, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 72)

            Spacer()

            RuleDeleteButton {
                breakpoints.remove(at: index)
            }
        }
    }

    private var maxPointsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.to.line.compact")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(L10n.t(.maxCitationPointsLabel))
                .font(.subheadline)
            Spacer()
            TextField("", value: $maxPoints, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }

    private func upToBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { breakpoints[index].up_to ?? 0 },
            set: { breakpoints[index].up_to = $0 }
        )
    }
}

// MARK: - TopicsSummaryList

/// Compact, read-only topic list for the Rules tab. Each row opens the shared
/// `TopicEditor`; "Add Topic" creates a new one. Editing lives in the sidebar
/// and this editor — there is no inline editing here — but topics stay part of
/// the metadata so Export Rules continues to include them.
struct TopicsSummaryList: View {
    @Bindable var metadata: MetadataStore
    @State private var topicSheet: TopicEditTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if metadata.topics.isEmpty {
                Text(L10n.t(.noTracks)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(metadata.topics) { topic in
                Button { topicSheet = .edit(topic) } label: {
                    HStack(spacing: 9) {
                        TopicBadge(color: topic.resolvedColor, icon: topic.displayIcon, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(topic.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            if !topic.query.isEmpty {
                                Text(topic.query)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if topic.archived {
                            Text(L10n.pick("Archived", "已归档"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .opacity(topic.archived ? 0.6 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            AddRuleButton(title: L10n.t(.addTrack)) {
                topicSheet = .new
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $topicSheet) { sheet in
            TopicEditor(existing: sheet.existing)
        }
    }
}

// MARK: - VenuesEditor

struct VenuesEditor: View {
    @Environment(\.settingsAlerts) private var alerts
    @Binding var venues: [VenuePref]
    /// Selectable field options (custom fields + the built-in "Others", last).
    let availableFields: [String]

    /// The venue currently having a brand-new field named via the prompt.
    @State private var newFieldVenueID: UUID?

    private let othersField = MetadataStore.othersField

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if venues.isEmpty {
                Text(L10n.t(.noVenues)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                RuleColumnHeader(title: L10n.t(.abbr), width: 64)
                RuleColumnHeader(title: L10n.t(.field), width: 110)
                RuleColumnHeader(title: L10n.t(.matchPhrase))
                RuleColumnHeader(title: L10n.t(.tier), width: 84)
                Spacer().frame(width: 22)
            }
            ForEach($venues) { $venue in
                HStack(spacing: 8) {
                    TextField(L10n.t(.abbr), text: $venue.abbr)
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                    fieldMenu(for: $venue).frame(width: 110)
                    TextField(L10n.t(.matchPhrase), text: $venue.phrase)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    Picker("", selection: $venue.tier) {
                        ForEach(1...5, id: \.self) { Text("\(L10n.t(.tier)) \($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 84)
                    RuleDeleteButton(name: venue.abbr.isEmpty ? venue.phrase : venue.abbr) {
                        venues.removeAll { $0.id == venue.id }
                    }
                }
            }
            AddRuleButton(title: L10n.t(.addVenue)) {
                venues.append(VenuePref(abbr: "", phrase: "", tier: 3, field: nil))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A field is "Others" (the catch-all) whenever no custom field is set.
    private func fieldMenu(for venue: Binding<VenuePref>) -> some View {
        let raw = venue.wrappedValue.field?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let current = raw.isEmpty ? othersField : raw
        let customFields = availableFields.filter { $0 != othersField }

        return Menu {
            fieldChoice(othersField, isSelected: current == othersField) {
                venue.wrappedValue.field = nil
            }
            if !customFields.isEmpty {
                Divider()
                ForEach(customFields, id: \.self) { name in
                    fieldChoice(name, isSelected: current == name) {
                        venue.wrappedValue.field = name
                    }
                }
            }
            Divider()
            Button {
                presentNewFieldPrompt(for: venue.wrappedValue.id)
            } label: { Label(L10n.t(.newField), systemImage: "plus") }
        } label: {
            // Fill the column so every field box is the same width and looks
            // like a uniform popup button (the default Menu hugs its text).
            HStack(spacing: 4) {
                Text(current).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 21)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func fieldChoice(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    private func presentNewFieldPrompt(for venueID: UUID) {
        newFieldVenueID = venueID
        let center = alerts
        center?.present(AlertItem(
            title: L10n.t(.newField),
            message: nil,
            actions: [
                .confirm(L10n.t(.confirm), action: {
                    let name = center?.currentAlert?.textFieldValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.commitNewField(name: name)
                }),
                .cancel(L10n.t(.cancel), action: { self.newFieldVenueID = nil })
            ],
            textFieldValue: "",
            textFieldLabel: L10n.t(.name)
        ))
    }

    private func commitNewField(name: String) {
        defer { newFieldVenueID = nil }
        guard !name.isEmpty, name.caseInsensitiveCompare(othersField) != .orderedSame,
              let id = newFieldVenueID,
              let index = venues.firstIndex(where: { $0.id == id }) else { return }
        venues[index].field = name
    }
}
