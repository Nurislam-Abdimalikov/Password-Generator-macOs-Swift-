import SwiftUI
import Combine
import LocalAuthentication
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class PasswordViewModel: ObservableObject {
    @Published var password: String = ""
    @Published var length: Double = 16
    @Published var useUppercase = true
    @Published var useLowercase = true
    @Published var useNumbers = true
    @Published var useSymbols = true
    @Published var history: [PasswordEntry] = []

    // Режим и опции генерации
    @Published var mode: GenerationMode = .password
    @Published var excludeSimilar = false
    @Published var wordCount: Double = 4

    // Профиль / PIN-код / биометрия
    @Published var isUnlocked = false
    // PIN хранится только как солёный SHA-256 хеш — открытый код нигде не сохраняется.
    private var pinHash: String = ""
    private var pinSalt: Data = Data()

    // Тема оформления
    @Published var theme: AppTheme = .neon {
        didSet {
            Brand.activeTheme = theme
            UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        }
    }

    private let historyKey = "password_history"
    private let pinKey = "user_pin"          // legacy: открытый PIN (для миграции старых версий)
    private let pinHashKey = "user_pin_hash"
    private let pinSaltKey = "user_pin_salt"
    private let themeKey = "app_theme"

    static let words = ["apple","river","stone","cloud","tiger","ocean","forest","ember",
                        "comet","maple","amber","frost","lunar","quartz","raven","solar",
                        "thorn","velvet","willow","zephyr","breeze","cedar","delta","falcon",
                        "glacier","harbor","ivory","jungle","lemon","meadow","nectar","opal",
                        "pebble","ripple","summit","tundra","copper","mango","orbit","pixel"]

    init() {
        loadTheme()
        loadHistory()
        loadPIN()
        generate()
    }

    private func loadTheme() {
        if let raw = UserDefaults.standard.string(forKey: themeKey),
           let t = AppTheme(rawValue: raw) { theme = t }
        Brand.activeTheme = theme
    }

    var strength: PasswordStrength { PasswordStrength.evaluate(password) }

    var hasPIN: Bool { !pinHash.isEmpty }

    func setPIN(_ pin: String) {
        let salt = PINHasher.newSalt()
        pinSalt = salt
        pinHash = PINHasher.hash(pin, salt: salt)
        Keychain.save(salt, for: pinSaltKey)
        Keychain.saveString(pinHash, for: pinHashKey)
        isUnlocked = true
    }

    func unlock(with pin: String) -> Bool {
        guard hasPIN else { return false }
        let candidate = PINHasher.hash(pin, salt: pinSalt)
        // Сравнение без утечки времени по длине совпадения.
        guard candidate.count == pinHash.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate.utf8, pinHash.utf8) { diff |= a ^ b }
        if diff == 0 { isUnlocked = true; return true }
        return false
    }

    func lock() { isUnlocked = false }

    func resetPIN() {
        pinHash = ""
        pinSalt = Data()
        Keychain.delete(pinHashKey)
        Keychain.delete(pinSaltKey)
        Keychain.delete(pinKey)
        isUnlocked = false
    }

    private func loadPIN() {
        if let hash = Keychain.readString(pinHashKey), let salt = Keychain.read(pinSaltKey), !hash.isEmpty {
            pinHash = hash
            pinSalt = salt
            return
        }
        // Миграция: если остался открытый PIN от старой версии — пересолить и захешировать.
        if let legacy = Keychain.readString(pinKey), !legacy.isEmpty {
            setPIN(legacy)
            isUnlocked = false
            Keychain.delete(pinKey)
        }
    }

    // Биометрия
    var canUseBiometrics: Bool {
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometricName: String {
        let ctx = LAContext(); _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType { case .touchID: return "Touch ID"; case .faceID: return "Face ID"; default: return "биометрию" }
    }

    var biometricIcon: String {
        let ctx = LAContext(); _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType { case .touchID: return "touchid"; case .faceID: return "faceid"; default: return "lock.shield" }
    }

    func authenticateWithBiometrics(completion: @escaping (Bool, String?) -> Void) {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Ввести PIN-код"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, "Биометрия недоступна на этом Mac"); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Разблокируйте доступ к сохранённым паролям") { success, evalError in
            DispatchQueue.main.async {
                if success { self.isUnlocked = true; completion(true, nil) }
                else { completion(false, evalError?.localizedDescription) }
            }
        }
    }

    // Генерация
    func generate() {
        switch mode { case .password: generatePassword(); case .passphrase: generatePassphrase() }
    }

    private func generatePassword() {
        var sets: [String] = []
        if useLowercase { sets.append("abcdefghijklmnopqrstuvwxyz") }
        if useUppercase { sets.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
        if useNumbers  { sets.append("0123456789") }
        if useSymbols  { sets.append("!@#$%^&*()-_=+[]{};:,.<>?") }

        if excludeSimilar {
            let banned = Set("O0o1lI")
            sets = sets.map { String($0.filter { !banned.contains($0) }) }.filter { !$0.isEmpty }
        }

        guard !sets.isEmpty else { password = ""; return }

        let total = max(Int(length), sets.count)
        let all = Array(sets.joined())
        func makePassword() -> String {
            var chars: [Character] = []
            for set in sets { if let c = SecureRandom.element(Array(set)) { chars.append(c) } }
            while chars.count < total { if let c = SecureRandom.element(all) { chars.append(c) } }
            return String(SecureRandom.shuffled(chars))
        }
        var newPassword = makePassword(); var attempts = 0
        while newPassword == password && attempts < 5 { newPassword = makePassword(); attempts += 1 }
        password = newPassword
    }

    private func generatePassphrase() {
        let count = max(3, Int(wordCount))
        func makePhrase() -> String {
            var parts: [String] = []
            for _ in 0..<count { parts.append((SecureRandom.element(Self.words) ?? "secure").capitalized) }
            return parts.joined(separator: "-") + "-\(SecureRandom.int(in: 10...99))"
        }
        var phrase = makePhrase(); var attempts = 0
        while phrase == password && attempts < 5 { phrase = makePhrase(); attempts += 1 }
        password = phrase
    }

    func copyToClipboard() {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(password, forType: .string)
        #else
        UIPasteboard.general.string = password
        #endif
        // После копирования генерируем новый пароль
        generate()
    }

    func saveCurrent() {
        guard !password.isEmpty else { return }
        history.insert(PasswordEntry(password: password, date: Date()), at: 0)
        persistHistory()
        // После сохранения сразу сгенерировать новый пароль
        generate()
    }

    func copy(_ entry: PasswordEntry) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.password, forType: .string)
        #else
        UIPasteboard.general.string = entry.password
        #endif
    }

    func deleteEntry(_ entry: PasswordEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()
    }

    func clearHistory() { history.removeAll(); persistHistory() }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) { Keychain.save(data, for: historyKey) }
    }

    private func loadHistory() {
        if let data = Keychain.read(historyKey),
           let decoded = try? JSONDecoder().decode([PasswordEntry].self, from: data) { history = decoded }
    }
}
