import LocalAuthentication
import SwiftUI

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

struct AppLockView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BiometricAuthentication.settingKey) private var lockEnabled = false

    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var message: String?
    @State private var authenticationContext: LAContext?

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            FoodTheme.background.ignoresSafeArea()

            if !lockEnabled || isUnlocked {
                content
            } else {
                lockedScreen
            }

            if lockEnabled && scenePhase != .active {
                privacyCover
            }
        }
        .onAppear {
            if lockEnabled {
                authenticate()
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                authenticate()
            case .inactive:
                if lockEnabled { isUnlocked = false }
            case .background:
                isUnlocked = false
                authenticationContext?.invalidate()
                authenticationContext = nil
                isAuthenticating = false
            @unknown default:
                if lockEnabled { isUnlocked = false }
            }
        }
        .onChange(of: lockEnabled) { enabled in
            message = nil
            if enabled {
                isUnlocked = false
                authenticate()
            } else {
                authenticationContext?.invalidate()
                authenticationContext = nil
                isAuthenticating = false
                isUnlocked = true
            }
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
                Text("FoodLog is locked")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundColor(FoodTheme.ink)
                Text("Unlock to view your journal.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
            }

            if isAuthenticating {
                ProgressView()
                    .controlSize(.large)
            } else {
                Button("Unlock", action: authenticate)
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

    private func authenticate() {
        guard lockEnabled,
              scenePhase == .active,
              !isUnlocked,
              !isAuthenticating
        else { return }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--simulate-biometric-denied") {
            isUnlocked = false
            isAuthenticating = false
            message = "Authentication was cancelled."
            return
        }
#endif

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            message = "Device authentication is unavailable."
            return
        }

        isAuthenticating = true
        authenticationContext = context
        message = nil
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your FoodLog journal"
        ) { success, error in
            DispatchQueue.main.async {
                guard authenticationContext === context else { return }
                authenticationContext = nil
                isAuthenticating = false
                guard lockEnabled else {
                    isUnlocked = false
                    return
                }
                isUnlocked = success
                if !success {
                    message = error == nil ? "Authentication was unsuccessful." : "Authentication was cancelled."
                }
            }
        }
    }
}
