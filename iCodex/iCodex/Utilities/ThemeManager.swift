import SwiftUI

// MARK: - Theme Colors

struct ThemeColors: Sendable {
    let background: Color
    let surface: Color
    let bubbleUser: Color
    let bubbleAssistant: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let codeBackground: Color
    let codeText: Color
    let codeBorder: Color
    let headerBackground: Color
    let inputBackground: Color
    let divider: Color
}

// MARK: - App Themes

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case standard
    case midnight
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .midnight: return "Midnight"
        case .terminal: return "Terminal"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Clean adaptive light & dark"
        case .midnight: return "Deep navy with cyan accents"
        case .terminal: return "Hacker green-on-black"
        }
    }

    var colors: ThemeColors {
        switch self {
        case .standard: return Self.standardColors
        case .midnight: return Self.midnightColors
        case .terminal: return Self.terminalColors
        }
    }

    // MARK: - Default Theme

    private static let standardColors = ThemeColors(
        background: Color(.systemBackground),
        surface: Color(.secondarySystemBackground),
        bubbleUser: Color(red: 0.22, green: 0.47, blue: 0.96).opacity(0.14),
        bubbleAssistant: Color(.tertiarySystemBackground),
        textPrimary: Color(.label),
        textSecondary: Color(.secondaryLabel),
        accent: Color(red: 0.22, green: 0.47, blue: 0.96),
        codeBackground: Color(.systemGray6),
        codeText: Color(.label),
        codeBorder: Color(.systemGray4),
        headerBackground: Color(.secondarySystemBackground),
        inputBackground: Color(.tertiarySystemBackground),
        divider: Color(.separator)
    )

    // MARK: - Midnight Theme

    private static let midnightColors = ThemeColors(
        background: Color(red: 0.06, green: 0.07, blue: 0.13),
        surface: Color(red: 0.09, green: 0.10, blue: 0.18),
        bubbleUser: Color(red: 0.14, green: 0.30, blue: 0.58).opacity(0.55),
        bubbleAssistant: Color(red: 0.10, green: 0.12, blue: 0.22),
        textPrimary: Color(red: 0.88, green: 0.90, blue: 0.96),
        textSecondary: Color(red: 0.52, green: 0.56, blue: 0.68),
        accent: Color(red: 0.30, green: 0.78, blue: 0.94),
        codeBackground: Color(red: 0.07, green: 0.08, blue: 0.16),
        codeText: Color(red: 0.72, green: 0.82, blue: 0.96),
        codeBorder: Color(red: 0.16, green: 0.20, blue: 0.32),
        headerBackground: Color(red: 0.08, green: 0.09, blue: 0.16),
        inputBackground: Color(red: 0.10, green: 0.12, blue: 0.20),
        divider: Color(red: 0.16, green: 0.18, blue: 0.28)
    )

    // MARK: - Terminal Theme

    private static let terminalColors = ThemeColors(
        background: Color(red: 0.04, green: 0.04, blue: 0.04),
        surface: Color(red: 0.08, green: 0.09, blue: 0.07),
        bubbleUser: Color(red: 0.10, green: 0.22, blue: 0.10).opacity(0.6),
        bubbleAssistant: Color(red: 0.07, green: 0.09, blue: 0.07),
        textPrimary: Color(red: 0.20, green: 0.86, blue: 0.32),
        textSecondary: Color(red: 0.16, green: 0.54, blue: 0.24),
        accent: Color(red: 0.20, green: 0.86, blue: 0.32),
        codeBackground: Color(red: 0.02, green: 0.02, blue: 0.02),
        codeText: Color(red: 0.30, green: 0.92, blue: 0.42),
        codeBorder: Color(red: 0.14, green: 0.30, blue: 0.16),
        headerBackground: Color(red: 0.06, green: 0.07, blue: 0.05),
        inputBackground: Color(red: 0.08, green: 0.10, blue: 0.08),
        divider: Color(red: 0.12, green: 0.22, blue: 0.12)
    )
}

// MARK: - Theme Manager

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "app_theme")
        }
    }

    var current: ThemeColors {
        selectedTheme.colors
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "app_theme") ?? "standard"
        self.selectedTheme = AppTheme(rawValue: stored) ?? .standard
    }
}
