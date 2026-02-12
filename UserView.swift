import SwiftUI

struct UserView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var userStore = UserDataStore.shared

    @State private var showCreateList = false
    @State private var newListName = ""

    @State private var listOrder = UserListOrderStore.load()

    @State private var showRenameList = false
    @State private var renameListText = ""
    @State private var renameListId: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    profileHeader

                    continueShelfSection

                    ratingsShelfSection

                    listsShelfSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("You")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(systemImage: "plus") {
                        showCreateList = true
                    }
                    .accessibilityLabel("Create list")
                }
            }
            .sheet(isPresented: $showCreateList) {
                NavigationStack {
                    Form {
                        Section("New list") {
                            TextField("List name", text: $newListName)
                        }
                    }
                    .navigationTitle("Create List")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                newListName = ""
                                showCreateList = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Create") {
                                userStore.createList(name: newListName)
                                newListName = ""
                                showCreateList = false
                            }
                            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showRenameList) {
                NavigationStack {
                    Form {
                        Section("Rename list") {
                            TextField("Name", text: $renameListText)
                        }
                    }
                    .navigationTitle("Rename")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showRenameList = false
                                renameListId = nil
                                renameListText = ""
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                if let id = renameListId {
                                    userStore.renameList(id: id, newName: renameListText)
                                }
                                showRenameList = false
                                renameListId = nil
                                renameListText = ""
                            }
                            .disabled(renameListText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Data helpers (avoid local declarations in ViewBuilder)

    private var favoriteSeriesSorted: [LibraryStore.Series] {
        store.series
            .filter { userStore.isFavorite($0.folderURL) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var systemListsSorted: [UserList] {
        userStore.lists.values
            .filter { $0.isSystem }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var customListsSorted: [UserList] {
        var custom = userStore.lists.values.filter { !$0.isSystem }

        // Apply persisted order for custom lists.
        custom.sort { a, b in
            let ia = listOrder.firstIndex(of: a.id) ?? Int.max
            let ib = listOrder.firstIndex(of: b.id) ?? Int.max
            if ia == ib {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return ia < ib
        }

        return custom
    }



    // MARK: - Trakt-style dashboard

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Avatar (placeholder for now)
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                    Image(systemName: "person.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 6) {
                    Text("You")
                        .font(.title2.weight(.bold))

                    Text("Local profile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        StatChip(value: userStore.favoriteSeriesKeys().count, label: "favorites")
                        StatChip(value: store.series.reduce(0) { $0 + $1.cbzCount }, label: "volumes")
                        StatChip(value: userStore.lists.values.count, label: "lists")
                    }
                    .padding(.top, 6)

                    HStack(spacing: 10) {
                        CapsuleButton(title: "Edit Profile", systemImage: "pencil") {
                            // stub for now
                        }

                        IconOnlyButton(systemImage: "square.and.arrow.up") {
                            // stub for now
                        }
                    }
                    .padding(.top, 6)
                }

                Spacer(minLength: 0)
            }

            // Sign-in stub inline (matches your “coming soon” requirement)
            VStack(alignment: .leading, spacing: 8) {
                SignInWithAppleStubButton()
                Text("Coming soon: Sign in with Apple to sync across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var continueShelfSection: some View {
        DashboardSection(title: "Continue reading") {
            if favoriteSeriesSorted.isEmpty {
                EmptyShelf(text: "Start reading a series to see it here.")
            } else {
                Shelf {
                    ForEach(favoriteSeriesSorted.prefix(10), id: \.folderURL) { s in
                        NavigationLink {
                            SeriesDetailView(series: s)
                        } label: {
                            WideShelfCard(
                                title: s.title,
                                subtitle: "Tap to resume",
                                coverURL: s.coverURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var ratingsShelfSection: some View {
        DashboardSection(title: "Ratings & notes") {
            let rated = store.series
                .filter {
                    (userStore.rating(for: $0.folderURL) ?? 0) > 0 ||
                    !userStore.note(for: $0.folderURL).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

            if rated.isEmpty {
                EmptyShelf(text: "Rate a series or add a note to see it here.")
            } else {
                Shelf {
                    ForEach(rated.prefix(12), id: \.folderURL) { s in
                        NavigationLink {
                            SeriesDetailView(series: s)
                        } label: {
                            RatedShelfCard(series: s)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var listsShelfSection: some View {
        DashboardSection(title: "Lists", trailing: {
            NavigationLink {
                ManageListsView(
                    listOrder: $listOrder,
                    onRename: { list in
                        renameListId = list.id
                        renameListText = list.name
                        showRenameList = true
                    }
                )
                .environmentObject(store)
                .environmentObject(userStore)
            } label: {
                HStack(spacing: 6) {
                    Text("Manage")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }) {
            let preview = (systemListsSorted + customListsSorted)
            if preview.isEmpty {
                EmptyShelf(text: "Create lists to organize your manga.")
            } else {
                Shelf {
                    ForEach(Array(preview.prefix(10))) { list in
                        NavigationLink {
                            UserListDetailView(list: list)
                                .environmentObject(store)
                                .environmentObject(userStore)
                        } label: {
                            ListShelfCard(
                                title: list.name,
                                subtitle: "\(seriesCount(in: list.id)) series",
                                systemImage: list.isSystem ? "lock.fill" : "list.bullet"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func seriesCount(in listId: String) -> Int {
        let keys = userStore.seriesKeys(inList: listId)
        // only count series that currently exist in library
        let existing = Set(store.series.map { $0.folderURL.seriesKey })
        return keys.filter { existing.contains($0) }.count
    }
}

private enum UserListOrderStore {
    private static let key = "manga.user.lists.order"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: key)
    }
}


// MARK: - Dashboard components

private struct DashboardSection<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) where Trailing == EmptyView {
        self.title = title
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                trailing()
            }

            content()
        }
    }
}

private struct Shelf<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                content()
            }
            .padding(.vertical, 2)
        }
    }
}

private struct EmptyShelf: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct StatChip: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CapsuleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct IconOnlyButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct WideShelfCard: View {
    let title: String
    let subtitle: String
    let coverURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LocalCoverImage(url: coverURL) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
            .frame(width: 260, height: 140)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )

            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
        }
    }
}

private struct RatedShelfCard: View {
    let series: LibraryStore.Series

    @EnvironmentObject private var userStore: UserDataStore

    var body: some View {
        HStack(spacing: 12) {
            LocalCoverImage(url: series.coverURL) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
            .frame(width: 64, height: 90)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(series.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                StarsRow(rating: userStore.rating(for: series.folderURL) ?? 0)

                let note = userStore.note(for: series.folderURL).trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct StarsRow: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= rating ? .yellow : .secondary)
            }
        }
    }
}

private struct ListShelfCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.10))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Manage Lists (reorder/edit)

private struct ManageListsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var userStore: UserDataStore

    @Binding var listOrder: [String]
    let onRename: (UserList) -> Void

    private var systemListsSorted: [UserList] {
        userStore.lists.values
            .filter { $0.isSystem }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var customListsSorted: [UserList] {
        var custom = userStore.lists.values.filter { !$0.isSystem }
        custom.sort { a, b in
            let ia = listOrder.firstIndex(of: a.id) ?? Int.max
            let ib = listOrder.firstIndex(of: b.id) ?? Int.max
            if ia == ib {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return ia < ib
        }
        return custom
    }

    var body: some View {
        List {
            if !systemListsSorted.isEmpty {
                Section("System") {
                    ForEach(systemListsSorted) { list in
                        NavigationLink {
                            UserListDetailView(list: list)
                                .environmentObject(store)
                                .environmentObject(userStore)
                        } label: {
                            listRow(list)
                        }
                    }
                }
            }

            Section("Custom") {
                if customListsSorted.isEmpty {
                    Text("Create a list from the + button.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customListsSorted) { list in
                        NavigationLink {
                            UserListDetailView(list: list)
                                .environmentObject(store)
                                .environmentObject(userStore)
                        } label: {
                            listRow(list)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                onRename(list)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                userStore.deleteList(id: list.id)
                                listOrder.removeAll { $0 == list.id }
                                UserListOrderStore.save(listOrder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: moveCustom)
                }
            }
        }
        .navigationTitle("Manage Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private func listRow(_ list: UserList) -> some View {
        HStack(spacing: 12) {
            Image(systemName: list.isSystem ? "lock.fill" : "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(list.name)
                .lineLimit(1)

            Spacer()

            Text("\(seriesCount(in: list.id))")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func moveCustom(from source: IndexSet, to destination: Int) {
        let currentIDs = customListsSorted.map { $0.id }
        var newOrder = currentIDs
        newOrder.move(fromOffsets: source, toOffset: destination)
        listOrder = newOrder
        UserListOrderStore.save(listOrder)
    }

    private func seriesCount(in listId: String) -> Int {
        let keys = userStore.seriesKeys(inList: listId)
        let existing = Set(store.series.map { $0.folderURL.seriesKey })
        return keys.filter { existing.contains($0) }.count
    }
}

// MARK: - List Detail

private struct UserListDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var userStore: UserDataStore

    let list: UserList

    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        let seriesInList = store.series
            .filter { userStore.data(for: $0.folderURL).lists.contains(list.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        List {
            if seriesInList.isEmpty {
                Text("Nothing in this list yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(seriesInList, id: \.folderURL) { s in
                    NavigationLink {
                        SeriesDetailView(series: s)
                    } label: {
                        HStack(spacing: 12) {
                            SeriesMiniCover(series: s)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).lineLimit(1)
                                let note = userStore.note(for: s.folderURL)
                                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !list.isSystem {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename") {
                            renameText = list.name
                            showRename = true
                        }
                        Button(role: .destructive) {
                            userStore.deleteList(id: list.id)
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form {
                    Section("Rename list") {
                        TextField("Name", text: $renameText)
                    }
                }
                .navigationTitle("Rename")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showRename = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            userStore.renameList(id: list.id, newName: renameText)
                            showRename = false
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Small cover thumb

private struct SeriesMiniCover: View {
    let series: LibraryStore.Series
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LocalCoverImage(url: series.coverURL) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 44, height: 64)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
        )
    }
}

private struct UserHeaderCard: View {
    let favoritesCount: Int
    let listsCount: Int
    let volumesCount: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("You")
                        .font(.title3.weight(.semibold))
                    Text("Your reading stats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                statPill(title: "Favorites", value: favoritesCount, systemImage: "star.fill")
                statPill(title: "Lists", value: listsCount, systemImage: "list.bullet")
                statPill(title: "Volumes", value: volumesCount, systemImage: "books.vertical")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func statPill(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}



// MARK: - Sign in with Apple (stub)

private struct SignInWithAppleStubButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .font(.system(size: 16, weight: .semibold))

                Text("Sign in with Apple")
                    .font(.body.weight(.semibold))

                Spacer(minLength: 0)

                Text("Coming soon")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    )
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.85)
        .accessibilityLabel("Sign in with Apple (coming soon)")
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButton: View {
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
        )
    }
}

// MARK: - Async local cover loader (theme-safe + iCloud friendly)

private struct LocalCoverImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadWithRetries()
        }
    }

    private func loadWithRetries() async {
        image = nil
        guard let url else { return }

        // A few retries helps when the cover is in iCloud and still downloading.
        let delays: [UInt64] = [0, 200_000_000, 450_000_000, 900_000_000] // ns

        for d in delays {
            if d > 0 { try? await Task.sleep(nanoseconds: d) }

            if let img = CoverImageStore.shared.load(from: url) {
                await MainActor.run { self.image = img }
                return
            }
        }
    }
}
