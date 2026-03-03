import SwiftUI

// MARK: - Project Tree Node
struct ProjectNode: Identifiable {
    let id: UUID
    let project: Project
    var children: [ProjectNode]
    var level: Int
    var isExpanded: Bool
}

// MARK: - Project Hierarchy View
struct ProjectHierarchyView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var expandedProjectIds: Set<UUID> = []
    @State private var selectedProjectId: UUID?
    @State private var showingAddSheet = false
    @State private var editingProject: Project?
    @State private var draggedProject: Project?
    @State private var dropTargetId: UUID?
    @State private var searchText = ""
    @State private var showArchived = false
    
    private var projectTree: [ProjectNode] {
        buildTree(projects: filteredProjects, parentId: nil, level: 0)
    }
    
    private var filteredProjects: [Project] {
        let base = showArchived ? dataStore.projects : dataStore.projects.filter { !$0.archived }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and Filter Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Toggle("Show Archived", isOn: $showArchived)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Project Tree
            List {
                ForEach(projectTree) { node in
                    ProjectNodeView(
                        node: node,
                        expandedIds: $expandedProjectIds,
                        selectedId: $selectedProjectId,
                        dropTargetId: $dropTargetId,
                        onExpandToggle: { toggleExpansion(node.id) },
                        onSelect: { selectedProjectId = node.id },
                        onEdit: { editingProject = node.project },
                        onDelete: { deleteProject(node.project) },
                        onDrop: { handleDrop(dropped: $0, onto: node.project) }
                    )
                    .listRowBackground(selectedProjectId == node.id ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                
                if projectTree.isEmpty {
                    EmptyProjectsView()
                }
            }
            .listStyle(.plain)
            
            // Bottom Toolbar
            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Project", systemImage: "plus")
                }
                
                Spacer()
                
                if let selectedId = selectedProjectId,
                   let project = dataStore.projects.first(where: { $0.id == selectedId }) {
                    Text("\(project.name) selected")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingAddSheet) {
            ProjectEditorView(project: nil) { newProject in
                dataStore.addProject(newProject)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project) { updated in
                dataStore.updateProject(updated)
                editingProject = nil
            }
        }
    }
    
    // MARK: - Tree Building
    private func buildTree(projects: [Project], parentId: UUID?, level: Int) -> [ProjectNode] {
        projects
            .filter { $0.parentId == parentId }
            .sorted { $0.createdAt < $1.createdAt }
            .map { project in
                ProjectNode(
                    id: project.id,
                    project: project,
                    children: buildTree(projects: projects, parentId: project.id, level: level + 1),
                    level: level,
                    isExpanded: expandedProjectIds.contains(project.id)
                )
            }
    }
    
    // MARK: - Actions
    private func toggleExpansion(_ projectId: UUID) {
        if expandedProjectIds.contains(projectId) {
            expandedProjectIds.remove(projectId)
        } else {
            expandedProjectIds.insert(projectId)
        }
    }
    
    private func deleteProject(_ project: Project) {
        // Check if project has children
        let hasChildren = dataStore.projects.contains { $0.parentId == project.id }
        if hasChildren {
            // Show confirmation dialog about child projects
        }
        dataStore.deleteProject(project)
    }
    
    private func handleDrop(dropped: Project, onto target: Project) {
        // Prevent dropping onto itself or its descendants
        guard dropped.id != target.id else { return }
        guard !isDescendant(projectId: target.id, of: dropped.id) else { return }
        
        // Move the project
        dataStore.moveProject(dropped.id, toParent: target.id)
        dropTargetId = nil
    }
    
    private func isDescendant(projectId: UUID, of ancestorId: UUID) -> Bool {
        let children = dataStore.projects.filter { $0.parentId == ancestorId }
        for child in children {
            if child.id == projectId || isDescendant(projectId: projectId, of: child.id) {
                return true
            }
        }
        return false
    }
}

// MARK: - Project Node View
struct ProjectNodeView: View {
    let node: ProjectNode
    @Binding var expandedIds: Set<UUID>
    @Binding var selectedId: UUID?
    @Binding var dropTargetId: UUID?
    let onExpandToggle: () -> Void
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDrop: (Project) -> Void
    
    @State private var isDragging = false
    @State private var isTargeted = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Indentation
            ForEach(0..<node.level, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
            }
            
            // Expand/Collapse Button
            if node.children.isEmpty {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 20)
            } else {
                Button(action: onExpandToggle) {
                    Image(systemName: expandedIds.contains(node.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
            }
            
            // Project Color Indicator
            Circle()
                .fill(Color(hex: node.project.colorHex) ?? .gray)
                .frame(width: 10, height: 10)
            
            // Project Name
            Text(node.project.name)
                .font(.system(size: 13))
            
            if node.project.archived {
                Text("(Archived)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Productivity Indicator
            if let rating = node.project.productivityRating {
                Image(systemName: rating.icon)
                    .foregroundColor(rating.color)
                    .font(.caption)
                    .help(rating.label)
            }
            
            // Billable Indicator
            if node.project.isBillable {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.green)
                    .font(.caption)
                    .help("Billable")
            }
            
            // Context Menu
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture { onSelect() }
        .onDrag {
            isDragging = true
            return NSItemProvider(object: node.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            // Handle drop
            return true
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(action: { /* Add child */ }) {
                Label("Add Child Project", systemImage: "plus")
            }
            
            Divider()
            
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
        
        // Render children if expanded
        if expandedIds.contains(node.id) {
            ForEach(node.children) { childNode in
                ProjectNodeView(
                    node: childNode,
                    expandedIds: $expandedIds,
                    selectedId: $selectedId,
                    dropTargetId: $dropTargetId,
                    onExpandToggle: {
                        if expandedIds.contains(childNode.id) {
                            expandedIds.remove(childNode.id)
                        } else {
                            expandedIds.insert(childNode.id)
                        }
                    },
                    onSelect: { selectedId = childNode.id },
                    onEdit: onEdit,
                    onDelete: onDelete,
                    onDrop: onDrop
                )
            }
        }
    }
}

// MARK: - Empty State
struct EmptyProjectsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Projects Yet")
                .font(.headline)
            
            Text("Create your first project to organize your time")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Project Editor View
struct ProjectEditorView: View {
    let project: Project?
    let onSave: (Project) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedColor: Color = .blue
    @State private var parentId: UUID?
    @State private var productivityRating: ProductivityRating?
    @State private var hourlyRate: String = ""
    @State private var isBillable = false
    @State private var archived = false
    
    @EnvironmentObject private var dataStore: LocalDataStore
    
    private var isEditing: Bool { project != nil }
    
    private var availableParents: [Project] {
        dataStore.projects.filter { $0.id != project?.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Project" : "New Project")
                .font(.title2)
            
            Form {
                // Name
                TextField("Project Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                // Color
                HStack {
                    Text("Color")
                    Spacer()
                    ColorPicker("", selection: $selectedColor)
                        .labelsHidden()
                }
                
                // Parent Project
                Picker("Parent Project", selection: $parentId) {
                    Text("None (Top Level)").tag(UUID?.none)
                    ForEach(availableParents) { parent in
                        Text(parent.name).tag(Optional(parent.id))
                    }
                }
                
                // Productivity Rating
                Picker("Productivity", selection: $productivityRating) {
                    Text("Not Set").tag(ProductivityRating?.none)
                    ForEach(ProductivityRating.allCases, id: \.self) { rating in
                        HStack {
                            Image(systemName: rating.icon)
                                .foregroundColor(rating.color)
                            Text(rating.label)
                        }
                        .tag(Optional(rating))
                    }
                }
                
                // Billable
                Toggle("Billable", isOn: $isBillable)
                
                if isBillable {
                    HStack {
                        Text("Hourly Rate")
                        TextField("0.00", text: $hourlyRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("$")
                    }
                }
                
                if isEditing {
                    Toggle("Archived", isOn: $archived)
                }
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let project = project {
                name = project.name
                selectedColor = Color(hex: project.colorHex) ?? .blue
                parentId = project.parentId
                productivityRating = project.productivityRating
                hourlyRate = project.hourlyRate.map { String($0) } ?? ""
                isBillable = project.isBillable
                archived = project.archived
            }
        }
    }
    
    private func save() {
        let rate = Double(hourlyRate.replacingOccurrences(of: ",", with: "."))
        
        let newProject = Project(
            id: project?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: selectedColor.toHex(),
            parentId: parentId,
            productivityRating: productivityRating,
            hourlyRate: rate,
            isBillable: isBillable,
            archived: archived,
            createdAt: project?.createdAt ?? Date()
        )
        
        onSave(newProject)
    }
}
