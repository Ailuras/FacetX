import SwiftUI

/// The shared shell for the context/action row at the top of every work
/// workspace.
struct WorkspaceActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: FacetTheme.workspaceSectionSpacing) {
            content
        }
        .frame(minHeight: FacetTheme.workspaceBarHeight, alignment: .center)
        .padding(.horizontal, FacetTheme.workspaceBarHorizontalPadding)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }
}

/// A compact, bordered group for related workspace actions. Separate groups
/// carry the visual spacing; buttons inside a group stay deliberately close.
struct WorkspaceActionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: FacetTheme.workspaceActionSpacing) {
            content
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FacetTheme.quietPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }
}

/// Label shared by buttons and borderless menus inside a workspace action
/// group. Active actions use the same accent treatment in every workspace.
struct WorkspaceActionIcon: View {
    let systemName: String
    var active = false
    var emphasized = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11.5, weight: .semibold))
            .frame(width: 26, height: FacetTheme.chipHeight)
            .contentShape(Rectangle())
            .facetHoverSurface(
                tint: active || emphasized ? Color.accentColor : .secondary,
                fill: active ? Color.accentColor.opacity(0.14)
                             : emphasized ? Color.accentColor.opacity(0.09) : Color.clear,
                hoverFill: active || emphasized ? Color.accentColor.opacity(0.19)
                                                 : Color.primary.opacity(0.055),
                stroke: active ? Color.accentColor.opacity(0.24) : Color.clear,
                hoverStroke: active || emphasized ? Color.accentColor.opacity(0.36)
                                                   : FacetTheme.hairline
            )
    }
}

struct WorkspaceActionButton: View {
    let systemName: String
    let help: String
    var active = false
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WorkspaceActionIcon(
                systemName: systemName,
                active: active,
                emphasized: emphasized
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension View {
    /// Compact group styling used by controls outside the four workspace
    /// headers where introducing a container view would disturb layout.
    func pillGroupContainer() -> some View {
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(FacetTheme.quietPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
    }
}
