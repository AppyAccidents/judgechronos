import Foundation
import CoreGraphics
import AppKit

class IdleMonitor: ObservableObject {
    static let shared = IdleMonitor()
    
    // Configurable threshold: 2 minutes
    private let idleThreshold: TimeInterval = 120
    private let pollInterval: TimeInterval = 10.0
    
    // State
    private var isIdle: Bool = false
    private var idleStartTime: Date?
    private var timer: Timer?
    
    func startMonitoring(dataStore: LocalDataStore) {
        stopMonitoring()
        
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkIdleState(dataStore: dataStore)
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkIdleState(dataStore: LocalDataStore) {
        let timeSinceInput = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .any)
        
        let wasIdle = isIdle
        isIdle = timeSinceInput >= idleThreshold
        
        if isIdle && !wasIdle {
            // TRANSITION: Active -> Idle
            // We just became idle. Mark the start time.
            // Start time is Now minus the time since input (approx)
            idleStartTime = Date().addingTimeInterval(-timeSinceInput)
            print("IdleMonitor: User went idle at \(idleStartTime!)")
        } else if !isIdle && wasIdle {
            // TRANSITION: Idle -> Active
            // User just came back.
            guard let start = idleStartTime else { return }
            let end = Date()
            let duration = end.timeIntervalSince(start)
            
            // Only record significant idle times (redundant check if threshold is high, but safe)
            if duration >= idleThreshold {
                print("IdleMonitor: User returned. Idle duration: \(duration)s")
                
                let rawEvent = RawEvent(
                    id: UUID(),
                    timestamp: start,
                    duration: duration,
                    bundleId: nil,
                    appName: "Idle", // Special name for Idle
                    windowTitle: nil,
                    source: .idle,
                    metadataHash: "idle|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))",
                    importedAt: Date()
                )
                
                Task { @MainActor in
                    // We append directly to rawEvents. 
                    // SessionManager needs to re-process or we just rely on next import/refresh?
                    // Ideally LocalDataStore handles ingestion.
                    dataStore.addRawEvent(rawEvent)
                    
                    // Trigger UI Prompt (Optional: "You were away for X mins")
                    // This could set a published property on dataStore or viewModel
                }
            }
            
            idleStartTime = nil
        }
    }
}
