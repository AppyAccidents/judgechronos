# Judge Chronos - Feature Implementation Plan
## Closing the Gap with Timing.app

### Current State Analysis
- **Feature Parity**: ~70% with Timing.app
- **Architecture**: Well-structured SwiftUI app with clean separation
- **Data Models**: Project model exists with parentId, Sessions have projectId
- **Gaps**: Hierarchy not used, limited exports, no productivity scoring, no call detection

---

## Phase 1: Hierarchical Projects System (HIGH PRIORITY)

### Goal
Transform flat Categories into Timing-style hierarchical Projects with drag-and-drop rule creation.

### Implementation

#### 1.1 Data Model Updates
```swift
// Extend Project model
struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var parentId: UUID?
    var productivityScore: ProductivityRating? // NEW
    var hourlyRate: Double? // NEW for invoicing
    var isBillable: Bool // NEW
    var archived: Bool // NEW
}

enum ProductivityRating: Int, Codable, CaseIterable {
    case veryDistracting = -2
    case distracting = -1
    case neutral = 0
    case productive = 1
    case veryProductive = 2
}
```

#### 1.2 UI Components
- **ProjectHierarchyView**: Tree view with expand/collapse
- **ProjectRow**: Draggable row with indentation indicator
- **ProjectDetailView**: Edit project with parent selector, rate, productivity
- **DragDropOverlay**: Visual feedback during drag operations

#### 1.3 Files to Create/Modify
- `ProjectHierarchyView.swift` (NEW)
- `ProjectDetailView.swift` (NEW)
- `LocalDataStore.swift` - Add hierarchy methods
- `ContentView.swift` - Replace Categories with Projects tab

**Estimation: 2-3 days**

---

## Phase 2: Browser Extension for URL Tracking (HIGH PRIORITY)

### Goal
Track actual website URLs, not just window titles like "Chrome — GitHub"

### Implementation

#### 2.1 Browser Extensions
- **Chrome Extension**: manifest v3, content script, native messaging
- **Safari Extension**: Safari App Extension with native messaging
- **Firefox Extension**: WebExtensions API

#### 2.2 Native Messaging Host
```swift
final class BrowserExtensionHost: ObservableObject {
    func handleMessage(browser: String, url: String, title: String)
}
```

#### 2.3 Files to Create
- `BrowserExtensionHost.swift`
- `extensions/chrome/`
- `extensions/safari/`

**Estimation: 3-4 days**

---

## Phase 3: PDF & XLSX Export for Invoicing (HIGH PRIORITY)

### Goal
Professional invoice-ready reports like Timing's

### Implementation

#### 3.1 PDF Export (PDFKit)
- Invoice templates with logo
- Line items with hourly rates
- Tax calculation
- Professional styling

#### 3.2 XLSX Export (CoreXLSX)
- Multiple sheets (Summary, Details)
- Formulas for totals
- Conditional formatting

#### 3.3 Files to Create
- `PDFReportGenerator.swift`
- `XLSXReportGenerator.swift`
- `ReportBuilderView.swift`

**Estimation: 3-4 days**

---

## Phase 4: Productivity Scoring System (MEDIUM PRIORITY)

### Goal
Rate projects by productivity, track trends over time

### Implementation

#### 4.1 Data Model
```swift
enum ProductivityRating: Int {
    case veryDistracting = -2
    case distracting = -1
    case neutral = 0
    case productive = 1
    case veryProductive = 2
}
```

#### 4.2 Features
- Daily productivity scores
- Trend analysis
- Peak hours detection
- Distracting app insights

#### 4.3 Files to Create
- `ProductivityEngine.swift`
- `ProductivityDashboard.swift`
- `ProductivityHeatmap.swift`

**Estimation: 2-3 days**

---

## Phase 5: Post-Call Detection & Prompts (MEDIUM PRIORITY)

### Goal
Detect video/voice calls and prompt for time logging

### Implementation

#### 5.1 Call Detection
- Zoom: "Zoom Meeting" window detection
- Teams: Call window detection
- Meet: Browser extension
- Slack: Huddle detection

#### 5.2 Post-Call Prompt
- Detect call end
- Show project selector
- One-tap logging

#### 5.3 Files to Create
- `CallDetector.swift`
- `PostCallPrompt.swift`

**Estimation: 2 days**

---

## Phase 6: Multi-language Localization (MEDIUM PRIORITY)

### Goal
Support EN, DE, FR, JA, ES like Timing

### Implementation
- String Catalogs (.xcstrings)
- RTL support considerations
- Professional translation service

**Estimation: 2-3 days**

---

## Phase 7: llms.txt Documentation (LOW PRIORITY)

### Goal
Machine-readable documentation for LLMs

### Files
- `llms.txt` - Summary for LLMs
- `llms-full.txt` - Detailed documentation

**Estimation: 0.5 day**

---

## Timeline Summary

| Phase | Feature | Priority | Est. Days |
|-------|---------|----------|-----------|
| 1 | Hierarchical Projects | High | 2-3 |
| 2 | Browser Extension | High | 3-4 |
| 3 | PDF/XLSX Export | High | 3-4 |
| 4 | Productivity Scoring | Medium | 2-3 |
| 5 | Post-Call Prompts | Medium | 2 |
| 6 | Localization | Medium | 2-3 |
| 7 | llms.txt | Low | 0.5 |

**Total: 15-20 days (~3-4 weeks)**

---

## Dependencies to Add

```swift
// Package.swift
.package(url: "https://github.com/CoreOffice/CoreXLSX", from: "0.14.0")
```

---

## Next Steps

1. Review and approve this plan
2. Create feature branches
3. Start with Phase 1 (Hierarchical Projects)
4. Test incrementally
