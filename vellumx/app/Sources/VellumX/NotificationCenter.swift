import SwiftUI

// MARK: - NotificationCenter

@MainActor
@Observable
final class NotificationCenter {
    static let shared = NotificationCenter()

    // MARK: Alert
    var currentAlert: AlertItem? {
        didSet {
            alertIsPresented = currentAlert != nil
        }
    }
    var alertIsPresented = false

    // MARK: Toast
    var toasts: [ToastItem] = []
    private let maxToasts = 3

    // MARK: Status
    var statusMessage: String = ""
    var statusType: StatusType = .neutral

    // MARK: - Alert

    func present(_ alert: AlertItem) {
        currentAlert = alert
    }

    func presentAlert(title: String, message: String? = nil,
                      primary: AlertAction, secondary: AlertAction? = nil) {
        var actions = [primary]
        if let secondary { actions.append(secondary) }
        currentAlert = AlertItem(
            title: title, message: message, actions: actions,
            textFieldValue: nil, textFieldLabel: nil
        )
    }

    func presentPrompt(title: String, label: String,
                       primary: AlertAction, secondary: AlertAction? = nil) {
        var actions = [primary]
        if let secondary { actions.append(secondary) }
        currentAlert = AlertItem(
            title: title, message: nil, actions: actions,
            textFieldValue: "", textFieldLabel: label
        )
    }

    func dismissAlert() {
        currentAlert = nil
    }

    // MARK: - Toast

    func showToast(_ message: String, type: ToastType = .success, duration: TimeInterval = 2.5) {
        let toast = ToastItem(message: message, type: type, duration: duration)
        toasts.insert(toast, at: 0)
        if toasts.count > maxToasts {
            toasts.removeLast(toasts.count - maxToasts)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            removeToast(id: toast.id)
        }
    }

    func removeToast(id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Status

    func setStatus(_ message: String, type: StatusType = .neutral) {
        statusMessage = message
        statusType = type
    }

    func clearStatus() {
        statusMessage = ""
        statusType = .neutral
    }
}

// MARK: - Alert Types

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let actions: [AlertAction]
    var textFieldValue: String?
    let textFieldLabel: String?
}

enum AlertAction {
    case confirm(String, isDestructive: Bool = false, action: () -> Void)
    case cancel(String, action: (() -> Void)? = nil)
    case plain(String, action: () -> Void)
}

// MARK: - Toast Types

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum ToastType {
    case success, error, warning, info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue
        }
    }
}

// MARK: - Status Types

enum StatusType {
    case neutral, success, error, progress

    var color: Color {
        switch self {
        case .neutral:  return .secondary
        case .success:  return .green
        case .error:    return .red
        case .progress: return .blue
        }
    }
}

// MARK: - LocalAlertCenter

/// A window-scoped alert presenter. The global `NotificationCenter` alert host
/// lives on the main window, so alerts triggered from another window (the
/// Settings window) would be presented on — and pull focus to — the main
/// window, leaving the originating window buried. A window that owns one of
/// these and installs `.localAlertHost(_:)` keeps its own confirmations on
/// itself.
@MainActor
@Observable
final class LocalAlertCenter {
    var currentAlert: AlertItem? {
        didSet { alertIsPresented = currentAlert != nil }
    }
    var alertIsPresented = false

    func present(_ alert: AlertItem) { currentAlert = alert }
    func dismiss() { currentAlert = nil }
}

// MARK: - Alert Host

/// Shared rendering for an `AlertItem` channel. Both the global main-window host
/// and any window-local host (Settings) bind their state into this so the alert
/// look and action handling stay identical.
private struct AlertHost: ViewModifier {
    @Binding var current: AlertItem?
    @Binding var isPresented: Bool
    let onResolve: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(current?.title ?? "", isPresented: $isPresented, presenting: current) { item in
                if let label = item.textFieldLabel {
                    TextField(label, text: Binding(
                        get: { current?.textFieldValue ?? "" },
                        set: { current?.textFieldValue = $0 }
                    ))
                }
                ForEach(0..<item.actions.count, id: \.self) { idx in
                    Button(role: Self.role(item.actions[idx])) {
                        run(item.actions[idx])
                    } label: {
                        Text(Self.label(item.actions[idx]))
                    }
                }
            } message: { item in
                if let message = item.message {
                    Text(message)
                }
            }
    }

    private func run(_ action: AlertAction) {
        switch action {
        case .confirm(_, _, let action): action()
        case .cancel(_, let action):     action?()
        case .plain(_, let action):      action()
        }
        onResolve()
    }

    private static func label(_ action: AlertAction) -> String {
        switch action {
        case .confirm(let label, _, _): return label
        case .cancel(let label, _):     return label
        case .plain(let label, _):      return label
        }
    }

    private static func role(_ action: AlertAction) -> ButtonRole? {
        switch action {
        case .confirm(_, let isDestructive, _): return isDestructive ? .destructive : nil
        case .cancel:                           return .cancel
        case .plain:                            return nil
        }
    }
}

// MARK: - Alert host modifiers

struct UnifiedAlertModifier: ViewModifier {
    @State private var nc = NotificationCenter.shared

    func body(content: Content) -> some View {
        content.modifier(AlertHost(
            current: $nc.currentAlert,
            isPresented: $nc.alertIsPresented,
            onResolve: { nc.dismissAlert() }
        ))
    }
}

private struct LocalAlertHostModifier: ViewModifier {
    @Bindable var center: LocalAlertCenter

    func body(content: Content) -> some View {
        content.modifier(AlertHost(
            current: $center.currentAlert,
            isPresented: $center.alertIsPresented,
            onResolve: { center.dismiss() }
        ))
    }
}

extension View {
    func unifiedAlert() -> some View {
        modifier(UnifiedAlertModifier())
    }

    /// Host a window-local alert channel (see `LocalAlertCenter`).
    func localAlertHost(_ center: LocalAlertCenter) -> some View {
        modifier(LocalAlertHostModifier(center: center))
    }
}

// MARK: - Settings alert environment

/// Lets Settings tabs present confirmations on the Settings window's own
/// `LocalAlertCenter` instead of the global (main-window) host.
private struct SettingsAlertsKey: EnvironmentKey {
    static let defaultValue: LocalAlertCenter? = nil
}

extension EnvironmentValues {
    var settingsAlerts: LocalAlertCenter? {
        get { self[SettingsAlertsKey.self] }
        set { self[SettingsAlertsKey.self] = newValue }
    }
}

// MARK: - Toast Views

struct ToastView: View {
    let toast: ToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toast.type.color)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 4)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .offset(y: 8))
        ))
        .onTapGesture {
            onDismiss()
        }
    }
}

struct ToastContainer: View {
    @State private var nc = NotificationCenter.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(nc.toasts) { toast in
                ToastView(toast: toast) {
                    nc.removeToast(id: toast.id)
                }
            }
        }
        .animation(.spring(duration: 0.35), value: nc.toasts)
        .padding(.bottom, 16)
        .padding(.trailing, 16)
    }
}

// MARK: - StatusBar

struct StatusBar: View {
    let message: String
    let type: StatusType

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                if type == .progress {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(type.color)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - GlobalStatusBar

struct GlobalStatusBar: View {
    @State private var nc = NotificationCenter.shared

    var body: some View {
        Group {
            if !nc.statusMessage.isEmpty {
                StatusBar(message: nc.statusMessage, type: nc.statusType)
            }
        }
    }
}
