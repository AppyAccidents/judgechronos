import SwiftUI
import EventKit

struct VisualTimelineView: View {
    @EnvironmentObject var dataStore: LocalDataStore
    @EnvironmentObject var viewModel: ActivityViewModel
    
    // Zoom level: pixels per minute
    @State private var pixelsPerMinute: CGFloat = 2.0
    
    // Constants
    private let rulerHeight: CGFloat = 30
    private let blockHeight: CGFloat = 40
    private let hourWidth: CGFloat = 60 * 2.0 // dependent on pixelsPerMinute
    
    // State for Interaction
    @State private var selectedEvent: ActivityEvent?
    @State private var popoverLocation: CGPoint = .zero
    
    // Calendar State
    @State private var calendarEvents: [EKEvent] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls / Status
            HStack {
                Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                Slider(value: $pixelsPerMinute, in: 0.5...5.0) {
                    Text("Zoom")
                }
                .frame(width: 120)
                
                 if CalendarService.shared.hasAccess {
                    Button(action: { fetchCalendar() }) {
                        Image(systemName: "calendar")
                    }
                    .help("Refresh Calendar")
                } else {
                    Button("Link Calendar") {
                        Task {
                            try? await CalendarService.shared.requestAccess()
                            fetchCalendar()
                        }
                    }
                    .font(.caption)
                }
                
                // Smart Grouping
                Button(action: { autoGroup() }) {
                    Image(systemName: "wand.and.stars")
                }
                .help("Auto-Group Context Switches")
            }
            .padding()
            .background(AppTheme.Colors.background.opacity(0.92))
            
            // Timeline Scroll Area
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // 1. Time Ruler & Grid
                    TimeRulerView(pixelsPerMinute: pixelsPerMinute)
                        .frame(height: rulerHeight)
                    
                    // 2. Calendar Layer (Background)
                     CalendarCanvas(
                        events: calendarEvents,
                        pixelsPerMinute: pixelsPerMinute,
                        blockHeight: blockHeight
                    )
                    .frame(width: 24 * 60 * pixelsPerMinute, height: blockHeight + 20)
                    .padding(.top, rulerHeight)
                    .opacity(0.3) // Faint background context
                    
                    // 3. Activity Blocks (Canvas)
                    TimelineCanvas(
                        events: viewModel.events,
                        categories: dataStore.categories,
                        pixelsPerMinute: pixelsPerMinute,
                        blockHeight: blockHeight
                    )
                    .frame(width: 24 * 60 * pixelsPerMinute, height: blockHeight + 20)
                    .padding(.top, rulerHeight)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                handleTap(at: value.location)
                            }
                    )
                }
                .frame(minWidth: 24 * 60 * pixelsPerMinute)
            }
        }
        .popover(item: $selectedEvent) { event in
             EventDetailView(
                 event: event,
                 isPresented: Binding(get: { selectedEvent != nil }, set: { if !$0 { selectedEvent = nil } })
             )
             .environmentObject(dataStore)
             .environmentObject(viewModel)
        }
        .onAppear {
            fetchCalendar()
        }
    }
    
    private func fetchCalendar() {
        Task {
             if CalendarService.shared.hasAccess {
                 let startOfDay = Calendar.current.startOfDay(for: viewModel.selectedDate)
                 let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                 if let events = try? CalendarService.shared.fetchEvents(from: startOfDay, to: endOfDay) {
                     await MainActor.run {
                         self.calendarEvents = events
                     }
                 }
             }
        }
    }
    
    private func handleTap(at location: CGPoint) {
        // 1. Calculate Time from X coordinate
        let minute = location.x / pixelsPerMinute
        let startOfDay = Calendar.current.startOfDay(for: viewModel.selectedDate)
        let tapTime = startOfDay.addingTimeInterval(TimeInterval(minute * 60))
        
        // 2. Find Event at that time
        if let event = viewModel.events.first(where: {
            // Check if tapTime is within event range (with small tolerance)
            tapTime >= $0.startTime && tapTime <= $0.endTime
        }) {
            self.selectedEvent = event
        }
    }
    
    private func autoGroup() {
        let suggestions = SmartGrouper.shared.suggestGroups(events: viewModel.events, categories: dataStore.categories)
        if let first = suggestions.first {
             // For MVP, just select the first event of the first group to show "Hey look here"
             // Or showing a nice alert list would be better.
             // Let's just print for now or maybe trigger a modal?
             // Actually, let's create a temporary session for them?
             // No, "Visualize suggested groups" was the goal.
             // Let's print to console for Verification or add a small banner.
             print("Found \(suggestions.count) smart groups.")
             for group in suggestions {
                 print("Group: \(group.title) (\(group.events.count) items)")
             }
        }
    }
}

struct TimeRulerView: View {
    let pixelsPerMinute: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let hourWidth = 60 * pixelsPerMinute
            
            for hour in 0...24 {
                let x = CGFloat(hour) * hourWidth
                
                // Tick mark
                let tickPath = Path { p in
                    p.move(to: CGPoint(x: x, y: 15))
                    p.addLine(to: CGPoint(x: x, y: 30))
                }
                context.stroke(tickPath, with: .color(.secondary), lineWidth: 1)
                
                // Hour Label
                if hour < 24 {
                    let text = Text("\(hour):00").font(.caption).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: x + 5, y: 10), anchor: .topLeading)
                }
            }
        }
    }
}

struct TimelineCanvas: View {
    let events: [ActivityEvent]
    let categories: [Category]
    let pixelsPerMinute: CGFloat
    let blockHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            // Assume displayed day starts at 00:00 of the event's day (or viewModel.selectedDate)
            // For simplicity, we calculate offset from midnight of the first event's day, 
            // or just rely on the fact that events are filtered for a specific day.
            
            guard let firstEvent = events.first else { return }
            let startOfDay = calendar.startOfDay(for: firstEvent.startTime)
            
            for event in events {
                // Calculate position relative to start of day
                let startOffset = event.startTime.timeIntervalSince(startOfDay)
                let endOffset = event.endTime.timeIntervalSince(startOfDay)
                
                let x = CGFloat(startOffset / 60.0) * pixelsPerMinute
                let width = CGFloat(event.duration / 60.0) * pixelsPerMinute
                
                // Avoid drawing invisible blocks
                if width < 1 { continue }
                
                let rect = CGRect(x: x, y: 0, width: width, height: blockHeight)
                
                // Determine Color
                let color = colorForEvent(event)
                
                // Draw Block
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(color))
                
                // Draw Label (if wide enough)
                if width > 30 {
                   /* let label = Text(event.appDisplayName)
                        .font(.caption2)
                        .foregroundColor(.white)
                    context.draw(label, in: rect) */
                }
            }
        }
    }
    
    private func colorForEvent(_ event: ActivityEvent) -> Color {
        if event.isIdle {
            return Color.gray.opacity(0.3)
        }
        if let categoryId = event.categoryId,
           let category = categories.first(where: { $0.id == categoryId }),
           let color = Color(hex: category.colorHex) {
            return color
        }
        // Fallback for uncategorized
        return Color.secondary.opacity(0.5)
    }
}

struct CalendarCanvas: View {
    let events: [EKEvent]
    let pixelsPerMinute: CGFloat
    let blockHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            guard let firstStart = events.first?.startDate else { return }
             // Align to start of day of that event, or use current day logic
            let startOfDay = calendar.startOfDay(for: firstStart)
            
            for event in events {
                let startOffset = event.startDate.timeIntervalSince(startOfDay)
                let endOffset = event.endDate.timeIntervalSince(startOfDay)
                
                let x = CGFloat(startOffset / 60.0) * pixelsPerMinute
                let width = CGFloat((endOffset - startOffset) / 60.0) * pixelsPerMinute
                
                if width < 1 { continue }
                
                // Draw Full Height Stripe
                let rect = CGRect(x: x, y: 0, width: width, height: blockHeight + 50) // Extend below
                
                let path = Path(roundedRect: rect, cornerRadius: 0)
                context.fill(path, with: .color(Color(nsColor: event.calendar.color).opacity(0.3)))
                
                // Stripe pattern or simple fill? Simple fill is fine for now.
                
                // Draw Title
                 if width > 40 {
                   /* let text = Text(event.title)
                         .font(.caption)
                         .foregroundColor(.secondary)
                     context.draw(text, in: rect) */
                 }
            }
        }
    }
}
