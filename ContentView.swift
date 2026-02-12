import SwiftUI
import UIKit

struct HideTopPillPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ContentView: View {
    @State private var hideTopPill = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        if isPhone {
            phoneTabs
        } else {
            ipadTabs
        }
    }
}

private extension ContentView {
    var ipadTabs: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            LibrariesView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

//            UserView()
//              .tabItem{ Label("You", systemImage: "person.circle") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

        }
        .tint(Color("AccentColor"))
        // Hide/show the bottom tab bar based on what the current screen requests.
        .toolbarVisibility(hideTopPill ? .hidden : .visible, for: .tabBar)
        // Listen for child views (e.g. SeriesDetailView) requesting tab bar hidden.
        .onPreferenceChange(HideTopPillPreferenceKey.self) { hideTopPill = $0 }
    }

    @ViewBuilder
    var phoneTabs: some View {
        if #available(iOS 26.0, *) {
            // iPhone: use Apple’s native Search-in-Tab-Bar pattern.
            TabView {
                Tab("Home", systemImage: "house") {
                    NavigationStack { HomeView() }
                }

                Tab("Library", systemImage: "books.vertical") {
                    NavigationStack { LibrariesView() }
                }

//                Tab("You", systemImage: "person.circle") {
//                    NavigationStack { UserView() }
//                }

                // The system renders this as a distinct trailing Search tab and can morph it into a field.
                Tab(role: .search) {
                    NavigationStack { SearchView() }
                }
            }
            .tint(Color("AccentColor"))
            .toolbarVisibility(hideTopPill ? .hidden : .visible, for: .tabBar)
            .onPreferenceChange(HideTopPillPreferenceKey.self) { hideTopPill = $0 }
        } else {
            // Fallback: older iOS versions use the classic TabView/tabItem.
            TabView {
                NavigationStack { HomeView() }
                    .tabItem { Label("Home", systemImage: "house") }

                NavigationStack { LibrariesView() }
                    .tabItem { Label("Libraries", systemImage: "books.vertical") }

//                NavigationStack { UserView() }
//                    .tabItem{ Label("You", systemImage: "person.circle") }

                NavigationStack { SearchView() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
            .tint(Color("AccentColor"))
            .toolbarVisibility(hideTopPill ? .hidden : .visible, for: .tabBar)
            .onPreferenceChange(HideTopPillPreferenceKey.self) { hideTopPill = $0 }
        }
    }
}
