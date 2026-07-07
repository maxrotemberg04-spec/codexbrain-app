import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: $state.selection) {
            Label("Dashboard", systemImage: "sparkle")
                .tag(SidebarItem.dashboard)
            Label("Calendar", systemImage: "calendar")
                .tag(SidebarItem.calendar)
            Label("Graph", systemImage: "circle.hexagongrid")
                .tag(SidebarItem.graph)
            ForEach(state.roots) { root in
                Section(root.name) {
                    HStack {
                        Label("All Notes", systemImage: "doc.text")
                        Spacer()
                        Text("\(state.count(for: .all(root.id)))")
                            .font(Theme.mono)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.all(root.id))
                    ForEach(state.topFolders(of: root), id: \.name) { folder in
                        HStack {
                            Label(folder.name, systemImage: FolderCard.icon(for: folder.name))
                            Spacer()
                            Text("\(folder.count)")
                                .font(Theme.mono)
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.folder(root.id, folder.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SidebarMaterial().ignoresSafeArea())
        .navigationSplitViewColumnWidth(min: 210, ideal: 238)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Button {
                    state.addFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                Text(state.statusLine)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BrowseSplit: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            if state.showNoteList {
                NoteListView()
                    .frame(minWidth: 270, idealWidth: 320, maxWidth: 460)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            NoteDetailView()
                .frame(minWidth: 460, maxWidth: .infinity)
        }
        .animation(Theme.reduceMotion ? nil : .easeOut(duration: 0.18), value: state.showNoteList)
        .background(Theme.bg)
        .toolbar { DashboardToolbar() }
    }
}

struct NoteListView: View {
    @EnvironmentObject var state: AppState

    var notes: [Note] { state.notesFor(state.selection) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search titles and contents", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(10)

            Divider()

            if notes.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(state.searchText.isEmpty ? "No notes in this folder yet" : "No match")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                    if !state.searchText.isEmpty {
                        Text("Scoring covers titles, folders, and full contents.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(notes, selection: $state.selectedNoteID) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bg)
    }
}

struct NoteRow: View {
    let note: Note
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("\(note.folder.isEmpty ? note.rootName : note.folder) · \(Self.day.string(from: note.modified))")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            if !note.description.isEmpty {
                Text(note.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}
