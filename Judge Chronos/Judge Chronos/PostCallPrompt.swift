import SwiftUI

struct PostCallPrompt: View {
    let call: DetectedCall
    @EnvironmentObject private var dataStore: LocalDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProjectId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var note: String = ""
    @State private var isBillable: Bool = true
    
    private var suggestedProject: String? {
        CallDetector.shared.getSuggestedProject(for: call)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: call.app.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Call Ended")
                    .font(.title2)
                
                Text("\(call.app.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let title = call.title {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Duration badge
                HStack {
                    Image(systemName: "clock")
                    Text("Duration: \(call.formattedDuration)")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(16)
            }
            
            Divider()
            
            // Project Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Log this time to:")
                    .font(.headline)
                
                // Suggested project
                if let suggested = suggestedProject,
                   let projectId = dataStore.projects.first(where: { $0.name == suggested })?.id {
                    SuggestedProjectButton(
                        projectName: suggested,
                        isSelected: selectedProjectId == projectId
                    ) {
                        selectedProjectId = projectId
                    }
                }
                
                // Project picker
                Picker("Project", selection: $selectedProjectId) {
                    Text("Select a project...").tag(UUID?.none)
                    ForEach(dataStore.projects.filter { !$0.archived }) { project in
                        HStack {
                            Circle()
                                .fill(Color(hex: project.colorHex) ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                        }
                        .tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                
                // Category picker (if no project selected or in addition)
                if selectedProjectId == nil {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Select category...").tag(UUID?.none)
                        ForEach(dataStore.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Note
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("What was this call about?", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Billable toggle
                if let projectId = selectedProjectId,
                   let project = dataStore.projects.first(where: { $0.id == projectId }),
                   project.isBillable {
                    Toggle("Billable time", isOn: $isBillable)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Skip") {
                    skip()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Log Time") {
                    logTime()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProjectId == nil && selectedCategoryId == nil)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    private func logTime() {
        // Create a session from the call
        let session = Session(
            id: UUID(),
            startTime: call.startTime,
            endTime: call.endTime ?? Date(),
            sourceApp: call.app.displayName,
            bundleId: call.app.bundleIdentifier,
            lastWindowTitle: call.title ?? "Video Call",
            windowTitleSamples: [call.title ?? "Video Call"],
            overlappingMeetingIds: [],
            rawEventIds: [],
            projectId: selectedProjectId,
            categoryId: selectedCategoryId,
            tagIds: [],
            note: note.isEmpty ? nil : note,
            isPrivate: false,
            isIdle: false
        )
        
        // Add to data store
        dataStore.addSession(session)
        
        // Mark as logged
        CallDetector.shared.markCallAsLogged(call.id)
        
        dismiss()
    }
    
    private func skip() {
        CallDetector.shared.dismissCall(call.id)
        dismiss()
    }
}

struct SuggestedProjectButton: View {
    let projectName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Suggested: \(projectName)")
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.yellow.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Call Prompt Manager
@MainActor
final class CallPromptManager: ObservableObject {
    static let shared = CallPromptManager()
    
    @Published var showingPrompt = false
    @Published var currentCall: DetectedCall?
    
    private init() {
        // Set up callback when call ends
        CallDetector.shared.onCallEnded = { [weak self] call in
            guard self?.shouldShowPrompt(for: call) == true else { return }
            
            DispatchQueue.main.async {
                self?.currentCall = call
                self?.showingPrompt = true
            }
        }
    }
    
    private func shouldShowPrompt(for call: DetectedCall) -> Bool {
        // Only show prompt for calls longer than 5 minutes
        return call.duration >= 300
    }
    
    func dismiss() {
        showingPrompt = false
        currentCall = nil
    }
}

// MARK: - Preview
#Preview {
    let call = DetectedCall(
        app: .zoom,
        startTime: Date().addingTimeInterval(-1800),
        endTime: Date(),
        title: "Daily Standup",
        participants: nil,
        isActive: false
    )
    
    return PostCallPrompt(call: call)
        .environmentObject(LocalDataStore.shared)
}
