import SwiftUI

// MARK: - Venue ratings

struct VenueRulesCard: View {
    @Bindable var metadata: MetadataStore

    var body: some View {
        SettingsCard(title: L10n.pick("Venue Ratings", "会议评级"), systemImage: "building.2",
                     subtitle: L10n.pick("Match a venue phrase to a field and tier; drives the score badge.",
                                         "将会议名匹配到领域与等级，决定评分徽章。")) {
            VStack(alignment: .leading, spacing: 8) {
                header
                ForEach($metadata.venues) { $venue in
                    HStack(spacing: 8) {
                        TextField(L10n.pick("Abbr", "缩写"), text: $venue.abbr)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        TextField(L10n.pick("Field", "领域"), text: fieldBinding(for: $venue))
                            .textFieldStyle(.roundedBorder).frame(width: 96)
                        TextField(L10n.pick("Match phrase", "匹配短语"), text: $venue.phrase)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        Picker("", selection: $venue.tier) {
                            ForEach(1...5, id: \.self) { Text("T\($0)").tag($0) }
                        }
                        .labelsHidden().frame(width: 64)
                        deleteButton { metadata.venues.removeAll { $0.id == venue.id } }
                    }
                }
                addButton(L10n.pick("Add Venue", "添加会议")) {
                    metadata.venues.append(VenuePref(abbr: "", phrase: "", tier: 3, field: nil))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ruleColumn(L10n.pick("Abbr", "缩写"), width: 70)
            ruleColumn(L10n.pick("Field", "领域"), width: 96)
            ruleColumn(L10n.pick("Match phrase", "匹配短语"))
            ruleColumn(L10n.pick("Tier", "等级"), width: 64)
            Spacer().frame(width: 20)
        }
    }

    private func fieldBinding(for venue: Binding<VenuePref>) -> Binding<String> {
        Binding(
            get: { venue.wrappedValue.field ?? "" },
            set: { venue.wrappedValue.field = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
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
                    ruleColumn(L10n.pick("Up to (citations)", "上限（引用数）"), width: 150)
                    ruleColumn(L10n.pick("Points / citation", "每次引用分值"), width: 110)
                    Spacer().frame(width: 20)
                }
                ForEach(metadata.citationBreakpoints.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            if metadata.citationBreakpoints[index].up_to != nil {
                                TextField("", value: upToBinding(index), format: .number)
                                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 90)
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: "infinity")
                                    Text(L10n.pick("No cap", "无上限"))
                                }
                                .font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            }
                            Button {
                                metadata.citationBreakpoints[index].up_to =
                                    metadata.citationBreakpoints[index].up_to == nil ? 100 : nil
                            } label: {
                                Image(systemName: metadata.citationBreakpoints[index].up_to == nil ? "number" : "infinity")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                        .frame(width: 150, alignment: .leading)
                        TextField("", value: pointsBinding(index), format: .number)
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 110)
                        deleteButton { metadata.citationBreakpoints.remove(at: index) }
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
                    metadata.citationBreakpoints.append(CitationBreakpoint(up_to: nil, points_per_citation: 1.0))
                }
            }
        }
    }

    private func upToBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { metadata.citationBreakpoints[index].up_to ?? 0 },
                set: { metadata.citationBreakpoints[index].up_to = $0 })
    }

    private func pointsBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { metadata.citationBreakpoints[index].points_per_citation },
                set: { metadata.citationBreakpoints[index].points_per_citation = $0 })
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
func addButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: "plus.circle.fill").font(.system(size: 12, weight: .medium))
    }
    .buttonStyle(.borderless).controlSize(.small).padding(.top, 2)
}

@ViewBuilder
func deleteButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "trash").font(.system(size: 12))
    }
    .buttonStyle(.borderless).foregroundStyle(.secondary).frame(width: 20)
}
