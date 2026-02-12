import Foundation
import Combine

@MainActor
final class AppLaunchState: ObservableObject {
    @Published var showOnboarding: Bool
    @Published var preloadProgress: Double = 0
    @Published var preloadStatus: String = "Preparing…"

    private let onboardingKey = "did_finish_onboarding_v1"

    init() {
        let didFinish = UserDefaults.standard.bool(forKey: onboardingKey)
        self.showOnboarding = !didFinish
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        showOnboarding = false
    }
}
