import SwiftUI
import UIKit

// MARK: - Continue Reading Shelf (V2)

struct ContinueReadingShelfV2: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var progress = ReadingProgressStore.shared

    var body: some View {
        let keys = progress.recentBookKeys(limit: 12)
        let books: [LibraryStore.Book] = keys.compactMap { store.allBooksIndex[$0] }

        VStack(alignment: .leading, spacing: 12) {
            Text("Continue")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .padding(.top, 6)

            if books.isEmpty {
                Text("Nothing yet — open a book to start tracking.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(books, id: \.fileURL) { book in
                            NavigationLink {
                                ReaderView(book: book, seriesTitle: "Reading")
                            } label: {
                                ContinueReadingCardV2(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

// MARK: - Card (V2)

private struct ContinueReadingCardV2: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let book: LibraryStore.Book

    @State private var cover: UIImage? = nil
    @State private var tint: Color = Color.white.opacity(0.10)
    @State private var isLoading = false

    private var isCompact: Bool { hSizeClass == .compact }

    private var cardSize: CGSize {
        isCompact ? CGSize(width: 340, height: 120) : CGSize(width: 520, height: 150)
    }

    private var coverSize: CGSize {
        isCompact ? CGSize(width: 64, height: 88) : CGSize(width: 84, height: 114)
    }

    private var titleFont: Font {
        isCompact ? .system(size: 18, weight: .bold) : .system(size: 22, weight: .bold)
    }

    private var subtitleFont: Font {
        isCompact ? .system(size: 14, weight: .semibold) : .system(size: 16, weight: .semibold)
    }

    private var progressLine: String {
        if let p = ReadingProgressStore.shared.progress(for: book.fileURL) {
            let pct = Int(((Double(p.lastPageIndex + 1) / Double(max(p.totalPages, 1))) * 100.0).rounded())
            return "Book • \(pct)%"
        }
        return "Book • 0%"
    }

    private var progressValue: Double {
        guard let p = ReadingProgressStore.shared.progress(for: book.fileURL), p.totalPages > 0 else { return 0 }
        let current = Double(p.lastPageIndex + 1)
        let total = Double(p.totalPages)
        return min(1.0, max(0.0, current / total))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background tint (from cover)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.black.opacity(0.12))
                )

            HStack(spacing: 16) {
                // Cover
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.10))

                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .frame(width: coverSize.width, height: coverSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                    Text(book.title)
                        .font(titleFont)
                        .foregroundColor(.white)
                        .lineLimit(isCompact ? 1 : 2)

                    Text(progressLine)
                        .font(subtitleFont)
                        .foregroundColor(.white.opacity(0.88))

                    ProgressView(value: progressValue)
                        .tint(.white)
                        .scaleEffect(x: 1, y: isCompact ? 1.1 : 1.25, anchor: .center)
                }

                Spacer(minLength: 0)

                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.vertical, isCompact ? 12 : 18)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .task(id: book.fileURL) {
            await loadCoverAndTint()
        }
    }

    // MARK: - Load cover + compute tint

    private func loadCoverAndTint() async {
        guard !isLoading else { return }
        isLoading = true

        // If you have a dedicated cover path for the book, use that.
        // Otherwise, this will fall back to first-page thumbnail generation (still works, just slower).
        let img: UIImage? = await Task.detached(priority: .utility) { [book] in
            if let cached = BookThumbnailStore.shared.cachedSync(for: book.fileURL) {
                return cached
            }
            return BookThumbnailStore.shared.loadFirstPageThumbnail(from: book.fileURL)
        }.value

        await MainActor.run {
            self.cover = img

            // Tint from average color
            if let img, let avg = img.averageColor {
                let softened = avg.softenedForUI()
                self.tint = Color(uiColor: softened).opacity(0.85)
            } else {
                self.tint = Color.white.opacity(0.10)
            }

            self.isLoading = false
        }
    }
}
