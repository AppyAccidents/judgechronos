import SwiftUI

struct EventDetailView: View {
    let event: ActivityEvent
    @EnvironmentObject var dataStore: LocalDataStore
    @EnvironmentObject var viewModel: ActivityViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: App Name & Icon
            HStack {
                // Placeholder icon - in real app, fetch from NSWorkspace
                Image(systemName: "app")
                    .font(.title2)
                    .foregroundColor(AppTheme.Colors.primary)
                
                VStack(alignment: .leading) {
                    Text(event.appDisplayName)
                        .font(.headline)
                    Text(Formatting.formatDuration(event.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Window Title (The Hero Feature)
            if let title = event.windowTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WINDOW TITLE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.body)
                        // Allow text selection
                        .textSelection(.enabled)
                }
            } else {
                 Text("No specific window title tracked.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Category Picker
            VStack(alignment: .leading, spacing: 4) {
                 Text("CATEGORY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Picker("", selection: bindingForCategory) {
                    Text("Uncategorized").tag(UUID?.none)
                    ForEach(dataStore.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .labelsHidden()
            }

            // Activity Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Picker("", selection: bindingForActivity) {
                    Text("No Activity").tag(UUID?.none)
                    ForEach(dataStore.activities) { activity in
                        Text(activity.name).tag(Optional(activity.id))
                    }
                }
                .labelsHidden()
            }

            // Break Toggle
            Toggle("Mark as Break", isOn: bindingForBreak)
                .font(.caption)

            // Timestamp
            Text("\(Formatting.formatTime(event.startTime)) - \(Formatting.formatTime(event.endTime))")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .frame(width: 300)
    }
    
    private var bindingForCategory: Binding<UUID?> {
        Binding(
            get: { dataStore.assignmentForEvent(event) },
            set: { newValue in
                viewModel.updateCategory(for: event, categoryId: newValue)
            }
        )
    }

    private var bindingForActivity: Binding<UUID?> {
        Binding(
            get: {
                guard let index = dataStore.sessions.firstIndex(where: { $0.id == event.id }) else { return nil }
                return dataStore.sessions[index].activityId
            },
            set: { newValue in
                guard let index = dataStore.sessions.firstIndex(where: { $0.id == event.id }) else { return }
                var session = dataStore.sessions[index]
                session.activityId = newValue
                dataStore.updateSessionActivity(sessionId: event.id, activityId: newValue)
            }
        )
    }

    private var bindingForBreak: Binding<Bool> {
        Binding(
            get: {
                guard let index = dataStore.sessions.firstIndex(where: { $0.id == event.id }) else { return false }
                return dataStore.sessions[index].isBreak
            },
            set: { newValue in
                dataStore.updateSessionBreak(sessionId: event.id, isBreak: newValue)
            }
        )
    }
}
