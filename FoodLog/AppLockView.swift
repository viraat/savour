import LocalAuthentication
import SwiftUI
import UIKit

struct BiometricAvailability {
    let isAvailable: Bool
    let name: String
}

enum BiometricAuthentication {
    static let settingKey = "foodLogBiometricLockEnabled"

    static func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        let name: String
        switch context.biometryType {
        case .faceID: name = "Face ID"
        case .touchID: name = "Touch ID"
        case .opticID: name = "Optic ID"
        case .none: name = "Biometrics"
        @unknown default: name = "Biometrics"
        }
        return BiometricAvailability(isAvailable: available, name: name)
    }
}

enum AppRelockDelay: Int, CaseIterable, Identifiable {
    static let settingKey = "foodLogRelockDelaySeconds"

    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        }
    }
}

/// Session-only state. A new process always starts locked. Elapsed time uses
/// system uptime so changing the clock cannot extend an unlocked session.
struct AppLockLifecycle {
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var needsAutomaticAuthentication = true
    private var awaySince: TimeInterval?

    func permitsContent(at now: TimeInterval, delay: AppRelockDelay) -> Bool {
        guard isUnlocked else { return false }
        guard let awaySince else { return true }
        let elapsed = now - awaySince
        return elapsed >= 0 && elapsed < Double(delay.rawValue)
    }

    mutating func setEnabled(_ enabled: Bool) {
        isUnlocked = !enabled
        isAuthenticating = false
        needsAutomaticAuthentication = enabled
        awaySince = nil
    }

    mutating func becameInactive(at now: TimeInterval, delay: AppRelockDelay) {
        // LocalAuthentication can make the scene inactive itself. That must
        // neither end its own request nor schedule another prompt.
        guard !isAuthenticating, isUnlocked else { return }
        if awaySince == nil { awaySince = now }
        if delay == .immediately {
            isUnlocked = false
            needsAutomaticAuthentication = true
        }
    }

    mutating func enteredBackground(at now: TimeInterval, delay: AppRelockDelay) {
        if awaySince == nil { awaySince = now }
        if delay == .immediately || isAuthenticating { isUnlocked = false }
        isAuthenticating = false
        needsAutomaticAuthentication = true
    }

    mutating func becameActive(at now: TimeInterval, delay: AppRelockDelay) {
        if let awaySince, isUnlocked {
            let elapsed = now - awaySince
            if elapsed < 0 || elapsed >= Double(delay.rawValue) {
                isUnlocked = false
                needsAutomaticAuthentication = true
            }
        }
        awaySince = nil
    }

    mutating func beginAuthentication(automatic: Bool) -> Bool {
        guard !isUnlocked, !isAuthenticating,
              !automatic || needsAutomaticAuthentication else { return false }
        isAuthenticating = true
        needsAutomaticAuthentication = false
        return true
    }

    mutating func finishAuthentication(success: Bool) {
        isAuthenticating = false
        isUnlocked = success
        // A failed/cancelled request stays locked until explicit retry or a
        // subsequent background/foreground visit, never an active-phase loop.
        needsAutomaticAuthentication = false
        awaySince = nil
    }
}

struct AppLockView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BiometricAuthentication.settingKey) private var lockEnabled = false
    @AppStorage(AppRelockDelay.settingKey) private var relockDelaySeconds = 0

    @State private var lifecycle = AppLockLifecycle()
    @State private var message: String?
    @State private var authenticationContext: LAContext?
    @State private var authenticationAttempts = 0

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var relockDelay: AppRelockDelay {
        AppRelockDelay(rawValue: relockDelaySeconds) ?? .immediately
    }

    var body: some View {
        ZStack {
            FoodTheme.background.ignoresSafeArea()

            // Check expiry during rendering too, before the foreground task
            // updates session state, so there is no unlocked first frame.
            if !lockEnabled || lifecycle.permitsContent(at: ProcessInfo.processInfo.systemUptime, delay: relockDelay) {
                content
                    .accessibilityHidden(lockEnabled && scenePhase != .active)
            } else {
                lockedScreen
            }

            if lockEnabled && scenePhase != .active {
                privacyCover
            }
        }
        .background {
            // A window-level cover also conceals presented editor/detail sheets
            // while retaining their state during the optional grace period.
            AppPrivacyCover(isEnabled: lockEnabled, isVisible: lockEnabled && scenePhase != .active)
        }
        .onAppear {
            if !lockEnabled { lifecycle.setEnabled(false) }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                // Start after the scene's initial presentation, including cold
                // launches that are already active before onChange is installed.
                await Task.yield()
                becameActive()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                lifecycle.becameActive(at: ProcessInfo.processInfo.systemUptime, delay: relockDelay)
            case .inactive:
                if lockEnabled {
                    lifecycle.becameInactive(at: ProcessInfo.processInfo.systemUptime, delay: relockDelay)
                }
            case .background:
                if lockEnabled {
                    lifecycle.enteredBackground(at: ProcessInfo.processInfo.systemUptime, delay: relockDelay)
                }
                authenticationContext?.invalidate()
                authenticationContext = nil
            @unknown default:
                if lockEnabled { lifecycle.setEnabled(true) }
            }
        }
        .onChange(of: lockEnabled) { enabled in
            message = nil
            authenticationContext?.invalidate()
            authenticationContext = nil
            lifecycle.setEnabled(enabled)
            becameActive()
        }
    }

    private var lockedScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(FoodTheme.ink)
                .frame(width: 76, height: 76)
                .foodGlass(cornerRadius: 38)

            VStack(spacing: 6) {
                Text("Savour is locked")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundColor(FoodTheme.ink)
                Text("Unlock to view your journal.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
            }

            if lifecycle.isAuthenticating {
                ProgressView()
                    .controlSize(.large)
            } else {
                Button("Unlock") { authenticate(automatic: false) }
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .foodPrimaryActionStyle()
            }

            if let message {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("authentication-message")
                    .accessibilityValue(authenticationTestValue)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FoodTheme.background)
    }

    private var privacyCover: some View {
        ZStack {
            FoodTheme.background.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(FoodTheme.secondaryText)
        }
        .accessibilityHidden(true)
    }

    private func becameActive() {
        guard scenePhase == .active else { return }
        lifecycle.becameActive(at: ProcessInfo.processInfo.systemUptime, delay: relockDelay)
        authenticate(automatic: true)
    }

    private var authenticationTestValue: String {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return "\(authenticationAttempts)"
        }
#endif
        return ""
    }

    private func authenticate(automatic: Bool) {
        guard lockEnabled, scenePhase == .active,
              lifecycle.beginAuthentication(automatic: automatic) else { return }
        authenticationAttempts += 1
        message = nil

#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--simulate-biometric-denied") ||
            (arguments.contains("--simulate-biometric-success-once") && authenticationAttempts > 1) {
            lifecycle.finishAuthentication(success: false)
            message = "Authentication was cancelled."
            return
        }
        if arguments.contains("--simulate-biometric-success-once") {
            lifecycle.finishAuthentication(success: true)
            return
        }
#endif

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            lifecycle.finishAuthentication(success: false)
            message = "Device authentication is unavailable."
            return
        }

        authenticationContext = context
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your Savour journal"
        ) { success, error in
            DispatchQueue.main.async {
                guard authenticationContext === context else { return }
                authenticationContext = nil
                guard lockEnabled else {
                    lifecycle.setEnabled(false)
                    return
                }
                lifecycle.finishAuthentication(success: success)
                if !success {
                    message = error == nil ? "Authentication was unsuccessful." : "Authentication was cancelled."
                }
            }
        }
    }
}

/// This non-key window covers every presentation in our scene, including sheets.
/// It never receives input or replaces the application's key window.
private struct AppPrivacyCover: UIViewRepresentable {
    let isEnabled: Bool
    let isVisible: Bool

    final class AnchorView: UIView {
        var updateCover: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateCover?(window?.windowScene)
        }
    }

    final class Coordinator {
        var coverWindow: UIWindow?
        var isEnabled = false
        var isVisible = false
        private var observers: [NSObjectProtocol] = []

        init() {
            // Cover synchronously as the scene deactivates, before iOS takes its
            // app-switcher snapshot; SwiftUI's phase update can arrive later.
            for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                         UIScene.didActivateNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let self, let scene = notification.object as? UIWindowScene,
                          scene === self.coverWindow?.windowScene else { return }
                    if self.isEnabled && notification.name == UIScene.willDeactivateNotification {
                        // Keyboard predictions can contain draft text. Remove
                        // the keyboard before the app-switcher snapshot too.
                        UIView.performWithoutAnimation {
                            for window in scene.windows where window !== self.coverWindow {
                                window.endEditing(true)
                            }
                        }
                    }
                    self.update(in: scene)
                    if notification.name != UIScene.didActivateNotification {
                        // willDeactivate may arrive before activationState or
                        // SwiftUI scenePhase changes. Conceal synchronously.
                        self.coverWindow?.isHidden = !self.isEnabled
                    }
                })
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func update(in scene: UIWindowScene?) {
            guard let scene else { return }
            if coverWindow?.windowScene !== scene {
                coverWindow?.isHidden = true
                let controller = UIViewController()
                controller.view.backgroundColor = .systemGroupedBackground
                let image = UIImageView(image: UIImage(systemName: "lock.fill"))
                image.tintColor = .secondaryLabel
                image.contentMode = .scaleAspectFit
                image.translatesAutoresizingMaskIntoConstraints = false
                controller.view.addSubview(image)
                NSLayoutConstraint.activate([
                    image.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                    image.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 36),
                    image.heightAnchor.constraint(equalToConstant: 36)
                ])
                let window = UIWindow(windowScene: scene)
                window.rootViewController = controller
                window.windowLevel = .alert + 1
                window.isUserInteractionEnabled = false
                window.accessibilityElementsHidden = true
                coverWindow = window
            }
            let conceal = isEnabled && (isVisible || scene.activationState != .foregroundActive)
            coverWindow?.isHidden = !conceal
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.updateCover = { [weak coordinator = context.coordinator] scene in
            coordinator?.update(in: scene)
        }
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isVisible = isVisible
        context.coordinator.update(in: view.window?.windowScene)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        view.updateCover = nil
        coordinator.coverWindow?.isHidden = true
        coordinator.coverWindow = nil
    }
}
