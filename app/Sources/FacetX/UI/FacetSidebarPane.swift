import SwiftUI

enum FacetSidebarStyle {
    static let width: CGFloat = 340
    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 620
    static let contentInset: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let padding = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    static var contentWidth: CGFloat {
        width - contentInset * 2
    }
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}

struct FacetSidebarPane<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let closeHelp: String
    let onClose: () -> Void
    /// When true the pane fills the available width (used by the note fullscreen
    /// mode) instead of its fixed, draggable width.
    let fillWidth: Bool
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        systemImage: String,
        closeHelp: String = L10n.pick("Close sidebar", "关闭侧栏"),
        fillWidth: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.closeHelp = closeHelp
        self.fillWidth = fillWidth
        self.onClose = onClose
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            FacetSidebarHeader(
                title: title,
                systemImage: systemImage,
                closeHelp: closeHelp,
                onClose: onClose,
                accessory: { accessory }
            )

            Divider()

            content
        }
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .resizableSidebarWidth(
            storageKey: "facetSidebarPaneWidth",
            defaultWidth: FacetSidebarStyle.width,
            minWidth: FacetSidebarStyle.minWidth,
            maxWidth: FacetSidebarStyle.maxWidth,
            handleEdge: .leading,
            disabled: fillWidth
        )
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: FacetSidebarStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetSidebarStyle.cornerRadius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(FacetSidebarStyle.padding)
        .transition(FacetSidebarStyle.transition)
    }
}

extension FacetSidebarPane where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        closeHelp: String = L10n.pick("Close sidebar", "关闭侧栏"),
        fillWidth: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            closeHelp: closeHelp,
            fillWidth: fillWidth,
            onClose: onClose,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct FacetSidebarHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    let closeHelp: String
    let onClose: () -> Void
    let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        closeHelp: String,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.closeHelp = closeHelp
        self.onClose = onClose
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            accessory

            Button(action: onClose) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(closeHelp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension View {
    func resizableSidebarWidth(storageKey: String,
                               defaultWidth: CGFloat,
                               minWidth: CGFloat,
                               maxWidth: CGFloat,
                               handleEdge: HorizontalEdge,
                               disabled: Bool = false) -> some View {
        modifier(ResizableSidebarWidthModifier(
            storageKey: storageKey,
            defaultWidth: defaultWidth,
            minWidth: minWidth,
            maxWidth: maxWidth,
            handleEdge: handleEdge,
            disabled: disabled
        ))
    }
}

private struct ResizableSidebarWidthModifier: ViewModifier {
    let defaultWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let handleEdge: HorizontalEdge
    let disabled: Bool

    @AppStorage private var storedWidth: Double
    @State private var dragWidth: Double?
    @State private var dragStartWidth: Double?

    init(storageKey: String,
         defaultWidth: CGFloat,
         minWidth: CGFloat,
         maxWidth: CGFloat,
         handleEdge: HorizontalEdge,
         disabled: Bool) {
        self.defaultWidth = defaultWidth
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.handleEdge = handleEdge
        self.disabled = disabled
        self._storedWidth = AppStorage(wrappedValue: Double(defaultWidth), storageKey)
    }

    func body(content: Content) -> some View {
        if disabled {
            content
        } else {
            content
                .frame(width: clampedWidth)
                .overlay(alignment: handleEdge == .leading ? .leading : .trailing) {
                    resizeHandle
                }
        }
    }

    private var clampedWidth: CGFloat {
        let raw = dragWidth ?? storedWidth
        return min(max(CGFloat(raw), minWidth), maxWidth)
    }

    /// The drag is measured in global coordinates; a local coordinate space would
    /// move with the handle as the pane resizes and feed jitter back into itself.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragStartWidth ?? storedWidth
                        if dragStartWidth == nil { dragStartWidth = base }
                        let delta = handleEdge == .leading
                            ? -Double(value.translation.width)
                            : Double(value.translation.width)
                        dragWidth = min(max(base + delta, Double(minWidth)), Double(maxWidth))
                    }
                    .onEnded { _ in
                        if let dragWidth { storedWidth = dragWidth }
                        dragWidth = nil
                        dragStartWidth = nil
                    }
            )
    }
}
