import SwiftUI

struct MarkdownText: View {
    let text: String
    let theme: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let lang, let code):
                    CodeBlockView(language: lang, code: code, theme: theme)
                case .text(let markdown):
                    Text(renderInline(markdown))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private enum Block {
        case text(String)
        case code(language: String, code: String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var textBuffer: [String] = []

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                // Flush text buffer
                if !textBuffer.isEmpty {
                    let joined = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty { blocks.append(.text(joined)) }
                    textBuffer = []
                }

                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: lang, code: codeLines.joined(separator: "\n")))
                i += 1 // skip closing ```
            } else {
                textBuffer.append(line)
                i += 1
            }
        }

        // Flush remaining text
        if !textBuffer.isEmpty {
            let joined = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.text(joined)) }
        }

        return blocks
    }

    private func renderInline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    let theme: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.codeText)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.codeBorder, lineWidth: 0.5)
        )
    }
}
