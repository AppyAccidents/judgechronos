# Judge Chronos Roadmap

## High-Impact Improvements

### 1) “Immutable raw data + derived views” (trust + auditability)
* Keep **raw events** (from `knowledgeC.db`) strictly read-only and never modified.
* Store **derived artifacts** separately:
    * classifications (project/category/tag assignments)
    * rule decisions (which rule matched, when, and why)
    * user annotations (notes, “this was work”, “meeting”, etc.)
* Add an “Explain” panel: *“This event was categorized as ‘Client A’ because Rule #12 matched bundle id + window title regex.”*

### 2) Better categorization inputs (still privacy-first)
* Rules based on:
    * app bundle identifier
    * app name
    * **window title** (optional; requires Accessibility permission; make it opt-in)
    * time of day / weekday
    * minimum duration threshold
* Add **tags** and **hierarchical projects** (e.g., Work → Client A → Feature X).

### 3) Editing without “lying”
Even if the timeline is non-editable, users need corrections:
* Allow **splitting/merging sessions** in a “Derived Sessions” layer.
* Allow marking ranges as:
    * “Away / Idle”
    * “Private” (hidden from charts/exports)
    * “Uncategorized”
This keeps raw extraction honest while making reporting usable.

### 4) Menubar + quick controls (daily usefulness)
* Menubar widget:
    * today’s totals (top project/app)
    * current active app (if determinable)
    * start “Focus Session” (optional)
* Hotkeys for:
    * quick assign last 30 minutes to a project
    * quick add note

### 5) Reporting that answers real questions
* Weekly review:
    * trend vs last week
    * “Top context switches” (app switches/hour)
    * “Deep work blocks” (long uninterrupted sessions)
* Budgets/goals:
    * “Max 2 h social media/day”
    * “Min 3 h project X/week”
* “Compare” mode: project A vs B, weekdays vs weekends.

### 6) Export/import ecosystem
* CSV is good; add:
    * JSON export (lossless, includes rule explanations)
    * “Timesheet export” format (daily totals per project)
    * optional integrations later (Toggl/Clockify) via exporter plugins

### 7) Privacy/security hardening (critical for this product positioning)
* Explicit data policy in-app:
    * “All data stays on-device”
    * no analytics by default
* Optional **local database encryption** (at least for derived data) or “privacy lock” that hides charts until unlocked.
* Data retention controls:
    * auto-delete raw events older than N days (if user wants)

### 8) Resilience against macOS changes
Reading `knowledgeC.db` can be fragile across macOS versions:
* Build a **schema adapter** layer:
    * detect columns/tables present
    * graceful degradation if fields disappear
* Add diagnostics page:
    * last successful import time
    * permissions status
    * what source fields are currently available

---

## Milestones

| Phase | Outcome | Key deliverables | Status |
|---|---|---|---|
| 0 | Solid foundation | Data model, import pipeline skeleton, test fixtures, CI | ✅ |
| 1 | Reliable extraction | Incremental import, deduplication, permissions UX, diagnostics | ✅ |
| 2 | Usable organization | Projects/categories/tags, manual assign UI, fast search/filter | ✅ |
| 3 | Automation | Rules engine, audit logs, "Don't Lie" manual overrides | ✅ |
| 4 | Reporting + export | Advanced aggregation, trend analysis, CSV+JSON exports | ✅ |
| 5 | UI Integration | Rule Editor, Session Audit, Settings panels | ✅ |
| 6 | Distribution Ready | Hygiene, README architecture, Code of Conduct | ✅ |
| 7 | Next Gen (Post-MVP) | Menubar app, Local Encryption, Apple Intel enhancements | 🗺️ |

---

## Phase 0 — Foundation (1–2 weeks)
* **Repo hygiene**
    * `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue templates
    * Define “privacy stance” in `README` (what you read, what you store, where)
* **Data model draft**
    * `RawEvent(id, start, end, bundleId, appName, source, metadataHash, importedAt)`
    * `Project/Category/Tag`
    * `Session(id, start, end, rawEventRefs, overrides…)`
    * `Rule(id, priority, enabled, conditions, targetProject, targetTags, stopOnMatch)`
* **Testing harness**
    * Include a **sanitized sample SQLite fixture** or a generator
    * Unit tests for:
        * timestamp parsing
        * deduplication
        * sessionization logic

## Phase 1 — Extraction you can depend on (2–4 weeks)
* **Incremental import**
    * Store a watermark: last imported timestamp + last row identifier if available
    * Import in pages (avoid loading huge ranges into memory)
* **Deduplication strategy**
    * Use a stable `metadataHash` based on key fields (time range + bundle id + source row id where possible)
* **Idle detection (baseline)**
    * Compute idle segments by gaps > threshold (user-configurable)
    * Mark idle as its own derived session type (not raw)
* **Permissions + onboarding**
    * Full Disk Access steps with:
        * “Check again” button
        * “Why we need this” explanation
* **Diagnostics page**
    * Show: permission status, database path used, last import time, last error (sanitized)
