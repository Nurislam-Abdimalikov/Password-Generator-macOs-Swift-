import SwiftUI

// MARK: - Палитра темы
struct ThemePalette {
    let accent: Color
    let gradient: [Color]
    var accentGradient: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Темы оформления (несколько на выбор)
enum AppTheme: String, CaseIterable, Identifiable {
    case neon = "Неон"
    case ocean = "Океан"
    case sunset = "Закат"
    case matrix = "Матрица"
    case mono = "Моно"
    var id: String { rawValue }

    var palette: ThemePalette {
        switch self {
        case .neon:
            return ThemePalette(accent: Color(red: 0.74, green: 0.42, blue: 0.99),
                                gradient: [Color(red: 0.62, green: 0.31, blue: 0.98),
                                           Color(red: 0.95, green: 0.36, blue: 0.74)])
        case .ocean:
            return ThemePalette(accent: Color(red: 0.32, green: 0.72, blue: 0.96),
                                gradient: [Color(red: 0.20, green: 0.55, blue: 0.95),
                                           Color(red: 0.25, green: 0.85, blue: 0.80)])
        case .sunset:
            return ThemePalette(accent: Color(red: 0.98, green: 0.56, blue: 0.35),
                                gradient: [Color(red: 0.98, green: 0.42, blue: 0.30),
                                           Color(red: 0.98, green: 0.76, blue: 0.32)])
        case .matrix:
            return ThemePalette(accent: Color(red: 0.32, green: 0.90, blue: 0.52),
                                gradient: [Color(red: 0.18, green: 0.82, blue: 0.45),
                                           Color(red: 0.45, green: 0.95, blue: 0.65)])
        case .mono:
            return ThemePalette(accent: Color(white: 0.85),
                                gradient: [Color(white: 0.70), Color(white: 0.95)])
        }
    }
}

// MARK: - Тема оформления (активная тема + общие константы)
enum Brand {
    static var activeTheme: AppTheme = .neon

    static let background = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.06, blue: 0.20),
            Color(red: 0.17, green: 0.09, blue: 0.33),
            Color(red: 0.06, green: 0.11, blue: 0.27)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static var accent: Color { activeTheme.palette.accent }
    static var accentGradient: LinearGradient { activeTheme.palette.accentGradient }
    static var gradientColors: [Color] { activeTheme.palette.gradient }
    static let stroke = Color.white.opacity(0.10)
}
