import SwiftUI

// MARK: - Fields

struct FieldRulesCard: View {
    @Bindable var metadata: MetadataStore

    var body: some View {
        SettingsCard(title: L10n.pick("Fields", "领域"), systemImage: "square.grid.2x2",
                     subtitle: L10n.pick("Configure literature fields and their badge colors.",
                                         "配置文献领域及其徽章颜色。")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ruleColumn(L10n.pick("Name", "名称"))
                    ruleColumn(L10n.pick("Color", "颜色"), width: 152)
                    Spacer().frame(width: 20)
                }

                ForEach(metadata.fields) { field in
                    HStack(spacing: 8) {
                        if field.name == MetadataStore.othersField {
                            Text(MetadataStore.othersField)
                                .font(SettingsUI.rowFont)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(L10n.pick("Field", "领域"), text: nameBinding(for: field))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                        }

                        colorSwatchAndPicker(for: field)
                            .frame(width: 152)

                        if field.name == MetadataStore.othersField {
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)
                        } else {
                            deleteButton { metadata.deleteField(id: field.id) }
                        }
                    }
                }

                addButton(L10n.pick("Add Field", "添加领域")) {
                    metadata.addField()
                }
            }
        }
    }

    private func nameBinding(for field: FieldPref) -> Binding<String> {
        Binding(
            get: { metadata.fields.first(where: { $0.id == field.id })?.name ?? field.name },
            set: { metadata.renameField(id: field.id, to: $0) }
        )
    }

    private func colorBinding(for field: FieldPref) -> Binding<String> {
        Binding(
            get: {
                metadata.fields.first(where: { $0.id == field.id })?.color
                    ?? MetadataStore.defaultFieldColor(field.name)
                    ?? "teal"
            },
            set: { metadata.setFieldColor(id: field.id, colorName: $0) }
        )
    }

    /// Shows a live color swatch alongside the picker so the selected colour
    /// is always visible without opening the dropdown (macOS NSPopUpButton does
    /// not render SwiftUI Circle views in the collapsed button label).
    private func colorSwatchAndPicker(for field: FieldPref) -> some View {
        let binding = colorBinding(for: field)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LabelColor.color(named: binding.wrappedValue) ?? .teal)
                .frame(width: 14, height: 14)
            Picker("", selection: binding) {
                ForEach(LabelColor.allCases) { option in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(option.color)
                            .frame(width: 9, height: 9)
                        Text(option.title)
                    }
                    .tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Venue ratings

struct VenueRulesCard: View {
    @Bindable var metadata: MetadataStore

    var body: some View {
        SettingsCard(title: L10n.pick("Venue Ratings", "会议评级"), systemImage: "building.2",
                     subtitle: L10n.pick("Match a venue phrase to a field and tier; drives the score badge.",
                                         "将会议名匹配到领域与等级，决定评分徽章。")) {
            VStack(alignment: .leading, spacing: 8) {
                header
                // Use enumerated ForEach with index-based Bindings to avoid the
                // ForEach($array) binding crash when rows are deleted.
                ForEach(Array(metadata.venues.enumerated()), id: \.element.id) { idx, venue in
                    HStack(spacing: 8) {
                        TextField(L10n.pick("Abbr", "缩写"), text: Binding(
                            get: { idx < metadata.venues.count ? metadata.venues[idx].abbr : "" },
                            set: { if idx < metadata.venues.count { metadata.venues[idx].abbr = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder).frame(width: 70)

                        fieldPicker(selection: Binding(
                            get: {
                                guard idx < metadata.venues.count else { return MetadataStore.othersField }
                                return MetadataStore.normalizedField(metadata.venues[idx].field)
                                    ?? MetadataStore.othersField
                            },
                            set: { val in
                                guard idx < metadata.venues.count else { return }
                                metadata.venues[idx].field = val == MetadataStore.othersField ? nil : val
                            }
                        ))
                        .frame(width: 108)

                        TextField(L10n.pick("Match phrase", "匹配短语"), text: Binding(
                            get: { idx < metadata.venues.count ? metadata.venues[idx].phrase : "" },
                            set: { if idx < metadata.venues.count { metadata.venues[idx].phrase = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)

                        Picker("", selection: Binding(
                            get: { idx < metadata.venues.count ? metadata.venues[idx].tier : 3 },
                            set: { if idx < metadata.venues.count { metadata.venues[idx].tier = $0 } }
                        )) {
                            ForEach(1...5, id: \.self) { Text("T\($0)").tag($0) }
                        }
                        .labelsHidden().frame(width: 64)

                        deleteButton {
                            guard idx < metadata.venues.count else { return }
                            metadata.venues.remove(at: idx)
                        }
                    }
                }
                othersRow
                addButton(L10n.pick("Add Venue", "添加会议")) {
                    metadata.venues.append(VenuePref(abbr: "", phrase: "", tier: 3, field: nil))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ruleColumn(L10n.pick("Abbr", "缩写"), width: 70)
            ruleColumn(L10n.pick("Field", "领域"), width: 108)
            ruleColumn(L10n.pick("Match phrase", "匹配短语"))
            ruleColumn(L10n.pick("Tier", "等级"), width: 64)
            Spacer().frame(width: 20)
        }
    }

    /// The fixed fallback used when no venue rule matches. It can't be deleted and
    /// has no field or phrase — only its tier is configurable.
    private var othersRow: some View {
        HStack(spacing: 8) {
            Text("Others")
                .font(SettingsUI.rowFont)
                .padding(.leading, 10)
                .frame(width: 70, alignment: .leading)
            fieldBadge(MetadataStore.othersField)
                .frame(width: 108, alignment: .leading)
            Text(L10n.pick("Fallback for unmatched venues", "未匹配会议的兜底"))
                .font(SettingsUI.secondaryFont)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: $metadata.othersTier) {
                Text(L10n.pick("None", "无")).tag(0)
                ForEach(1...5, id: \.self) { Text("T\($0)").tag($0) }
            }
            .labelsHidden().frame(width: 64)
            Image(systemName: "lock")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
        }
        .padding(.vertical, 4)
        .background(FacetTheme.panel.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func fieldPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(metadata.allFields, id: \.self) { field in
                Text(field).tag(field)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func fieldBadge(_ field: String) -> some View {
        Text(field)
            .font(SettingsUI.smallFont.weight(.semibold))
            .foregroundStyle(metadata.fieldColor(field))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(metadata.fieldColor(field).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Tiers

struct TierRulesCard: View {
    @Bindable var metadata: MetadataStore

    var body: some View {
        SettingsCard(title: L10n.pick("Tier Points", "等级分值"), systemImage: "rosette",
                     subtitle: L10n.pick("Points awarded for each venue tier.",
                                         "各会议等级对应的分值。")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ruleColumn(L10n.pick("Rank", "等级"), width: 44)
                    ruleColumn(L10n.pick("Name", "名称"))
                    ruleColumn(L10n.pick("Points", "分值"), width: 64)
                    Spacer().frame(width: 20)
                }
                ForEach($metadata.tiers) { $tier in
                    HStack(spacing: 8) {
                        Text("\(tier.rank)").monospacedDigit().frame(width: 44, alignment: .leading)
                        TextField(L10n.pick("Name", "名称"), text: $tier.name)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        TextField("", value: $tier.points, format: .number)
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 64)
                        deleteButton { metadata.tiers.removeAll { $0.rank == tier.rank } }
                    }
                }
                addButton(L10n.pick("Add Tier", "添加等级")) {
                    let next = (metadata.tiers.map(\.rank).max() ?? 0) + 1
                    metadata.tiers.append(TierPref(rank: next, name: "Tier \(next)",
                                                   points: max(1, 12 - 2 * next), color: nil,
                                                   sortOrder: metadata.tiers.count))
                }
            }
        }
    }
}

// MARK: - Citation scoring

struct CitationRulesCard: View {
    @Bindable var metadata: MetadataStore

    var body: some View {
        SettingsCard(title: L10n.pick("Citation Scoring", "引用评分"), systemImage: "quote.bubble",
                     subtitle: L10n.pick("Points per citation across ranges, capped at a maximum.",
                                         "按区间为每次引用计分，并设置上限。")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ruleColumn(L10n.pick("Up to (citations)", "上限（引用数）"))
                    ruleColumn(L10n.pick("Points / citation", "每次引用分值"))
                    Spacer().frame(width: 20)
                }
                // Use enumerated ForEach with index-based Bindings to prevent
                // the crash that occurs when ForEach($array) element bindings
                // are accessed after their element has been removed.
                ForEach(Array(metadata.citationBreakpoints.enumerated()), id: \.element.id) { idx, _ in
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: {
                                guard idx < metadata.citationBreakpoints.count else { return 1 }
                                return metadata.citationBreakpoints[idx].up_to ?? 1
                            },
                            set: {
                                guard idx < metadata.citationBreakpoints.count else { return }
                                metadata.citationBreakpoints[idx].up_to = max(1, $0)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(maxWidth: .infinity)

                        TextField("", value: Binding(
                            get: {
                                guard idx < metadata.citationBreakpoints.count else { return 0.0 }
                                return metadata.citationBreakpoints[idx].points_per_citation
                            },
                            set: {
                                guard idx < metadata.citationBreakpoints.count else { return }
                                metadata.citationBreakpoints[idx].points_per_citation = $0
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(maxWidth: .infinity)

                        deleteButton {
                            guard idx < metadata.citationBreakpoints.count else { return }
                            metadata.citationBreakpoints.remove(at: idx)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.to.line.compact").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.pick("Max citation points", "引用分上限")).font(SettingsUI.secondaryFont)
                    Spacer()
                    TextField("", value: $metadata.maxCitationPoints, format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 72)
                }
                addButton(L10n.pick("Add Breakpoint", "添加区间")) {
                    let next = (metadata.citationBreakpoints.compactMap(\.up_to).max() ?? 0) + 50
                    metadata.citationBreakpoints.append(CitationBreakpoint(up_to: next, points_per_citation: 0.1))
                }
            }
        }
    }
}

// MARK: - Shared chrome

@ViewBuilder
func ruleColumn(_ title: String, width: CGFloat? = nil) -> some View {
    Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary.opacity(0.85))
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
}

@ViewBuilder
@MainActor
func addButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: "plus.circle.fill").font(.system(size: 12, weight: .medium))
    }
    .buttonStyle(.borderless).controlSize(.small).padding(.top, 2)
}

@ViewBuilder
@MainActor
func deleteButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "trash").font(.system(size: 12))
    }
    .buttonStyle(.borderless).foregroundStyle(.secondary).frame(width: 20)
}
