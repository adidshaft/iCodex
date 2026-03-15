import SwiftUI

struct PulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

struct ThreadRowView: View {
    let thread: CodexThread

    var body: some View {
        HStack(spacing: 12) {
            // Activity indicator
            VStack {
                if thread.isRunning {
                    PulsingDot()
                } else {
                    Image(systemName: thread.sourceIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let branch = thread.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                    }
                    Text(thread.formattedDate)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                // Git stats for completed threads
                if let stats = thread.gitStats {
                    HStack(spacing: 8) {
                        if stats.insertions > 0 {
                            Text("+\(stats.insertions)")
                                .foregroundStyle(.green)
                        }
                        if stats.deletions > 0 {
                            Text("-\(stats.deletions)")
                                .foregroundStyle(.red)
                        }
                        if stats.filesChanged > 0 {
                            Text("\(stats.filesChanged) files")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if thread.isRunning {
                    Text("RUNNING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green))
                }
                Text(thread.formattedTokens)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
