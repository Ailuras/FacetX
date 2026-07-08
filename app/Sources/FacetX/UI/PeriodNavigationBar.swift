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
        HStack(spacing: 12) {
            leading

            Spacer()

            HStack(spacing: 10) {
                navCluster
                accessory
            }
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
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
        HStack(spacing: 2) {
            pillIconButton(systemName: "chevron.left", help: previousHelp, action: onPrevious)
            pillIconButton(systemName: "chevron.right", help: nextHelp, action: onNext)
            pillTextButton(L10n.pick("Current", "当前"), help: currentHelp, action: onCurrent)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func pillIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.clear,
                                   hoverFill: Color.primary.opacity(0.055),
                                   hoverStroke: FacetTheme.hairline)
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
