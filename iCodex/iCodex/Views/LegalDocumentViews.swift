import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            PolicySection(
                title: "Summary",
                content: "iCodex is a companion app for software running on your own Mac. It connects over your local network so you can view threads, send replies, and manage Codex remotely from your iPhone or iPad."
            )

            PolicySection(
                title: "Information Stored On Your Device",
                content: "The app stores your selected server host, port, and pairing token locally on your device so it can reconnect to your Mac. This information is not uploaded to the developer by the app."
            )

            PolicySection(
                title: "Local Network Access",
                content: "iCodex requests Local Network access to discover your Mac and connect directly to the iCodex-Connect companion app running on your own machine."
            )

            PolicySection(
                title: "What We Do Not Collect",
                content: "The current iOS app does not include advertising SDKs, analytics SDKs, or third-party tracking. It does not create a developer-hosted user account and does not upload your Codex messages to a developer-operated cloud service."
            )

            PolicySection(
                title: "Your Data Flow",
                content: "Conversation data shown in the app comes from the Codex environment on your Mac. Requests from the iOS app are sent to your Mac companion over your network and are used only to deliver the features you invoke."
            )
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportGuideView: View {
    var body: some View {
        List {
            PolicySection(
                title: "Setup",
                content: "1. Install iCodex-Connect on your Mac.\n2. Move it to Applications and open it from there.\n3. Grant Accessibility permission when prompted.\n4. Make sure your iPhone or iPad and Mac are on the same Wi-Fi network.\n5. Pair with the 6-digit passcode shown in the Mac menu bar app."
            )

            PolicySection(
                title: "If Your Mac Is Not Found",
                content: "Confirm that iCodex-Connect is running on your Mac, both devices are on the same Wi-Fi network, and Local Network permission is enabled for iCodex in iOS Settings."
            )

            PolicySection(
                title: "If Pairing Fails",
                content: "Open the Mac menu bar app again and make sure you entered the current 6-digit passcode. If needed, disconnect in Settings and pair again."
            )

            PolicySection(
                title: "If Remote Control Actions Fail",
                content: "Check that iCodex-Connect still has Accessibility permission on the Mac and that the Codex desktop app is open."
            )
        }
        .navigationTitle("Support Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PolicySection: View {
    let title: String
    let content: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        bodyView
    }
}
