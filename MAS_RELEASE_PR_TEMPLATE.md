# PR Template: Mac App Store Release (Judge Chronos MAS)

## Title
`MAS release readiness: sandbox-safe tracking + StoreKit donation tips`

## Summary
- Added dual-channel architecture:
  - `Judge Chronos MAS` (sandbox-compliant, MAS-safe ingestion)
  - `Judge Chronos` (direct channel, advanced ingestion)
- Added ingestion abstraction with channel-specific providers.
- Added StoreKit 2 consumable donations (`tip.small`, `tip.medium`, `tip.large`) with no feature unlocks.
- Gated Full Disk Access UX and KnowledgeC flows out of MAS behavior.
- Added compile-time `APPSTORE` isolation to remove MAS KnowledgeC runtime path.

## What Changed
- New: `DistributionChannel` and activity capability model.
- New: `ActivityIngestionProvider` protocol and MAS foreground ingestion provider.
- New: `DonationService` for StoreKit 2 purchases and transaction observation.
- Updated: `LocalDataStore` provider injection and channel-specific defaults.
- Updated: UI messaging/settings to hide Full Disk Access prompts in MAS channel.
- Updated: project target settings for MAS sandbox entitlements and `APPSTORE` compilation condition.

## App Review Risk Hardening
- MAS target has sandbox enabled with minimal entitlements.
- MAS binary has no active KnowledgeC/Full Disk Access execution path.
- Full Disk Access onboarding and messaging are disabled in MAS channel UX.
- Donation copy explicitly states optional support and no unlock behavior.

## Validation Checklist
- [ ] `xcodebuild build -scheme 'Judge Chronos'` passes.
- [ ] `xcodebuild build -scheme 'Judge Chronos MAS'` passes.
- [ ] `xcodebuild test -scheme 'Judge Chronos'` passes.
- [ ] MAS entitlements verified with `codesign -d --entitlements :-`.
- [ ] MAS app launches and timeline auto-populates from foreground app/title/calendar.
- [ ] MAS app does not prompt for Full Disk Access.
- [ ] StoreKit tips load and purchase flow works in sandbox/TestFlight.

## Manual QA Notes
- MAS mode:
  - Uses frontmost app + window title + calendar overlays.
  - Works without manual tagging.
  - Shows privacy-safe tracking messaging.
- Direct mode:
  - Existing advanced ingestion path remains unchanged.

## App Store Connect / IAP Checklist
- [ ] Create MAS app record with MAS bundle ID.
- [ ] Create consumable IAPs:
  - `tip.small`
  - `tip.medium`
  - `tip.large`
- [ ] Add localized display names/descriptions for IAPs.
- [ ] Submit IAPs together with first app submission.

## Copy/Paste App Review Notes
`Judge Chronos MAS tracks productivity context locally on-device using frontmost app changes, optional window title (Accessibility permission), and optional meeting overlays (Calendar permission).`

`The app does not require Full Disk Access in the Mac App Store build. Donations are implemented as optional consumable tips via StoreKit 2 (tip.small, tip.medium, tip.large) and do not unlock features.`

## Rollback Plan
- If MAS-specific issue is found, ship direct channel updates independently.
- Disable donation UI via product availability while keeping core tracking intact.
