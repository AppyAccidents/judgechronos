import SwiftUI

struct BrowserTrackingView: View {
    @StateObject private var browserHost = BrowserExtensionHost.shared
    @State private var showSetupSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "globe")
                    .font(.title2)
                Text("Browser Tracking")
                    .font(.title2)
                Spacer()
                Toggle("Enabled", isOn: .init(
                    get: { browserHost.isListening },
                    set: { isOn in
                        if isOn {
                            browserHost.startListening()
                        } else {
                            browserHost.stopListening()
                        }
                    }
                ))
                .toggleStyle(.switch)
            }
            
            // Setup Instructions
            if browserHost.activeSessions.isEmpty {
                SetupCard(showSetup: $showSetupSheet)
            }
            
            // Active Sessions
            if !browserHost.activeSessions.isEmpty {
                ActiveSessionsSection(sessions: browserHost.activeSessions)
            }
            
            // Recent History
            if browserHost.activeSessions.count > 0 {
                RecentHistorySection(sessions: browserHost.activeSessions)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showSetupSheet) {
            BrowserSetupSheet()
        }
        .onAppear {
            browserHost.startListening()
        }
    }
}

// MARK: - Setup Card
struct SetupCard: View {
    @Binding var showSetup: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("Install Browser Extension")
                    .font(.headline)
            }
            
            Text("Track time spent on websites by installing the browser extension for Chrome or Safari.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Set Up Extensions") {
                showSetup = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Active Sessions Section
struct ActiveSessionsSection: View {
    let sessions: [BrowserSession]
    
    private var activeOnly: [BrowserSession] {
        sessions.filter { $0.isActive }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Now")
                .font(.headline)
            
            if activeOnly.isEmpty {
                Text("No active browser sessions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(activeOnly) { session in
                    ActiveSessionRow(session: session)
                }
            }
        }
    }
}

struct ActiveSessionRow: View {
    let session: BrowserSession
    @State private var currentTime = Date()
    
    private var duration: TimeInterval {
        currentTime.timeIntervalSince(session.startTime)
    }
    
    var body: some View {
        HStack {
            // Browser icon
            Image(systemName: browserIcon(for: session.browser))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            // Domain and title
            VStack(alignment: .leading, spacing: 2) {
                Text(session.domain)
                    .font(.system(size: 13, weight: .medium))
                Text(session.title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Duration
            Text(formatDuration(duration))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
            
            // Live indicator
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
        .onAppear {
            // Update timer every second
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                currentTime = Date()
            }
        }
    }
    
    private func browserIcon(for browser: String) -> String {
        switch browser.lowercased() {
        case "chrome": return "globe"
        case "safari": return "safari"
        case "firefox": return "flame"
        default: return "globe"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recent History Section
struct RecentHistorySection: View {
    let sessions: [BrowserSession]
    
    private var completedSessions: [BrowserSession] {
        sessions
            .filter { !$0.isActive && $0.endTime != nil }
            .sorted { ($0.endTime ?? Date()) > ($1.endTime ?? Date()) }
            .prefix(10)
            .map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent History")
                .font(.headline)
            
            ForEach(completedSessions) { session in
                HistoryRow(session: session)
            }
        }
    }
}

struct HistoryRow: View {
    let session: BrowserSession
    
    var body: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.domain)
                    .font(.system(size: 12))
                if let endTime = session.endTime {
                    Text(formatTime(endTime))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let duration = session.endTime?.timeIntervalSince(session.startTime) {
                Text(formatDuration(duration))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(0.7)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes < 1 {
            return "<1m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Setup Sheet
struct BrowserSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Set Up Browser Extension")
                    .font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            
            // Browser selector
            Picker("Browser", selection: $selectedTab) {
                Text("Chrome").tag(0)
                Text("Safari").tag(1)
            }
            .pickerStyle(.segmented)
            
            // Instructions
            if selectedTab == 0 {
                ChromeInstructions()
            } else {
                SafariInstructions()
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct ChromeInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionStep(number: 1, text: "Open Chrome and navigate to chrome://extensions/")
            InstructionStep(number: 2, text: "Enable 'Developer mode' in the top right corner")
            InstructionStep(number: 3, text: "Click 'Load unpacked' button")
            InstructionStep(number: 4, text: "Select the extensions/chrome folder from the Judge Chronos app bundle")
            InstructionStep(number: 5, text: "The extension should now appear in your toolbar")
            
            Divider()
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Chrome Web Store version coming soon for easier installation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SafariInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionStep(number: 1, text: "Open Safari Preferences (Cmd + ,)")
            InstructionStep(number: 2, text: "Click on the 'Extensions' tab")
            InstructionStep(number: 3, text: "Find 'Judge Chronos Extension' in the list")
            InstructionStep(number: 4, text: "Check the box to enable it")
            InstructionStep(number: 5, text: "Grant permissions when prompted")
            
            Divider()
            
            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.green)
                Text("The Safari extension is bundled with the Judge Chronos app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    BrowserTrackingView()
        .frame(width: 600, height: 500)
}
