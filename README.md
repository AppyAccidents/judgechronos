# Judge Chronos

**Judge Chronos** is an open-source, privacy-focused time-tracking application built exclusively for macOS. It helps users understand and organize their digital activity by extracting, categorizing, and visualizing app usage data, all while respecting user privacy and system integrity.

## Core Pillars
- **Privacy First**: All data remains local. No cloud sync, no accounts required.
- **Immutable Extraction**: Raw system events are never modified. We derive a logical timeline from them.
- **Automation with Intent**: A priority-based rules engine that explains *why* it categorized something.
- **Data Portability**: Full, lossless JSON export of your entire tracking history and rules.

## Features
- **Incremental Import**: Efficiently syncs with macOS `knowledgeC.db` using watermark-based ingestion.
- **derived Timeline**: Automatically merges raw events into "Sessions" to preserve original data while allowing logical edits.
- **Rules Engine**: priority-based automation with full audit logs (explained in the UI).
- **Pro Reporting**: Advanced aggregation by Project, Category, and Tag with trend analysis support.
- **Idle Detection**: Automatically clusters gaps in activity as "Idle" time.
- **Full Disk Access Onboarding**: Streamlined setup process that respects macOS security requirements.

## Architecture
The app follows a strict tiered logic model:
1. **Extraction**: `KnowledgeCReader` pulls raw `knowledgeC.db` events.
2. **Persistence**: `LocalDataStore` manages a versioned local JSON backup.
3. **Derivation**: `SessionManager` transforms raw events into editable `Session` entities.
4. **Automation**: `RulesEngine` applies user-defined logic to the derived timeline.
5. **Reporting**: `ReportingService` aggregates the result for visualization.

## Tech Stack
- **Swift / SwiftUI**: Native macOS experience.
- **SQLite**: Direct interaction with system databases.
- **Charts**: Native SwiftUI Charting.
- **Apple Intelligence**: Integrated categorization suggestions (macOS 15+).

## License
MIT License

---

*Judge Chronos is in active development. Contributions and feedback are welcome!*