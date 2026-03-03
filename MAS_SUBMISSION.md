# Judge Chronos Mac App Store Submission Guide

## Current Status

✅ **App Record**: Created (ID: 6759955103)  
✅ **IAPs**: 3 consumable tips created (tip.small, tip.medium, tip.large)  
✅ **Build**: Archived and ready for upload (Version 0.1.0, Build 4)  
⚠️ **Upload**: Requires manual upload via Xcode due to asc CLI UTI compatibility issue

---

## Upload Instructions (Xcode Method)

### Option 1: Using Xcode Organizer (Recommended)

1. Open the project in Xcode:
   ```bash
   open "Judge Chronos/Judge Chronos.xcodeproj"
   ```

2. Go to **Window → Organizer** (or press Cmd+Shift+Option+O)

3. Select **"Judge Chronos MAS"** from the sidebar

4. Select the latest archive (should show version 0.1.0, build 4)

5. Click **"Distribute App"**

6. Select **"App Store Connect"** → Click **Next**

7. Select **"Upload"** → Click **Next**

8. Ensure these options are checked:
   - ☑️ Upload your app's symbols
   - ☑️ Upload your app's bitcode (if available)

9. Click **Upload**

10. Wait for upload to complete (this may take a few minutes)

---

### Option 2: Using Pre-built PKG

If you have the PKG file already exported at `/tmp/JudgeChronosMASExport/Judge Chronos MAS.pkg`:

1. Open **Transporter** app (download from Mac App Store if not installed)

2. Drag the PKG file into Transporter

3. Click **Deliver**

---

## Post-Upload Steps

### 1. Wait for Build Processing

After upload, the build needs to be processed by Apple:

```bash
# Check build status (run this periodically)
asc builds list --app 6759955103 --output table
```

Wait until the **Processing** column shows **VALID**.

### 2. Attach Build to Version

Once the build is processed, attach it to version 0.1.0:

```bash
# Get the build ID from the list above, then:
asc versions attach-build \
  --version-id 9fdf47e6-ba64-4944-86fe-029a381fe11b \
  --build <BUILD_ID>
```

### 3. Verify IAPs in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. Select Judge Chronos → Features → In-App Purchases
3. Ensure all 3 tips are present and status is "Ready to Submit"

### 4. Submit for Review

```bash
# Create review submission
asc review submissions-create --app 6759955103 --platform MAC_OS
```

Or submit via the App Store Connect web interface:
1. Go to App Store → Judge Chronos → 0.1.0
2. Click **"Submit for Review"**
3. Answer the export compliance and content rights questions
4. Submit

---

## App Review Information

**Suggested Review Notes:**

```
Judge Chronos MAS tracks productivity context locally on-device using:
- Frontmost app changes (via NSWorkspace notifications)
- Optional window title tracking (Accessibility permission)
- Optional meeting overlays (Calendar permission)

The app does not require Full Disk Access in the Mac App Store build.

In-App Purchases:
- tip.small, tip.medium, tip.large are optional consumable tips
- They do not unlock any features
- They are purely for supporting development

All data remains local on the user's device. No cloud sync or accounts required.
```

---

## Technical Details

### Build Configuration
- **Bundle ID**: `berkerceylan.Judge-Chronos-MAS`
- **Version**: 0.1.0
- **Build**: 4
- **Target**: macOS 26.0+
- **Architecture**: Universal (arm64 + x86_64)

### Entitlements (MAS)
```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.personal-information.calendars</key>
    <true/>
</dict>
```

### In-App Purchases
| Product ID | Type | Status |
|------------|------|--------|
| tip.small | Consumable | READY_TO_SUBMIT |
| tip.medium | Consumable | READY_TO_SUBMIT |
| tip.large | Consumable | READY_TO_SUBMIT |

---

## Known Issues

### asc CLI UTI Detection
The asc CLI tool has a compatibility issue with PKG files exported on macOS 26.x:
- **Error**: `'com.apple.installer-package-archive' is not a valid value for the attribute 'uti'`
- **Workaround**: Use Xcode Organizer or Transporter app for upload
- **Status**: This is a known issue with asc CLI v0.36.0 on newer macOS versions

---

## Quick Reference Commands

```bash
# Check app status
asc apps get --id 6759955103

# Check builds
asc builds list --app 6759955103 --output table

# Check IAPs
asc iap list --app 6759955103 --output table

# Check version status
asc versions list --app 6759955103 --output table

# View submission status
asc review submissions list --app 6759955103 --output table
```

---

## Support

For issues with:
- **Build/upload**: Check Xcode build logs in `/tmp/JudgeChronosMASExport/Packaging.log`
- **App Store Connect**: Visit https://appstoreconnect.apple.com
- **asc CLI**: Run `asc auth doctor` to verify authentication
