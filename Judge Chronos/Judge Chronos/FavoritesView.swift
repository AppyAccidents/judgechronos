import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var showingAddSheet = false
    @State private var editingFavorite: Favorite?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "star")
                    .font(.title2)
                Text("Favorites")
                    .font(.title2)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Label("Add Favorite", systemImage: "plus")
                }
            }
            .padding()

            if dataStore.favorites.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Favorites Yet")
                        .font(.headline)
                    Text("Create quick-entry bookmarks for common tasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(dataStore.favorites.sorted(by: { $0.sortOrder < $1.sortOrder })) { favorite in
                            FavoriteCard(favorite: favorite)
                                .contextMenu {
                                    Button("Edit") { editingFavorite = favorite }
                                    Divider()
                                    Button("Delete") { dataStore.deleteFavorite(favorite) }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            FavoriteEditorView(favorite: nil) { newFav in
                dataStore.addFavorite(newFav)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingFavorite) { fav in
            FavoriteEditorView(favorite: fav) { updated in
                dataStore.updateFavorite(updated)
                editingFavorite = nil
            }
        }
    }
}

// MARK: - Favorite Card
struct FavoriteCard: View {
    let favorite: Favorite
    @EnvironmentObject private var dataStore: LocalDataStore

    private var projectName: String {
        dataStore.projectName(for: favorite.projectId)
    }

    private var activityName: String {
        dataStore.activityName(for: favorite.activityId)
    }

    private var projectColor: Color {
        guard let pid = favorite.projectId,
              let project = dataStore.projects.first(where: { $0.id == pid }) else {
            return .gray
        }
        return Color(hex: project.colorHex) ?? .gray
    }

    var body: some View {
        Button(action: startTimer) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(projectColor)
                        .frame(width: 10, height: 10)
                    Text(projectName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if favorite.isBillable {
                        Image(systemName: "dollarsign.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Text(activityName)
                    .font(.subheadline)

                if let desc = favorite.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Start Timer")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func startTimer() {
        _ = ManualTimerService.shared.startTimer(
            dataStore: dataStore,
            projectId: favorite.projectId,
            activityId: favorite.activityId,
            description: favorite.description,
            isBillable: favorite.isBillable
        )
    }
}

// MARK: - Favorite Editor
struct FavoriteEditorView: View {
    let favorite: Favorite?
    let onSave: (Favorite) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: LocalDataStore

    @State private var projectId: UUID?
    @State private var activityId: UUID?
    @State private var description = ""
    @State private var isBillable = true
    @State private var sortOrder = 0

    private var isEditing: Bool { favorite != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Favorite" : "New Favorite")
                .font(.title2)

            Form {
                Picker("Project", selection: $projectId) {
                    Text("None").tag(UUID?.none)
                    ForEach(dataStore.projects.filter { !$0.archived }) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker("Activity", selection: $activityId) {
                    Text("None").tag(UUID?.none)
                    ForEach(dataStore.activitiesForProject(projectId)) { activity in
                        Text(activity.name).tag(Optional(activity.id))
                    }
                }

                TextField("Description", text: $description)
                    .textFieldStyle(.roundedBorder)

                Toggle("Billable", isOn: $isBillable)

                Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...100)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let fav = favorite {
                projectId = fav.projectId
                activityId = fav.activityId
                description = fav.description ?? ""
                isBillable = fav.isBillable
                sortOrder = fav.sortOrder
            }
        }
    }

    private func save() {
        let fav = Favorite(
            id: favorite?.id ?? UUID(),
            projectId: projectId,
            activityId: activityId,
            description: description.isEmpty ? nil : description,
            isBillable: isBillable,
            sortOrder: sortOrder
        )
        onSave(fav)
    }
}
