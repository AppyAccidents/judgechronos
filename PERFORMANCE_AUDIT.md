# Judge Chronos - Performance Audit & Optimization Plan

## Current State Analysis

### Code Metrics
- **Swift Files**: 43 files
- **Total Lines**: ~10,572
- **Build Status**: ✅ Clean (no warnings)

### Performance Issues Identified

#### 1. LocalDataStore - Inefficient Lookups (HIGH PRIORITY)
**Issue**: Multiple O(n) array scans for lookups

```swift
// Current (inefficient)
func categoryForEvent(_ event: ActivityEvent) -> UUID? {
    if let session = sessions.first(where: { $0.id == event.id }), ...
    // Scans entire sessions array multiple times
}

// Problem: firstWhere is O(n), called repeatedly in loops
```

**Impact**: Slows down timeline rendering with large datasets

**Solution**: Use dictionary-based indexing

---

#### 2. ActivityViewModel - Unnecessary Object Creation (MEDIUM PRIORITY)
**Issue**: Creating new arrays on every refresh

```swift
// Current
let filtered = rawEvents.filter { ... }
let withIdle = insertIdleEvents(into: filtered)
events = dataStore.applyCategories(to: withIdle)
```

**Solution**: Use lazy collections or in-place mutation

---

#### 3. ProductivityEngine - Redundant Calculations (HIGH PRIORITY)
**Issue**: Recalculating scores every time view appears

```swift
// Current - recalculates everything
func calculateDailyScore(for date: Date) -> ProductivityScore
```

**Solution**: Cache scores with invalidation

---

#### 4. Missing Features from Timing.app (MEDIUM PRIORITY)

| Feature | Timing | Judge Chronos | Priority |
|---------|--------|---------------|----------|
| GrandTotal Integration | ✅ | ❌ | Low |
| Team/Sharing | ✅ | ❌ | Low |
| Advanced Filters | ✅ | Partial | Medium |
| Time Entry Editing | ✅ | Partial | Medium |
| Keyboard Shortcuts | ✅ | ❌ | Medium |
| Data Import from other apps | ✅ | ❌ | Low |

---

## Optimization Plan

### Phase 1: LocalDataStore Optimization
- Add dictionary-based session index
- Add project lookup cache
- Optimize category assignment

### Phase 2: ViewModel Optimization  
- Implement lazy loading
- Add pagination for large datasets
- Reduce unnecessary refreshes

### Phase 3: Productivity Engine Caching
- Cache daily scores
- Cache hourly productivity
- Invalidate on data changes

### Phase 4: Code Cleanup
- Remove unused code
- Consolidate duplicate logic
- Add performance tests

