import SwiftUI
import Combine

/// A single toast notification.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    let action: ToastAction?

    static func == (lhs: Toast, rhs: Toast) -> Bool {
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

struct ToastAction: Identifiable {
    let id = UUID()
    let title: String
    let handler: () -> Void
}

/// A persistent banner notification shown at the top of the window.
struct Banner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: BannerType
    let action: BannerAction?

    static func == (lhs: Banner, rhs: Banner) -> Bool {
        lhs.id == rhs.id
    }
}

enum BannerType {
    case error, warning, info

    var icon: String {
        switch self {
        case .error:   return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .error:   return Color.red.opacity(0.10)
        case .warning: return Color.orange.opacity(0.10)
        case .info:    return Color.blue.opacity(0.10)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue
        }
    }
}

struct BannerAction: Identifiable {
    let id = UUID()
    let title: String
    let handler: () -> Void
}

/// Central controller for all in-app notifications (toasts and banners).
///
/// Injected as an `@EnvironmentObject` at the app root so any view or
/// service can enqueue feedback without needing a binding.
@MainActor
final class ToastController: ObservableObject {
    @Published private(set) var toasts: [Toast] = []
    @Published private(set) var banner: Banner?

    /// Maximum number of toasts visible at once.
    private let maxVisibleToasts = 3

    /// Queue for toasts that exceed the visible limit.
    private var toastQueue: [Toast] = []

    /// Track active timers so they can be cancelled if a toast is manually dismissed.
    private var toastTimers: [UUID: Timer] = [:]

    // MARK: - Public API

    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 3, action: ToastAction? = nil) {
        let toast = Toast(message: message, type: type, duration: duration, action: action)

        if toasts.count < maxVisibleToasts {
            insertToast(toast)
        } else {
            toastQueue.append(toast)
        }
    }

    func showBanner(_ message: String, type: BannerType = .info, action: BannerAction? = nil) {
        withAnimation(.easeInOut(duration: 0.25)) {
            banner = Banner(message: message, type: type, action: action)
        }
    }

    func dismissBanner() {
        withAnimation(.easeInOut(duration: 0.20)) {
            banner = nil
        }
    }

    func dismiss(_ id: UUID) {
        // Cancel timer if any
        toastTimers[id]?.invalidate()
        toastTimers.removeValue(forKey: id)

        withAnimation(.easeInOut(duration: 0.20)) {
            toasts.removeAll { $0.id == id }
        }

        // Pull from queue if there's room
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            if !self.toastQueue.isEmpty, self.toasts.count < self.maxVisibleToasts {
                let next = self.toastQueue.removeFirst()
                self.insertToast(next)
            }
        }
    }

    /// Dismiss all toasts and banners. Useful when switching major contexts.
    func dismissAll() {
        toastTimers.values.forEach { $0.invalidate() }
        toastTimers.removeAll()
        toastQueue.removeAll()

        withAnimation(.easeInOut(duration: 0.20)) {
            toasts.removeAll()
            banner = nil
        }
    }

    // MARK: - Private

    private func insertToast(_ toast: Toast) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            toasts.append(toast)
        }

        let toastID = toast.id
        let timer = Timer.scheduledTimer(withTimeInterval: toast.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss(toastID)
            }
        }
        toastTimers[toast.id] = timer
    }
}
