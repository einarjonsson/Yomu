import SwiftUI
import UIKit
import CoreImage

// MARK: - Home Screen (Top level)

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var progress = ReadingProgressStore.shared
    @Namespace private var heroZoomNS
    @State private var isScrollLocked = false
    @State private var homeRefreshID = UUID()

    private func lockScrollBriefly(_ seconds: Double = 0.25) {
        isScrollLocked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            isScrollLocked = false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // HOME SUMMARY
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Home")
                                .font(.title2.weight(.semibold))
                            let seriesCount = store.series.count
                            let recentCount = ReadingProgressStore.shared.recentBookKeys(limit: 10).count
                            Text("\(seriesCount) series · \(recentCount) recent")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // HERO
                    HeroCarouselView(zoomNS: heroZoomNS, lockScrollBriefly: lockScrollBriefly)
                        .environmentObject(store)

                    // CONTINUE READING
                    // NOTE: ContinueReadingShelfV2 is assumed to exist elsewhere in your project.
                    ContinueReadingShelfV2()
                        .environmentObject(store)

                    HomeStatsSectionLocal()

                    // Divider
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    // RECENTLY ADDED
                    RecentlyAddedShelf()
                        .environmentObject(store)
                }
                .id(homeRefreshID)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(isScrollLocked)
            .allowsHitTesting(!isScrollLocked)
            .onAppear {
                lockScrollBriefly(0.15)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerDidCloseBook)) { _ in
                // Force a lightweight rebuild so shelves re-query progress/recents.
                homeRefreshID = UUID()
            }

            // This prevents the “content under the nav bar” look *when the bar is transparent at scroll edge*
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

//
// MARK: - Hero Carousel
//
// NOTE:
// - Do NOT put ignoresSafeArea(.top) on the ScrollView.
// - If you want the hero to bleed under the nav later, do it ONLY on the hero itself.
//
private struct HeroCarouselView: View {
    let zoomNS: Namespace.ID
    let lockScrollBriefly: (Double) -> Void
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var metadataStore = SeriesMetadataStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var heroHeight: CGFloat {
        (hSizeClass == .compact) ? 420 : 560
    }
    var body: some View {
        let featured = featuredSeries(limit: 5)

        VStack(spacing: 0) {
            if featured.isEmpty {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: heroHeight)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("Import some series to get started")
                                .foregroundStyle(.secondary)
                        }
                    )
                    .padding(.horizontal, 16)
            } else {
                TabView {
                    ForEach(featured, id: \.folderURL) { series in
                        let meta = metadataStore.metadata(for: series.folderURL)
                        HeroCard(series: series, meta: meta, height: heroHeight, zoomNS: zoomNS, lockScrollBriefly: lockScrollBriefly)
                            .padding(.horizontal, 16)   // ✅ MATCHES SHELVES
                    }
                }
                .frame(height: heroHeight)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
    }

    // Picks up to `limit` featured series, prioritizing recently opened series.
    private func featuredSeries(limit: Int) -> [LibraryStore.Series] {
        let all = store.series

        let recentBookKeys = ReadingProgressStore.shared.recentBookKeys(limit: 30)
        let recentSeriesURLs: [URL] = recentBookKeys.compactMap { key in
            store.allBooksIndex[key]?.seriesFolderURL
        }

        var ordered: [LibraryStore.Series] = []
        var seen = Set<URL>()

        for url in recentSeriesURLs {
            if let s = all.first(where: { $0.folderURL == url }), !seen.contains(url) {
                ordered.append(s)
                seen.insert(url)
            }
            if ordered.count >= limit { break }
        }

        if ordered.count < limit {
            let rest = all
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .filter { !seen.contains($0.folderURL) }

            ordered.append(contentsOf: rest.prefix(limit - ordered.count))
        }

        return Array(ordered.prefix(limit))
    }

    // MARK: Hero Card

    private struct HeroCard: View {
        let series: LibraryStore.Series
        let meta: SeriesMetadata?
        let height: CGFloat
        let zoomNS: Namespace.ID
        let lockScrollBriefly: (Double) -> Void

        @Environment(\.colorScheme) private var colorScheme
        
        @Environment(\.horizontalSizeClass) private var hSizeClass

        private var isCompact: Bool { hSizeClass == .compact }
        private var titleFontSize: CGFloat { isCompact ? 26 : 34 }
        private var coverSize: CGSize { isCompact ? CGSize(width: 96, height: 144) : CGSize(width: 120, height: 180) }
        private var heroTopPadding: CGFloat { isCompact ? 120 : 160 }

        // iPhone text tuning
        private var scoreFont: Font { isCompact ? .subheadline.weight(.semibold) : .headline }
        private var descFont: Font { isCompact ? .footnote : .subheadline }
        private var descLineLimit: Int { isCompact ? 2 : 3 }
        private var titleLineLimit: Int { 2 }

        private let textColor: Color = .white
        private let subTextColor: Color = Color.white.opacity(0.88)

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {

                    heroBackground
                        .frame(width: geo.size.width, height: height)
                        .clipped()

                    // Darken bottom for text readability
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.45),
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height)

                    HStack(alignment: .bottom, spacing: 16) {
                        HeroCover(series: series, coverURLString: meta?.coverImageLarge, size: coverSize)
                            .modifier(ZoomSourceIfAvailable(id: series.folderURL, ns: zoomNS))
                        
                        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
                            Text(meta?.title ?? series.title)
                                .font(.system(size: titleFontSize, weight: .bold))
                                .foregroundColor(textColor)
                                .lineLimit(titleLineLimit)
                                .minimumScaleFactor(isCompact ? 0.85 : 1.0)
                                .allowsTightening(isCompact)

                            if let score = meta?.averageScore {
                                Label("\(score)/100", systemImage: "star.fill")
                                    .font(scoreFont)
                                    .foregroundStyle(subTextColor)
                            }

                            if let desc = meta?.description, !desc.isEmpty {
                                Text(clean(desc))
                                    .font(descFont)
                                    .foregroundColor(subTextColor)
                                    .lineLimit(descLineLimit)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: isCompact ? max(0, geo.size.width - coverSize.width - 24 - 24 - 16) : 520,
                                           alignment: .leading)
                            }

                            NavigationLink {
                                SeriesDetailView(series: series)
                                    .modifier(ZoomNavIfAvailable(id: series.folderURL, ns: zoomNS))
                            } label: {
                                Label("Open", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.accentColor)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    lockScrollBriefly(0.25)
                                }
                            )
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 24)
                    .padding(.bottom, 46)
                    .padding(.top, heroTopPadding)
                }
                .frame(height: height)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }

        private var heroBackground: some View {
            ZStack {
                if let banner = meta?.bannerImage, let url = URL(string: banner) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .empty:
                            Color(uiColor: .secondarySystemBackground)
                        case .success(let img):
                            img.resizable().scaledToFill().transition(.opacity)
                        case .failure:
                            Color(uiColor: .secondarySystemBackground)
                        @unknown default:
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                } else if let cover = meta?.coverImageLarge, let url = URL(string: cover) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .empty:
                            Color(uiColor: .secondarySystemBackground)
                        case .success(let img):
                            img.resizable().scaledToFill().blur(radius: 10).transition(.opacity)
                        case .failure:
                            Color(uiColor: .secondarySystemBackground)
                        @unknown default:
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
        }

        private func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "<br>", with: " ")
                .replacingOccurrences(of: "<i>", with: "")
                .replacingOccurrences(of: "</i>", with: "")
                .replacingOccurrences(of: "<b>", with: "")
                .replacingOccurrences(of: "</b>", with: "")
        }
    }

    // MARK: Hero Cover

        private struct HeroCover: View {
            let series: LibraryStore.Series
            let coverURLString: String?
            let size: CGSize

            init(series: LibraryStore.Series, coverURLString: String?, size: CGSize = CGSize(width: 120, height: 180)) {
                self.series = series
                self.coverURLString = coverURLString
                self.size = size
            }

            var body: some View {
                ZStack {
                    if let local = series.coverURL,
                       let img = CoverImageStore.shared.load(from: local) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if let s = coverURLString, let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color(uiColor: .secondarySystemBackground)
                            }
                        }
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(radius: 10)
            }
        }
}

//
// MARK: - Continue Reading Shelf (legacy)
//
// NOTE: Your HomeView uses ContinueReadingShelfV2(). This legacy shelf is kept here
// in case you still reference it elsewhere.
private struct ContinueReadingShelf: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var progress = ReadingProgressStore.shared

    var body: some View {
        let keys = progress.recentBookKeys(limit: 12)
        let books: [LibraryStore.Book] = keys.compactMap { store.allBooksIndex[$0] }

        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Reading")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 6)

            if books.isEmpty {
                Text("Nothing yet — open a book to start tracking.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(books, id: \.fileURL) { book in
                            NavigationLink {
                                let seriesName = store.series.first(where: { $0.folderURL == book.seriesFolderURL })?.title ?? "Manga"
                                ReaderView(book: book, seriesTitle: seriesName)
                            } label: {
                                ContinueCard(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

//
// MARK: - Recently Added Shelf (grouped by series)
//
private struct RecentlyAddedShelf: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var progress = ReadingProgressStore.shared
    private let metadataStore = SeriesMetadataStore.shared

    /// A grouped model: one card per series, showing how many *recently added* books are unread.
    struct SeriesNewChaptersItem: Identifiable {
        let id: URL
        let series: LibraryStore.Series
        let recentlyAddedBooks: [LibraryStore.Book]
        let unreadNewCount: Int
    }

    var body: some View {
        let items = buildItems(from: store.recentlyAdded)

        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Added")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 6)

            if items.isEmpty {
                Text("No recent books found.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            let meta = metadataStore.metadata(for: item.series.folderURL)
                            let remoteCover = meta?.coverImageLarge

                            NavigationLink {
                                SeriesDetailView(series: item.series)
                            } label: {
                                SeriesNewChaptersCard(item: item, remoteCoverURLString: remoteCover)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func buildItems(from recentlyAdded: [LibraryStore.Book]) -> [SeriesNewChaptersItem] {
        guard !recentlyAdded.isEmpty else { return [] }

        // Keep stable order by first appearance in `recentlyAdded`.
        var orderedSeriesURLs: [URL] = []
        var seen = Set<URL>()

        // Group books by series folder URL.
        var grouped: [URL: [LibraryStore.Book]] = [:]

        for b in recentlyAdded {
            let seriesURL = b.seriesFolderURL

            grouped[seriesURL, default: []].append(b)

            if !seen.contains(seriesURL) {
                seen.insert(seriesURL)
                orderedSeriesURLs.append(seriesURL)
            }
        }

        var result: [SeriesNewChaptersItem] = []
        result.reserveCapacity(orderedSeriesURLs.count)

        for url in orderedSeriesURLs {
            guard let books = grouped[url], !books.isEmpty else { continue }
            guard let series = store.series.first(where: { $0.folderURL == url }) else { continue }

            // “New chapters” = unread books within the *recently added* bucket.
            let unreadNew = books.filter { progress.progress(for: $0.fileURL) == nil }.count

            result.append(
                SeriesNewChaptersItem(
                    id: url,
                    series: series,
                    recentlyAddedBooks: books,
                    unreadNewCount: unreadNew
                )
            )
        }

        return Array(result.prefix(6))
    }
}

// MARK: - Cards

private struct ContinueCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let book: LibraryStore.Book

    private var isCompact: Bool { hSizeClass == .compact }
    private var cardSize: CGSize {
        // iPhone: wider + shorter; iPad: keep existing tall card
        isCompact ? CGSize(width: 320, height: 120) : CGSize(width: 180, height: 250)
    }

    var body: some View {
        let p = ReadingProgressStore.shared.progress(for: book.fileURL)
        let subtitle: String = {
            guard let p else { return "Not started" }
            return "Page \(p.lastPageIndex + 1) of \(p.totalPages)"
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)

            // Very subtle overlay for depth
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))

            if isCompact {
                // iPhone layout: wide card
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                        )
                        .frame(width: 56, height: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        // Small progress bar if we have progress
                        if let p {
                            ProgressView(value: Double(p.lastPageIndex + 1), total: Double(max(p.totalPages, 1)))
                                .tint(.primary)
                                .scaleEffect(x: 1.0, y: 1.15, anchor: .center)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
            } else {
                // iPad layout: keep original tall card
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Recently Added (Series card)

private struct SeriesNewChaptersCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    let item: RecentlyAddedShelf.SeriesNewChaptersItem
    let remoteCoverURLString: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SeriesCoverThumb(series: item.series, remoteCoverURLString: remoteCoverURLString)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.series.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if item.unreadNewCount > 0 {
                    Text("\(item.unreadNewCount) new chapter\(item.unreadNewCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                } else {
                    Text("No new chapters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Added: \(item.recentlyAddedBooks.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(
            width: (hSizeClass == .compact) ? 320 : 360,
            height: (hSizeClass == .compact) ? 112 : 120
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SeriesCoverThumb: View {
    let series: LibraryStore.Series
    let remoteCoverURLString: String?

    var body: some View {
        ZStack {
            if let local = series.coverURL,
               let img = CoverImageStore.shared.load(from: local) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()

            } else if let s = remoteCoverURLString,
                      let url = URL(string: s) {
                AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }

            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}

// MARK: - Home Stats Section

private struct HomeStatsSectionLocal: View {
    @StateObject private var progress = ReadingProgressStore.shared
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stats")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 6)

            if isCompact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Completed",
                            value: "\(progress.completedBooksTotal())",
                            subtitle: "All time",
                            systemImage: "checkmark.seal.fill"
                        )
                        .frame(width: 180)

                        StatCard(
                            title: "Reading",
                            value: "\(progress.minutesReadTodayTotal()) min",
                            subtitle: "Today",
                            systemImage: "clock.fill"
                        )
                        .frame(width: 180)

                        StatCard(
                            title: "Finished",
                            value: "\(progress.booksFinishedThisYear())",
                            subtitle: "This year",
                            systemImage: "calendar"
                        )
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                HStack(spacing: 12) {
                    StatCard(
                        title: "Completed",
                        value: "\(progress.completedBooksTotal())",
                        subtitle: "All time",
                        systemImage: "checkmark.seal.fill"
                    )

                    StatCard(
                        title: "Reading",
                        value: "\(progress.minutesReadTodayTotal()) min",
                        subtitle: "Today",
                        systemImage: "clock.fill"
                    )

                    StatCard(
                        title: "Finished",
                        value: "\(progress.booksFinishedThisYear())",
                        subtitle: "This year",
                        systemImage: "calendar"
                    )
                }
                .padding(.horizontal, 16)
            }
        }
        // Important: make sure it doesn't collapse to zero height.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    private var isCompact: Bool { hSizeClass == .compact }
    private var titleFont: Font { .system(size: isCompact ? 14 : 16, weight: .semibold) }
    private var valueFont: Font { .system(size: isCompact ? 22 : 28, weight: .bold) }
    private var subtitleFont: Font { .system(size: isCompact ? 12 : 14, weight: .medium) }
    private var iconFont: Font { .system(size: isCompact ? 14 : 16, weight: .semibold) }
    private var pad: CGFloat { isCompact ? 12 : 14 }
    private var cardWidth: CGFloat { isCompact ? 180 : 220 }
    private var cardHeight: CGFloat { 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(iconFont)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(valueFont)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(pad)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}


// MARK: - iOS 18+ Fluid transitions helpers

private struct ZoomSourceIfAvailable: ViewModifier {
    let id: AnyHashable
    let ns: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}

private struct ZoomNavIfAvailable: ViewModifier {
    let id: AnyHashable
    let ns: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            content
        }
    }
}



// MARK: - Reader close refresh signal
extension Notification.Name {
    static let readerDidCloseBook = Notification.Name("readerDidCloseBook")
}

