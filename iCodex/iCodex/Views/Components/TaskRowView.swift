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
        HStack(spacing: 12) {
            // Status indicator column
            ZStack {
                if thread.isRunning {
                    PulsingDot()
                } else {
                    Image(systemName: thread.sourceIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(themeManager.current.textSecondary)
                }
            }
            .frame(width: 20)

            // Main content
            VStack(alignment: .leading, spacing: 5) {
                Text(thread.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(themeManager.current.textPrimary)

                HStack(spacing: 6) {
                    if let branch = thread.gitBranch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text(branch)
                        }
                        .lineLimit(1)
                    }
                    Text("·")
                        .foregroundStyle(themeManager.current.textSecondary.opacity(0.4))
                    Text(thread.formattedDate)
                }
                .font(.caption2)
                .foregroundStyle(themeManager.current.textSecondary)

                // Git diff stats for completed threads
                if let stats = thread.gitStats, (stats.insertions > 0 || stats.deletions > 0) {
                    HStack(spacing: 6) {
                        if stats.insertions > 0 {
                            Text("+\(stats.insertions)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if stats.deletions > 0 {
                            Text("-\(stats.deletions)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                        if stats.filesChanged > 0 {
                            Text("\(stats.filesChanged) files")
                                .font(.system(size: 10))
                                .foregroundStyle(themeManager.current.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            // Right column
            VStack(alignment: .trailing, spacing: 5) {
                if thread.isRunning {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                }
                Text(thread.formattedTokens)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(themeManager.current.textSecondary.opacity(0.6))
            }
        }
        .padding(.vertical, 6)
    }
}
