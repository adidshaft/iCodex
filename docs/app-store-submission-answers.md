# App Store Submission Answers

Updated: 2026-03-16

These answers are tailored to the current iOS app in this repo.

## Recommended listing metadata

- App Name: `iCodex`
- Subtitle: `Remote Codex companion`
- Primary Category: `Productivity`
- Secondary Category: `Utilities`

Suggested keywords:
- `codex,developer,remote,mac,assistant,threads,ai,workflow`

Suggested short description:

`iCodex lets you monitor and control Codex running on your own Mac. Pair your iPhone or iPad with the iCodex-Connect companion app on your Mac, then view threads, send replies, and manage work from anywhere on your local network.`

## App Review notes

Paste this into the App Review notes field:

`iCodex is a companion app for software running on the user’s own Mac. To use the app, the reviewer should install and open the iCodex-Connect macOS companion on a Mac, keep the Mac and iOS device on the same local network, and pair using the one-time 6-digit passcode shown by the Mac menu bar app. The iOS app uses Local Network access only to discover and communicate directly with the reviewer’s own Mac. No public user account is required. The Mac companion requests Accessibility permission because it controls the locally installed Codex desktop app on the reviewer’s Mac. A short demo video showing setup, pairing, and normal use should be attached to the review submission.`

Recommended attachments for review:
- a 1-2 minute demo video
- a short PDF or note with the exact Mac install steps
- if needed, a temporary test Mac and local-network instructions

## App Privacy answers

Recommended App Privacy position:
- Data Used to Track You: `No`
- Data Linked to the User: `No`
- Data Not Linked to the User: `No`
- Resulting label: `No Data Collected`

Why this is the right answer for the current app:
- The iOS app connects directly to the user’s own Mac companion over the local network.
- The repo contains no analytics SDKs, ad SDKs, attribution SDKs, or third-party tracking SDKs.
- The app stores host, port, and pairing token locally on device, but does not send that information to a developer-operated backend.

## Tracking answers

- Does this app track users across apps or websites? `No`
- Does this app share data with data brokers, ad networks, or third-party advertising partners? `No`
- Does this app use IDFA? `No`

## Export compliance answers

The project now sets:
- `ITSAppUsesNonExemptEncryption = NO`

Recommended position:
- The app does not implement proprietary or non-standard cryptography.
- The app does not require export documentation for custom encryption.

If App Store Connect still shows follow-up export questions, answer consistently with:
- No proprietary encryption
- No custom non-standard cryptography
- No separate export compliance documentation required for this build

If the transport architecture changes later to add custom cryptography, revisit this section.

## Age rating answers

Recommended age rating target:
- `4+`

Recommended answers:
- Gambling: `None`
- Contests: `None`
- Medical/Treatment information: `None`
- Alcohol, tobacco, or drug references: `None`
- Sexual content or nudity: `None`
- Horror/Fear themes: `None`
- Violence: `None`
- User-generated content shared publicly in-app: `No`
- Unrestricted web access: `No`

## Sign-in and account answers

- Is account creation required? `No`
- Is sign-in required to access core functionality? `No`
- Are there paid features or subscriptions? `No` for the current repo state

## Content rights answers

Recommended answer:
- `Yes, I have all necessary rights for the app’s content, screenshots, metadata, and branding.`

## Privacy policy and support URLs

You still need public website URLs in App Store Connect.

Recommended pages to publish:
- `https://your-domain.com/privacy`
- `https://your-domain.com/support`
- `https://your-domain.com/download-mac`

You can use the repo drafts in:
- `CodexManagerSystem/docs/privacy-policy.md`
- `CodexManagerSystem/docs/support.md`

## App Review guideline framing

This app best fits Apple’s guidance for remote desktop or host-client software on a user-owned host over a local network.

Relevant Apple references:
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Review information: https://developer.apple.com/help/app-store-connect/reference/app-review-information
- App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Export compliance overview: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
