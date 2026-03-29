import SwiftUI

struct PulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(isAnimating ? 1.6 : 1.0)
                .opacity(isAnimating ? 0 : 0.6)
                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
        }
        .onAppear { isAnimating = true }
    }
}

struct ThreadRowView: View {
    let thread: CodexThread
    var themeManager = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(thread.isRunning ? Color.green.opacity(0.12) : themeManager.current.inputBackground)
                    .frame(width: 42, height: 42)

                if thread.isRunning {
                    PulsingDot()
                } else {
                    Image(systemName: thread.sourceIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeManager.current.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(thread.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(themeManager.current.textPrimary)

                HStack(spacing: 6) {
                    if let branch = thread.gitBranch {
                        threadPill(icon: "arrow.triangle.branch", text: branch)
                    }

                    threadPill(icon: "clock", text: thread.formattedDate)
                }

                if let stats = thread.gitStats, (stats.insertions > 0 || stats.deletions > 0 || stats.filesChanged > 0) {
                    HStack(spacing: 6) {
                        if stats.insertions > 0 {
                            statPill(text: "+\(stats.insertions)", color: .green)
                        }
                        if stats.deletions > 0 {
                            statPill(text: "-\(stats.deletions)", color: .red)
                        }
                        if stats.filesChanged > 0 {
                            statPill(text: "\(stats.filesChanged) files", color: themeManager.current.textSecondary)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                if thread.isRunning {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                }

                Text(thread.formattedTokens)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.current.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(themeManager.current.inputBackground)
                    )
            }
        }
        .padding(.vertical, 8)
    }

    private func threadPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(themeManager.current.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(themeManager.current.inputBackground)
        )
    }

    private func statPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(themeManager.current.inputBackground)
            )
    }
}
