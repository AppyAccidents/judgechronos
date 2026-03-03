# Mac App Store + Donations Checklist

## App Record
- Create app in App Store Connect with bundle ID: `berkerceylan.Judge-Chronos-MAS`
- Price: Free
- Category: Productivity

## In-App Purchases (Consumable Tips)
- `tip.small`
- `tip.medium`
- `tip.large`

Each product should include:
- Display name
- Description (optional donation, no feature unlock)
- Price tier
- Review screenshot

## Metadata
- App description should state:
  - tracking uses frontmost app/window title and optional calendar context
  - donations are optional and do not unlock features
- Privacy details for Calendar and Accessibility permissions

## Submission Notes (Suggested)
- This is a free productivity app.
- In-App Purchases are optional consumable tips to support development.
- No content/features are locked behind purchases.
- macOS App Store build is sandboxed and does not read protected system databases.
- Calendar and Accessibility are used only for activity context.

## Pre-Submission Validation
- Archive `Judge Chronos MAS` target in Release.
- Confirm sandbox entitlement:
  - `codesign -d --entitlements :- <Judge Chronos MAS.app>`
- Confirm donation products load in StoreKit sandbox.
- Submit app + all three IAPs in the same review cycle.
