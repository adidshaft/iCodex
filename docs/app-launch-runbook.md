# iCodex Launch Runbook

Updated: 2026-03-16

Goal:
- Ship the iOS app on the App Store.
- Keep the macOS companion app as a direct website download, not a Mac App Store app.

## Current repo state

What the codebase currently does:
- The iOS app is a SwiftUI client in `iCodex`.
- The iOS app discovers a Mac on the same Wi-Fi by scanning local subnets and then talks to the Mac backend over `http://<ip>:8642`.
- Pairing is done with a 6-digit setup passcode shown by the Mac app.
- The Mac companion is packaged by `MacBackend/build_dmg.sh`.
- The Mac companion controls the Codex desktop app and requests Accessibility permission through the native helper in `MacBackend/icodex_keystroke.swift`.

Release-relevant settings already present:
- iOS bundle ID: `adidshaft.iCodex`
- iOS marketing version: `1.0`
- iOS build number: `1`
- iOS device family: iPhone + iPad
- iOS deployment target: `26.2`
- macOS DMG version in the build script: `2.2.0`

## Launch blockers to clear first

- [ ] Add iOS local-network privacy messaging.
  The project currently does not define `NSLocalNetworkUsageDescription` in the generated Info.plist settings. The app scans the LAN and connects directly to a Mac on the local network, so this needs to be present before App Store submission.

- [ ] Validate the iOS networking policy in a Release/TestFlight build.
  The app currently uses `URLSession` with plain HTTP to numeric local IPs. Apple requires ATS-compliant networking by default and only allows narrow exceptions when needed. If TestFlight or App Review builds block `http://192.168.x.x`, decide between:
  - moving the Mac backend to HTTPS on the LAN, or
  - adding the narrowest ATS exception that actually works for this app.

  Note:
  This is the one area where repo behavior and Apple’s docs need a real device check before submission. The code is using raw IP addresses rather than Bonjour or `.local` hostnames.

- [ ] Choose the real minimum supported iOS/iPadOS version.
  `IPHONEOS_DEPLOYMENT_TARGET` is currently `26.2`. If that is intentional, keep it. If not, lower it before launch because it directly limits who can download the app.

- [ ] Prepare App Store metadata that is not in the repo.
  You will need:
  - app name, subtitle, description, keywords
  - privacy policy URL
  - support URL
  - category
  - age rating answers
  - screenshots for iPhone and iPad
  - review notes explaining the Mac companion dependency

- [ ] Decide how App Review will verify the product.
  This app depends on a user-owned Mac companion and a local-network setup. Apple explicitly asks for demo accounts, hardware, or a demo video when review requires a special environment or hardware. Plan this before the first submission.

- [ ] Sign and notarize the Mac companion for website download.
  The GitHub release workflow should fail closed unless Developer ID signing and notarization credentials are configured. Keep that path healthy and verify the published DMG remains stapled and Gatekeeper-clean.

- [ ] Reduce friction in the Mac installer.
  The current Mac app expects a system Python install and then creates a venv and installs Python packages on first launch. That is risky for a public download. Prefer bundling the runtime and dependencies into the app before launch.

## iOS App Store plan

### 1. Finalize product identity

- [ ] Confirm the shipping app name shown on the App Store.
- [ ] Confirm the final bundle ID and whether `adidshaft.iCodex` is the one you want to keep.
- [ ] Decide whether the App Store listing is iPhone-only or iPhone + iPad.
- [ ] Confirm the support email, website, privacy policy page, and support page.

### 2. Finish the iOS build configuration

- [ ] Add `NSLocalNetworkUsageDescription` with a clear user-facing reason string.
  Suggested direction:
  `"iCodex uses your local network to find and connect to your Mac so you can manage Codex remotely from your iPhone or iPad."`

- [ ] Test a Release build on physical devices from TestFlight, not just Debug.
- [ ] Verify that the onboarding flow, passcode pairing, thread loading, message sending, stop/interrupt actions, and settings work end-to-end on a clean install.
- [ ] Test the denied-permission path for Local Network access and make sure the app explains how to recover.
- [ ] Test the denied-permission path when the Mac companion is missing or not running.
- [ ] Decide whether to keep only manual IP entry, or keep subnet scanning for launch.
  Inference:
  Manual IP entry is easier to explain to App Review and usually creates fewer privacy questions than aggressive subnet scanning.

### 3. Prepare App Store Connect

- [ ] Create the iOS app record in App Store Connect.
- [ ] Fill in App Information, Pricing and Availability, and App Privacy.
- [ ] Opt the iOS app out of Mac App Store availability under:
  `Pricing and Availability` -> `iPhone and iPad Apps on Apple Silicon Mac`
  because you want the Mac experience distributed directly from your website.
- [ ] Upload localized screenshots for each supported device size you plan to support.
- [ ] Add at least one support contact path that is live before review.
- [ ] Add a privacy policy URL that is live before review.

### 4. Prepare App Review notes

Add a review note that explains:
- The iOS app is a companion for software running on the user’s own Mac.
- The app only works after the user installs `iCodex-Connect` on their Mac and both devices are on the same local network.
- Pairing happens with a one-time 6-digit passcode generated on the Mac.
- The app accesses the local network only to discover and communicate with the user’s Mac.
- No public account signup is required.

Also attach:
- a short demo video showing Mac install, Accessibility permission, iPhone pairing, and normal usage
- any temporary review instructions needed to reach a working state

### 5. TestFlight rollout

- [ ] Upload a signed archive from Xcode.
- [ ] Run internal TestFlight first.
- [ ] Then run a small external TestFlight with people who are not on your development machines.
- [ ] Collect feedback on:
  - local-network permission prompts
  - pairing failures
  - confusing onboarding steps
  - behavior when the Mac app is not installed
  - behavior when the Mac app lacks Accessibility permission

### 6. Submit and release

- [ ] Submit the first production build only after metadata, privacy answers, screenshots, and review notes are complete.
- [ ] Choose either manual release or automatic release after approval.
  Recommendation:
  Use manual release for v1 so you can align the website, support docs, and announcement.

## macOS direct-download plan

### 1. Decide the shipping packaging model

Recommended:
- Bundle the Python runtime and Python dependencies into the app.
- Avoid first-launch `pip install`.
- Keep the DMG as the distribution container.

Why this matters:
- fewer support tickets
- better first-launch reliability
- cleaner notarization story
- less chance of Gatekeeper or endpoint security tools flagging the install flow

### 2. Sign the Mac app for outside-the-store distribution

- [ ] Enroll in the Apple Developer Program if not already complete.
- [ ] Create or confirm a `Developer ID Application` certificate.
- [ ] Sign the full `.app` bundle and all nested executables/helpers with hardened runtime enabled.
- [ ] Make sure the shipped app, helper binary, and any bundled runtimes all remain validly signed after packaging.

### 3. Notarize and staple

- [ ] Submit the final DMG or ZIP with `notarytool`.
- [ ] Wait for `Accepted`.
- [ ] Staple the notarization ticket to the app and/or DMG.
- [ ] Re-download the stapled artifact on a clean Mac and verify it launches without security warnings beyond the expected Accessibility permission flow.

### 4. Website release assets

- [ ] Create a simple download page with:
  - what the Mac app does
  - minimum macOS version
  - install steps
  - Accessibility permission steps
  - troubleshooting for Local Network and Accessibility
  - privacy policy
  - support contact

- [ ] Publish a checksum and version number for each release.
- [ ] Keep release notes for support and rollback clarity.

### 5. Mac launch QA

- [ ] Fresh install on a clean Mac user account.
- [ ] Launch from `/Applications`, not from the mounted DMG.
- [ ] Verify first-run permission flow.
- [ ] Verify Codex control, pairing, thread sync, stop/interrupt, and reconnect behavior.
- [ ] Verify behavior after app update.

## Launch-day checklist

- [ ] App Store build approved.
- [ ] iOS app manually released.
- [ ] Website download page live.
- [ ] Signed and notarized Mac DMG live.
- [ ] Support email monitored.
- [ ] Privacy policy and help pages live.
- [ ] One short setup video published.
- [ ] Crash/bug triage plan ready for first 72 hours.

## Suggested order of work

1. Fix iOS privacy/networking submission blockers.
2. Run TestFlight on real devices.
3. Finish App Store Connect metadata and review notes.
4. Package, sign, notarize, and staple the Mac DMG.
5. Publish the support/privacy/download pages.
6. Submit iOS to App Review.
7. Release iOS only after the Mac website download is already live.

## Official Apple references

- App Review page:
  https://developer.apple.com/app-store/review/
- App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
- App Review information in App Store Connect:
  https://developer.apple.com/help/app-store-connect/reference/app-review-information
- App preview specs:
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- Manage iPhone/iPad app availability on Apple silicon Macs:
  https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon
- App availability:
  https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store
- Local network privacy:
  https://developer.apple.com/videos/play/wwdc2020/10110/
- Network updates:
  https://developer.apple.com/documentation/updates/network
- ATS overview:
  https://developer.apple.com/documentation/security/preventing-insecure-network-connections
- Developer ID and Gatekeeper:
  https://developer.apple.com/developer-id/
- Notarization workflow:
  https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
