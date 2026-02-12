import SwiftUI

struct OnboardingOverlay: View {
    @ObservedObject var appState: AppLaunchState

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome")
                    .font(.title2).bold()

                Text("We’re preparing your library and fetching series details in the background.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: appState.preloadProgress)
                    Text(appState.preloadStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.finishOnboarding()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            .padding(18)
            .frame(maxWidth: 520)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .padding(.horizontal, 18)
        }
    }
}
