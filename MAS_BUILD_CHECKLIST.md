# Judge Chronos MAS Build & Submission Checklist

## Pre-Submission Status

| Item | Status |
|------|--------|
| App Record Created | ✅ |
| Bundle ID Configured | ✅ `berkerceylan.Judge-Chronos-MAS` |
| In-App Purchases Created | ✅ (3 tips) |
| IAP Localizations | ✅ |
| App Version Created | ✅ 0.1.0 |
| Build Archived | ✅ Build 4 |
| Build Uploaded | ⚠️ Use Xcode Organizer |
| Screenshots | ⬜ Required before submission |
| App Review Info | ⬜ Required before submission |
| Build Attached to Version | ⬜ After upload |
| Submitted for Review | ⬜ Final step |

## Upload Build (Current Step)

Due to an asc CLI compatibility issue with macOS PKG files, use one of these methods:

### Method 1: Xcode Organizer (Recommended)

1. Open `Judge Chronos/Judge Chronos.xcodeproj` in Xcode
2. Window → Organizer
3. Select "Judge Chronos MAS" archive (Version 0.1.0, Build 4)
4. Click "Distribute App" → "App Store Connect" → "Upload"
5. Complete the upload process

### Method 2: Transporter App

1. Install Transporter from Mac App Store
2. Drag `/tmp/JudgeChronosMASExport/Judge Chronos MAS.pkg` into Transporter
3. Click Deliver

## Post-Upload Steps

### 1. Verify Build Processing

```bash
asc builds list --app 6759955103 --output table
```

Wait for status = VALID

### 2. Attach Build to Version

```bash
# Note: First get the new build ID from the list above
asc versions attach-build \
  --version-id 9fdf47e6-ba64-4944-86fe-029a381fe11b \
  --build <NEW_BUILD_ID>
```

### 3. Complete Metadata in App Store Connect

Visit https://appstoreconnect.apple.com/apps/6759955103/appstore/macos/version/deliverable

Required fields:
- [ ] Screenshots (at least 1 for Mac)
- [ ] App Preview (optional but recommended)
- [ ] Promotional Text
- [ ] Description
- [ ] Support URL
- [ ] Marketing URL (optional)
- [ ] Privacy Policy URL
- [ ] Copyright
- [ ] Contact Information

### 4. App Review Information

**Sign-in required:** No

**Review notes:**
```
Judge Chronos MAS tracks productivity context locally on-device using frontmost app changes, optional window title tracking (Accessibility permission), and optional meeting overlays (Calendar permission).

The app does not require Full Disk Access in the Mac App Store build.

In-App Purchases (tip.small, tip.medium, tip.large) are optional consumable tips that do not unlock features.

All data remains local on the user's device. No cloud sync or accounts required.
```

**Attachment:** None required

### 5. Submit for Review

```bash
asc submit create --app 6759955103 --version 0.1.0 --platform MAC_OS --confirm
```

Or use App Store Connect web interface.

## Build Details

| Property | Value |
|----------|-------|
| App ID | 6759955103 |
| Bundle ID | berkerceylan.Judge-Chronos-MAS |
| Version | 0.1.0 |
| Build | 4 |
| Platform | macOS |
| Minimum OS | macOS 26.0 |
| Architecture | Universal (arm64 + x86_64) |
| Sandbox | Enabled |
| Entitlements | Calendar |

## In-App Purchases

| Product ID | Name | Type | Status |
|------------|------|------|--------|
| tip.small | Small Tip | Consumable | READY_TO_SUBMIT |
| tip.medium | Medium Tip | Consumable | READY_TO_SUBMIT |
| tip.large | Large Tip | Consumable | READY_TO_SUBMIT |

## Useful Commands

```bash
# Check build status
asc builds list --app 6759955103 --output table

# Check version status  
asc versions list --app 6759955103 --output table

# Check IAP status
asc iap list --app 6759955103 --output table

# View app details
asc apps get --id 6759955103
```
