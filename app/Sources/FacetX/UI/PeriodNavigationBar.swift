import SwiftUI

struct PeriodNavigationBar<Leading: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let previousHelp: String
    let nextHelp: String
    let currentHelp: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCurrent: () -> Void
    private let leading: Leading
    private let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        previousHelp: String,
        nextHelp: String,
        currentHelp: String,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onCurrent: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.previousHelp = previousHelp
        self.nextHelp = nextHelp
        self.currentHelp = currentHelp
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onCurrent = onCurrent
        self.leading = leading()
        self.accessory = accessory()
    }

    var body: some View {
        WorkspaceActionBar {
            leading

            Spacer()

            HStack(spacing: FacetTheme.workspaceActionGroupSpacing) {
                navCluster
                accessory
            }
        }
        .overlay(alignment: .center) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navCluster: some View {
        WorkspaceActionGroup {
            pillIconButton(systemName: "chevron.left", help: previousHelp, action: onPrevious)
            pillIconButton(systemName: "chevron.right", help: nextHelp, action: onNext)
            pillTextButton(L10n.pick("Current", "当前"), help: currentHelp, action: onCurrent)
        }
        .frame(width: 112, alignment: .leading)
    }

    private func pillIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WorkspaceActionIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pillTextButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 52, height: 24)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.clear,
                                   hoverFill: Color.primary.opacity(0.055),
                                   hoverStroke: FacetTheme.hairline)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
