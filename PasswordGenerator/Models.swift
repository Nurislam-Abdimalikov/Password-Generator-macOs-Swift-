import SwiftUI

// MARK: - Модель записи истории
struct PasswordEntry: Identifiable, Codable {
    var id = UUID()
    let password: String
    let date: Date
}

// MARK: - Уровни надёжности
enum PasswordStrength: Int {
    case weak, medium, strong, veryStrong

    var label: String {
        switch self {
        case .weak: return "Слабый"
        case .medium: return "Средний"
        case .strong: return "Надёжный"
        case .veryStrong: return "Очень надёжный"
        }
    }

    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .yellow
        case .veryStrong: return .green
        }
    }

    var fillRatio: Double {
        switch self {
        case .weak: return 0.25
        case .medium: return 0.5
        case .strong: return 0.75
        case .veryStrong: return 1.0
        }
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .weak }
        var score = 0
        let length = password.count
        if length >= 8 { score += 1 }
        if length >= 12 { score += 1 }
        if length >= 16 { score += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil { score += 1 }

        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        case 5...6: return .strong
        default: return .veryStrong
        }
    }
}

// MARK: - Режим генерации
enum GenerationMode: String, CaseIterable, Identifiable {
    case password = "Пароль"
    case passphrase = "Фраза"
    var id: String { rawValue }
}
