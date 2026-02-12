import SwiftUI
import UIKit

struct ReaderView: View {
    let book: LibraryStore.Book
    let seriesTitle: String
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var pages: [UIImage] = []
    @State private var isLoading = true
    @State private var errorText: String? = nil
    
    @State private var mode: ReaderMode = .curl
    
    // ✅ This is the binding PageCurlReader expects
    @State private var currentIndex: Int = 0
    
    // ✅ Tap middle toggles this
    @State private var chromeHidden = false

    // Added state vars for drag-to-dismiss gesture
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDraggingToDismiss = false

    // Reader HUD + actions
    @State private var showGoToPage = false
    @State private var goToPageText: String = ""

    // Simple in-memory bookmarks (we can persist later)
    @State private var bookmarks: Set<Int> = []
    
    // End-of-volume behavior
    @State private var didTriggerPrefetch = false
    @State private var showEndAlert = false
    @State private var endAlertMode: EndAlertMode = .nextVolume

    @State private var nextVolumeURL: URL? = nil
    @State private var nextVolumeTitle: String = ""

    @State private var pushNext = false
    @State private var nextBookToOpen: LibraryStore.Book? = nil

    @State private var showSimilarSheet = false
    @State private var similarSeries: [SimilarSeriesItem] = []

    private enum EndAlertMode { case nextVolume, endOfSeries }

    private struct SimilarSeriesItem: Identifiable {
        let id = UUID()
        let title: String
        let coverURL: URL?
        let folderURL: URL
    }
    
    // Persistent reader settings
    @AppStorage("reader.keepAwake") private var keepAwake: Bool = true
    @AppStorage("reader.brightness") private var savedBrightness: Double = -1 // -1 = don't override
    @AppStorage("reader.direction") private var savedDirectionRaw: String = ReadingDirection.rtl.rawValue
    @AppStorage("reader.reverseScroll") private var reverseScroll: Bool = false

    @State private var showReaderSettings = false

    // Track and restore system settings
    @State private var priorBrightness: CGFloat = UIScreen.main.brightness
    @State private var priorIdleDisabled: Bool = false

    // Small in-memory cache for scroll zoom views
    private let imageCache = NSCache<NSNumber, UIImage>()
    
    
    
    // For scroll tracking throttling
    @State private var lastRecordedPage: Int? = nil
    @State private var pendingWorkItem: DispatchWorkItem? = nil
    
    private let chromeFadeDuration: Double = 0.30
    
    private enum ReaderMode: String, CaseIterable {
        case scroll
        case curl
    }
    
    private enum ReadingDirection: String, CaseIterable {
        case rtl
        case ltr

        var title: String { self == .rtl ? "Right-to-left" : "Left-to-right" }
    }

    private var direction: ReadingDirection {
        ReadingDirection(rawValue: savedDirectionRaw) ?? .rtl
    }
    
    
    // MARK: - View switcher
    
    @ViewBuilder
    private var pagesView: some View {
        if mode == ReaderMode.curl {
            PageCurlReader(
                pages: pages,
                currentIndex: $currentIndex,
                chromeHidden: $chromeHidden.animation(.easeInOut(duration: chromeFadeDuration)),
                direction: (direction == .rtl ? .rtl : .ltr),
                useSingleCoverInLandscape: true
            )
        } else if mode == ReaderMode.scroll {
            scrollReaderView
                // Tap-to-toggle chrome in scroll mode (curl mode handles tap zones inside UIKit)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: chromeFadeDuration)) {
                        chromeHidden.toggle()
                    }
                }
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Scroll mode

    private var scrollReaderView: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayOrder, id: \.self) { index in
                            ZoomableImageView(
                                image: cachedImage(for: index) ?? pages[index],
                                cacheKey: index,
                                cache: imageCache
                            )
                            .cornerRadius(8)
                            .padding(.horizontal, 10)
                            .id(index)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: PageMidYPreferenceKey.self,
                                        value: [index: geo.frame(in: .named("scroll")).midY]
                                    )
                                }
                            )
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(Color.black)
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(PageMidYPreferenceKey.self) { (midYs: [Int: CGFloat]) in
                    updateMostVisiblePage(midYs: midYs, viewportHeight: outer.size.height)
                }
                .onChange(of: pages.count) { _ in
                    if let p = ReadingProgressStore.shared.progress(for: book.fileURL) {
                        DispatchQueue.main.async {
                            proxy.scrollTo(min(p.lastPageIndex, max(0, pages.count - 1)), anchor: .top)
                        }
                    }
                }
                .onAppear {
                    if let p = ReadingProgressStore.shared.progress(for: book.fileURL), !pages.isEmpty {
                        proxy.scrollTo(min(p.lastPageIndex, max(0, pages.count - 1)), anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundColor(.secondary)
                }
            } else if let errorText {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(errorText)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                pagesView
            }

            // (HUD overlays removed; toolbars now used)
            // Hidden push for "Next Volume"
            NavigationLink(
                destination: Group {
                    if let nb = nextBookToOpen {
                        ReaderView(book: nb, seriesTitle: seriesTitle)
                    } else {
                        EmptyView()
                    }
                },
                isActive: $pushNext
            ) { EmptyView() }
            .hidden()
        }
        .offset(y: dragOffsetY)
        .scaleEffect(isDraggingToDismiss ? max(0.9, 1.0 - (abs(dragOffsetY) / 1200)) : 1.0)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    // Only when chrome is visible and dragging down
                    guard !chromeHidden else { return }
                    let dy = value.translation.height
                    if dy > 0 { // downward only
                        isDraggingToDismiss = true
                        dragOffsetY = dy
                    }
                }
                .onEnded { value in
                    defer {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            dragOffsetY = 0
                            isDraggingToDismiss = false
                        }
                    }
                    guard !chromeHidden else { return }
                    let dy = value.translation.height
                    let velocityY = value.velocity.height

                    // Thresholds: distance or fast flick
                    let distanceThreshold: CGFloat = 140
                    let velocityThreshold: CGFloat = 900
                    if dy > distanceThreshold || velocityY > velocityThreshold {
                        // Smoothly dismiss
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            dragOffsetY = UIScreen.main.bounds.height
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            dismiss()
                        }
                    }
                }
        )
        .statusBarHidden(chromeHidden)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar(chromeHidden ? .hidden : .visible, for: .bottomBar)
        // Hide bottom tab bar in reader
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.black, for: .bottomBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .bottomBar)
        .toolbar {
            // Top navigation bar
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .principal) {
                Text("\(seriesTitle) | \(book.title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        mode = (mode == .curl) ? .scroll : .curl
                    } label: {
                        Label(mode == .curl ? "Switch to Scroll" : "Switch to Curl",
                              systemImage: mode == .curl ? "scroll" : "rectangle.portrait.on.rectangle.portrait")
                    }

                    Divider()

                    Button {
                        openGoToPage()
                    } label: {
                        Label("Go to Page…", systemImage: "number")
                    }

                    Button {
                        toggleBookmark()
                    } label: {
                        Label(bookmarks.contains(currentIndex) ? "Remove Bookmark" : "Add Bookmark",
                              systemImage: bookmarks.contains(currentIndex) ? "bookmark.fill" : "bookmark")
                    }

                    Divider()

                    Button {
                        showReaderSettings = true
                    } label: {
                        Label("Reader Settings…", systemImage: "textformat.size")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            // Bottom toolbar (HIG: frequent actions)
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    toggleBookmark()
                } label: {
                    Image(systemName: bookmarks.contains(currentIndex) ? "bookmark.fill" : "bookmark")
                }

                Spacer()

                Button {
                    openGoToPage()
                } label: {
                    Image(systemName: "number")
                }

                Spacer()

                Button {
                    showReaderSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }

        // Removed .onAppear that called markOpened
        .onAppear {
            didTriggerPrefetch = false
            showEndAlert = false
            
            loadBookmarks()

            priorIdleDisabled = UIApplication.shared.isIdleTimerDisabled
            if keepAwake { UIApplication.shared.isIdleTimerDisabled = true }

            priorBrightness = UIScreen.main.brightness
            if savedBrightness >= 0 {
                UIScreen.main.brightness = CGFloat(savedBrightness)
            }
        }
        
        // Add onChange for currentIndex to track progress only when page changes
        .onChange(of: currentIndex) { newValue in
            ReadingProgressStore.shared.setProgress(for: book.fileURL, lastPageIndex: newValue, totalPages: pages.count)

            // Prefetch next volume when approaching the end
            prefetchNextVolumeIfNeeded(currentPage: newValue)

            // Show end-of-volume alert on final page
            if !pages.isEmpty, newValue == pages.count - 1 {
                presentEndAlertIfNeeded()
            }
        }

        .onDisappear {
            ReadingProgressStore.shared.addMinutesRead(2, for: book.fileURL)
            UIApplication.shared.isIdleTimerDisabled = priorIdleDisabled
            UIScreen.main.brightness = priorBrightness
        }

        // Load pages
        .task { await loadCBZ() }

        .sheet(isPresented: $showGoToPage) {
            NavigationStack {
                Form {
                    Section("Go to page") {
                        TextField("Page number", text: $goToPageText)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("Go to Page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showGoToPage = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            applyGoToPage()
                            showGoToPage = false
                        }
                        .disabled(Int(goToPageText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showReaderSettings) {
            NavigationStack {
                Form {
                    Section {
                        Picker("Direction", selection: $savedDirectionRaw) {
                            ForEach(ReadingDirection.allCases, id: \.rawValue) { d in
                                Text(d.title).tag(d.rawValue)
                            }
                        }

                        Toggle("Reverse scroll order", isOn: $reverseScroll)
                            .disabled(mode != .scroll)

                        Toggle("Keep screen awake", isOn: $keepAwake)
                            .onChange(of: keepAwake) { v in
                                UIApplication.shared.isIdleTimerDisabled = v
                            }
                    }

                    Section("Brightness") {
                        Toggle("Override brightness", isOn: Binding(
                            get: { savedBrightness >= 0 },
                            set: { on in
                                if on {
                                    savedBrightness = Double(UIScreen.main.brightness)
                                } else {
                                    savedBrightness = -1
                                    UIScreen.main.brightness = priorBrightness
                                }
                            }
                        ))

                        if savedBrightness >= 0 {
                            Slider(value: Binding(
                                get: { savedBrightness },
                                set: { v in
                                    savedBrightness = v
                                    UIScreen.main.brightness = CGFloat(v)
                                }
                            ), in: 0.05...1.0)
                        }
                    }

                    Section("About") {
                        Text("Bookmarks are saved per volume on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Reader Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showReaderSettings = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .alert(isPresented: $showEndAlert) {
            switch endAlertMode {
            case .nextVolume:
                return Alert(
                    title: Text("End of Volume"),
                    message: Text("Ready to continue with \(nextVolumeTitle)?"),
                    primaryButton: .default(Text("Next Volume")) { openNextVolume() },
                    secondaryButton: .cancel(Text("Later"))
                )

            case .endOfSeries:
                return Alert(
                    title: Text("You’re caught up"),
                    message: Text("That was the last page of the last volume."),
                    primaryButton: .default(Text("Similar series")) { showSimilarSheet = true },
                    secondaryButton: .cancel(Text("Done"))
                )
            }
        }
        .sheet(isPresented: $showSimilarSheet) {
            NavigationStack {
                List {
                    if similarSeries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No suggestions yet")
                                .font(.headline)
                            Text("We’ll add smarter recommendations later. For now, here are nearby series from your library.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(similarSeries) { item in
                            HStack(spacing: 12) {
                                SimilarCoverView(url: item.coverURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text("From your library")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Similar series")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSimilarSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }


    // MARK: - Load

    private func loadCBZ() async {
        isLoading = true
        errorText = nil
        pages = []
        didTriggerPrefetch = false
        showEndAlert = false
        nextVolumeURL = nil
        nextVolumeTitle = ""

        let url = book.fileURL

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let images = try await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                try CBZExtractor.extractImages(from: url)
            }.value

            await MainActor.run {
                self.pages = images
                self.isLoading = false

                // ✅ Restore last page, but do not call setProgress here yet
                if let p = ReadingProgressStore.shared.progress(for: book.fileURL) {
                    self.currentIndex = min(p.lastPageIndex, max(0, images.count - 1))
                } else {
                    self.currentIndex = 0
                }
                self.resolveNextVolume()
            }
        } catch {
            await MainActor.run {
                self.errorText = "Could not open this book.\n\(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Bookmark persistence

    private var bookmarkKey: String {
        "bookmarks::\(book.fileURL.path)"
    }

    private func loadBookmarks() {
        if let arr = UserDefaults.standard.array(forKey: bookmarkKey) as? [Int] {
            bookmarks = Set(arr)
        } else {
            bookmarks = []
        }
    }

    private func saveBookmarks() {
        UserDefaults.standard.set(Array(bookmarks).sorted(), forKey: bookmarkKey)
    }
    
    
    // MARK: - Reader actions

    // MARK: - Next volume + end-of-series

    private func seriesRootFolder() -> URL {
        book.seriesFolderURL
    }

    private func collectReadableFilesRecursively(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [URL] = []
        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if vals?.isDirectory == true { continue }

            let ext = url.pathExtension.lowercased()
            if ext == "cbz" || ext == "pdf" {
                out.append(url)
            }
        }

        return out.sorted { a, b in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    private func resolveNextVolume() {
        let root = seriesRootFolder()
        let files = collectReadableFilesRecursively(in: root)

        guard let currentPos = files.firstIndex(where: { $0.standardizedFileURL == book.fileURL.standardizedFileURL }) else {
            nextVolumeURL = nil
            nextVolumeTitle = ""
            return
        }

        let nextIndex = currentPos + 1
        guard nextIndex < files.count else {
            nextVolumeURL = nil
            nextVolumeTitle = ""
            return
        }

        let next = files[nextIndex]
        nextVolumeURL = next
        nextVolumeTitle = next.deletingPathExtension().lastPathComponent
    }

    private func prefetchNextVolumeIfNeeded(currentPage: Int) {
        guard !pages.isEmpty else { return }
        guard !didTriggerPrefetch else { return }

        let threshold = max(0, pages.count - 5)
        guard currentPage >= threshold else { return }

        didTriggerPrefetch = true
        resolveNextVolume()

        guard let nextURL = nextVolumeURL else { return }

        Task.detached(priority: .utility) {
            let didAccess = nextURL.startAccessingSecurityScopedResource()
            defer { if didAccess { nextURL.stopAccessingSecurityScopedResource() } }

            try? ICloudDownloadHelper.startDownload(nextURL)
        }
    }

    private func presentEndAlertIfNeeded() {
        guard !showEndAlert else { return }

        resolveNextVolume()

        if nextVolumeURL != nil {
            endAlertMode = .nextVolume
        } else {
            endAlertMode = .endOfSeries
            loadLocalSimilarSeries()
        }

        showEndAlert = true
    }

    private func openNextVolume() {
        guard let url = nextVolumeURL else { return }

        let nextBook = LibraryStore.Book(
            title: url.deletingPathExtension().lastPathComponent,
            fileURL: url,
            seriesFolderURL: seriesRootFolder()
        )

        nextBookToOpen = nextBook
        pushNext = true
    }

    private func loadLocalSimilarSeries() {
        // Fallback similarity: pick sibling series folders under the library root
        let seriesFolder = seriesRootFolder()
        let libraryRoot = seriesFolder.deletingLastPathComponent()
        let fm = FileManager.default

        guard let children = try? fm.contentsOfDirectory(
            at: libraryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            similarSeries = []
            return
        }

        let folders = children.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir && url.standardizedFileURL != seriesFolder.standardizedFileURL
        }

        func score(_ name: String) -> Int {
            let a = name.lowercased()
            let b = seriesTitle.lowercased()
            return zip(a, b).prefix { $0 == $1 }.count
        }

        let top = folders
            .sorted { score($0.lastPathComponent) > score($1.lastPathComponent) }
            .prefix(6)

        similarSeries = top.map { folder in
            SimilarSeriesItem(
                title: folder.lastPathComponent,
                coverURL: findCoverImageInSeriesFolder(folder),
                folderURL: folder
            )
        }
    }

    private func findCoverImageInSeriesFolder(_ folder: URL) -> URL? {
        let fm = FileManager.default
        let candidates = [
            "cover.jpg", "cover.jpeg", "cover.png",
            "folder.jpg", "folder.jpeg", "folder.png",
            "Cover.jpg", "Cover.png"
        ]
        for name in candidates {
            let u = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private var pageLabel: String {
        guard !pages.isEmpty else { return "" }
        return "\(currentIndex + 1) / \(pages.count)"
    }

    private func clampPage(_ i: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(i, 0), pages.count - 1)
    }

    private func toggleBookmark() {
        guard !pages.isEmpty else { return }
        if bookmarks.contains(currentIndex) {
            bookmarks.remove(currentIndex)
        } else {
            bookmarks.insert(currentIndex)
        }
        saveBookmarks()
    }
    
    private var displayOrder: [Int] {
        guard !pages.isEmpty else { return [] }
        let indices = Array(pages.indices)
        return (mode == .scroll && reverseScroll) ? indices.reversed() : indices
    }

    private func cachedImage(for index: Int) -> UIImage? {
        imageCache.object(forKey: NSNumber(value: index))
    }

    private func jumpToBookmark(next: Bool) {
        guard !bookmarks.isEmpty else { return }
        let sorted = bookmarks.sorted()
        if next {
            if let target = sorted.first(where: { $0 > currentIndex }) {
                currentIndex = target
            } else {
                currentIndex = sorted.first ?? currentIndex
            }
        } else {
            if let target = sorted.last(where: { $0 < currentIndex }) {
                currentIndex = target
            } else {
                currentIndex = sorted.last ?? currentIndex
            }
        }
    }

    private func openGoToPage() {
        guard !pages.isEmpty else { return }
        goToPageText = String(currentIndex + 1)
        showGoToPage = true
    }

    private func applyGoToPage() {
        guard let n = Int(goToPageText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        currentIndex = clampPage(n - 1)
    }

    // MARK: - Scroll tracking

    private func updateMostVisiblePage(midYs: [Int: CGFloat], viewportHeight: CGFloat) {
        guard !pages.isEmpty else { return }

        let viewportMid = viewportHeight / 2

        guard let best = midYs.min(by: { abs($0.value - viewportMid) < abs($1.value - viewportMid) })?.key else {
            return
        }

        if best == lastRecordedPage { return }

        pendingWorkItem?.cancel()
        let work = DispatchWorkItem {
            lastRecordedPage = best
            ReadingProgressStore.shared.setProgress(
                for: book.fileURL,
                lastPageIndex: best,
                totalPages: pages.count
            )
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    
    // MARK: - Zoomable image (scroll mode)
    
    private struct SimilarCoverView: View {
        let url: URL?

        var body: some View {
            Group {
                if let url,
                   let data = try? Data(contentsOf: url),
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.15))
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 52, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private struct ZoomableImageView: UIViewRepresentable {
        let image: UIImage
        let cacheKey: Int
        let cache: NSCache<NSNumber, UIImage>

        func makeUIView(context: Context) -> UIScrollView {
            let scrollView = UIScrollView()
            scrollView.maximumZoomScale = 4.0
            scrollView.minimumZoomScale = 1.0
            scrollView.bouncesZoom = true
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.delegate = context.coordinator

            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
            ])

            let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            context.coordinator.scrollView = scrollView
            context.coordinator.imageView = imageView

            return scrollView
        }

        func updateUIView(_ uiView: UIScrollView, context: Context) {
            context.coordinator.imageView?.image = image
            cache.setObject(image, forKey: NSNumber(value: cacheKey))
        }
        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject, UIScrollViewDelegate {
            weak var scrollView: UIScrollView?
            weak var imageView: UIImageView?

            func viewForZooming(in scrollView: UIScrollView) -> UIView? {
                imageView
            }

            @objc func didDoubleTap(_ gr: UITapGestureRecognizer) {
                guard let scrollView else { return }

                if scrollView.zoomScale > 1.01 {
                    scrollView.setZoomScale(1.0, animated: true)
                } else {
                    let point = gr.location(in: imageView)
                    let size = scrollView.bounds.size
                    let zoomRect = CGRect(
                        x: point.x - size.width / 4,
                        y: point.y - size.height / 4,
                        width: size.width / 2,
                        height: size.height / 2
                    )
                    scrollView.zoom(to: zoomRect, animated: true)
                }
            }
        }
    }
}

