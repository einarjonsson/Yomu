import SwiftUI
import UIKit
import Combine

struct YomuApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var appState = AppLaunchState()
    @StateObject private var userStore = UserDataStore.shared   // ✅ use shared singleton
    @State private var didPreload = false    // ensure preload runs once


    init() {
        // keep your appearance code as-is
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor.white
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor.white

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundColor = .clear
        tab.backgroundEffect = nil
        tab.shadowColor = .clear

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(userStore)              // ✅ ADD THIS
                    .task {
                        if !didPreload {
                            didPreload = true
                            await preloadHomeData()
                        }
                    }

                if appState.showOnboarding {
                    OnboardingOverlay(appState: appState)
                        .transition(.opacity)
                }
            }
            .environmentObject(appState)
        }
    }

    // MARK: - Preload pipeline

    @MainActor
    private func updateProgress(_ value: Double, _ status: String) {
        appState.preloadProgress = value
        appState.preloadStatus = status
    }

    private func preloadHomeData() async {
        await updateProgress(0.05, "Preparing library…")

        // Light delay for a smoother first frame only; keep it off-main by default
        await updateProgress(0.20, "Indexing your library…")

        // Snapshot a small subset of series on the main actor
        let series = await MainActor.run { Array(store.series.prefix(8)) }
        if series.isEmpty {
            await updateProgress(1.0, "Ready!")
            return
        }

        await updateProgress(0.35, "Fetching series details…")

        // Fetch metadata concurrently, but cap parallelism to be gentle on rotation/layout
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 3
            var inFlight = 0
            var queued = Array(series.enumerated())
            var completed = 0

            func enqueueNext() {
                guard !queued.isEmpty else { return }
                let (i, s) = queued.removeFirst()
                inFlight += 1
                group.addTask {
                    await SeriesMetadataStore.shared.ensureMetadata(for: s)
                    await MainActor.run {
                        completed += 1
                        let pct = 0.35 + (0.55 * (Double(completed) / Double(max(series.count, 1))))
                        self.appState.preloadProgress = pct
                        self.appState.preloadStatus = "Fetching series details…"
                    }
                }
            }

            // Prime initial tasks
            while inFlight < maxConcurrent && !queued.isEmpty {
                enqueueNext()
            }

            // As each finishes, launch another until all are done
            for await _ in group {
                inFlight -= 1
                if !queued.isEmpty { enqueueNext() }
            }
        }

        await updateProgress(1.0, "Ready!")
    }
}

