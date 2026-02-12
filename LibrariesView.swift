import SwiftUI
import UniformTypeIdentifiers

struct LibrariesView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showImporter = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Namespace private var zoomNS
    @State private var isScrollLocked = false

    private func lockScrollBriefly(_ seconds: Double = 0.25) {
        isScrollLocked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            isScrollLocked = false
        }
    }

    private var isCompact: Bool { hSizeClass == .compact }

    private var grid: [GridItem] {
        // iPhone: allow 2-up layout with smaller tiles; iPad: keep current 180 minimum
        [GridItem(.adaptive(minimum: isCompact ? 150 : 180), spacing: 14)]
    }

    private var tileHeight: CGFloat { isCompact ? 210 : 250 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.series.isEmpty {
                        ContentUnavailableView(
                            "No Manga Yet",
                            systemImage: "books.vertical",
                            description: Text("Import your manga folder to get started.")
                        )
                        .padding(.top, 12)
                    } else {
                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(store.series) { s in
                                // Precompute metadata to help the type-checker
                                let meta = SeriesMetadataStore.shared.metadata(for: s.folderURL)

                                let completed: Bool = {
                                    let s = (meta?.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                    return s == "FINISHED" || s == "COMPLETED" || s == "COMPLETE"
                                }()

                                NavigationLink {
                                    SeriesDetailView(series: s)
                                        .modifier(ZoomNavIfAvailable(id: s.id, ns: zoomNS))
                                } label: {
                                    SeriesSquare(
                                        title: s.title,
                                        subtitle: "\(s.cbzCount) book(s)",
                                        localCoverURL: s.coverURL,
                                        remoteCoverURLString: meta?.coverImageLarge,
                                        height: tileHeight,
                                        transitionID: s.id,
                                        zoomNS: zoomNS,
                                        isCompleted: completed
                                    )
                                }
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        lockScrollBriefly(0.25)
                                    }
                                )
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 10)
                    }
                    if !store.status.isEmpty {
                        Text(store.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollDisabled(isScrollLocked)
            .refreshable {
                store.refreshSeries()
            }
            .allowsHitTesting(!isScrollLocked)
            .onAppear {
                // When we return from the detail view, SwiftUI may still be settling the
                // interactive zoom transition for a fraction of a second. Lock scroll briefly
                // so an immediate swipe doesn’t break layout/gesture state.
                lockScrollBriefly(0.25)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .foregroundStyle(.primary)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(isCompact ? .large : .inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            store.refreshSeries()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button(role: .destructive) {
                            store.clearSavedFolder()
                        } label: {
                            Label("Reset Library Folder", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    store.setPickedFolder(url)
                case .failure(let error):
                    store.status = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct SeriesSquare: View {
    let title: String
    let subtitle: String
    let localCoverURL: URL?
    let remoteCoverURLString: String?
    let height: CGFloat
    let transitionID: AnyHashable
    let zoomNS: Namespace.ID
    let isCompleted: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String,
        localCoverURL: URL?,
        remoteCoverURLString: String?,
        height: CGFloat = 250,
        transitionID: AnyHashable,
        zoomNS: Namespace.ID,
        isCompleted: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.localCoverURL = localCoverURL
        self.remoteCoverURLString = remoteCoverURLString
        self.height = height
        self.transitionID = transitionID
        self.zoomNS = zoomNS
        self.isCompleted = isCompleted
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // Background image priority:
            // 1) local cover file
            // 2) remote cover from AniList
            if let localCoverURL, let img = CoverImageStore.shared.load(from: localCoverURL) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .clipped()
            } else if let s = remoteCoverURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.primary.opacity(0.08)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.primary.opacity(0.08)
                    @unknown default:
                        Color.primary.opacity(0.08)
                    }
                }
                .frame(height: height)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                Image(systemName: "books.vertical")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .opacity(0.75)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.80)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(ZoomSourceIfAvailable(id: transitionID, ns: zoomNS))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.14), lineWidth: 1)
        )
        .overlay(
            Group {
                if isCompleted {
                    HStack {
                        Spacer()
                        Text("COMPLETED")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
            }, alignment: .top
        )
    }
}

/// iOS 18+ fluid zoom transition helpers.
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

