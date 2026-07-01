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

    // Свой набор символов
    @Published var customSymbols: String = "!@#$%^&*()-_=+[]{};:,.<>?" {
        didSet { UserDefaults.standard.set(customSymbols, forKey: symbolsKey) }
    }

    // Поиск по истории
    @Published var searchQuery: String = ""
    var filteredHistory: [PasswordEntry] { history.filter { $0.matches(searchQuery) } }

    // Настройки безопасности/удобства
    @Published var autoClearClipboard: Bool = true {
        didSet { UserDefaults.standard.set(autoClearClipboard, forKey: clipClearKey) }
    }
    @Published var clipboardClearSeconds: Double = 30 {
        didSet { UserDefaults.standard.set(clipboardClearSeconds, forKey: clipSecKey) }
    }
    @Published var autoLockEnabled: Bool = true {
        didSet { UserDefaults.standard.set(autoLockEnabled, forKey: autoLockKey); armAutoLock() }
    }
    @Published var autoLockMinutes: Double = 2 {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: autoLockMinKey); armAutoLock() }
    }
    @Published var launchAtLogin: Bool = false {
        didSet { if launchAtLogin != oldValue { SystemIntegration.setLaunchAtLogin(launchAtLogin) } }
    }
    @Published var menuBarOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(menuBarOnly, forKey: menuBarKey)
            SystemIntegration.setMenuBarOnly(menuBarOnly)
        }
    }

    // Профиль / PIN-код / биометрия
    @Published var isUnlocked = false { didSet { armAutoLock() } }
    // PIN хранится только как солёный SHA-256 хеш — открытый код нигде не сохраняется.
    private var pinHash: String = ""
    private var pinSalt: Data = Data()

    // Служебное
    private var clipboardChangeCount: Int = -1
    private var autoLockWork: DispatchWorkItem?

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
    private let symbolsKey = "custom_symbols"
    private let clipClearKey = "clip_autoclear"
    private let clipSecKey = "clip_seconds"
    private let autoLockKey = "autolock_enabled"
    private let autoLockMinKey = "autolock_minutes"
    private let menuBarKey = "menu_bar_only"

    static let words = ["apple","river","stone","cloud","tiger","ocean","forest","ember",
                        "comet","maple","amber","frost","lunar","quartz","raven","solar",
                        "thorn","velvet","willow","zephyr","breeze","cedar","delta","falcon",
                        "glacier","harbor","ivory","jungle","lemon","meadow","nectar","opal",
                        "pebble","ripple","summit","tundra","copper","mango","orbit","pixel"]

    init() {
        loadTheme()
        loadSettings()
        loadHistory()
        loadPIN()
        generate()
        observeAppLifecycle()
    }

    private func loadTheme() {
        if let raw = UserDefaults.standard.string(forKey: themeKey),
           let t = AppTheme(rawValue: raw) { theme = t }
        Brand.activeTheme = theme
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        if let s = d.string(forKey: symbolsKey), !s.isEmpty { customSymbols = s }
        if d.object(forKey: clipClearKey) != nil { autoClearClipboard = d.bool(forKey: clipClearKey) }
        if d.object(forKey: clipSecKey) != nil { clipboardClearSeconds = d.double(forKey: clipSecKey) }
        if d.object(forKey: autoLockKey) != nil { autoLockEnabled = d.bool(forKey: autoLockKey) }
        if d.object(forKey: autoLockMinKey) != nil { autoLockMinutes = d.double(forKey: autoLockMinKey) }
        // Автозапуск: источник истины — сама система.
        launchAtLogin = SystemIntegration.launchAtLoginEnabled
        // Режим меню-бара: восстановить и применить.
        menuBarOnly = d.bool(forKey: menuBarKey)
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
        if useSymbols {
            let symbols = customSymbols.isEmpty ? "!@#$%^&*()-_=+[]{};:,.<>?" : customSymbols
            sets.append(symbols)
        }

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

    // Копирует в буфер обмена (без авто-перегенерации — чтобы можно было сохранить
    // ровно тот пароль, что вставил на сайте). Регенерация — только по кнопке.
    func copyToClipboard() { setClipboard(password) }

    func copy(_ entry: PasswordEntry) { setClipboard(entry.password) }

    private func setClipboard(_ value: String) {
        guard !value.isEmpty else { return }
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        clipboardChangeCount = pb.changeCount
        #else
        UIPasteboard.general.string = value
        #endif
        scheduleClipboardClear(value)
    }

    // Стирает буфер спустя заданное время, но только если там всё ещё наш пароль.
    private func scheduleClipboardClear(_ value: String) {
        guard autoClearClipboard else { return }
        let delay = max(5, clipboardClearSeconds)
        #if os(macOS)
        let expectedCount = clipboardChangeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            if pb.changeCount == expectedCount, pb.string(forType: .string) == value {
                pb.clearContents()
            }
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if UIPasteboard.general.string == value { UIPasteboard.general.string = "" }
        }
        #endif
    }

    // Сохранить текущий пароль вместе с контекстом (сайт, логин/почта, заметка).
    func saveCurrent(site: String = "", login: String = "", note: String = "") {
        guard !password.isEmpty else { return }
        let entry = PasswordEntry(password: password, date: Date(),
                                  site: site.trimmingCharacters(in: .whitespacesAndNewlines),
                                  login: login.trimmingCharacters(in: .whitespacesAndNewlines),
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        history.insert(entry, at: 0)
        persistHistory()
        noteActivity()
        // Готовим новый пароль для следующей регистрации
        generate()
    }

    // Обновить метаданные существующей записи.
    func updateEntry(_ entry: PasswordEntry, site: String, login: String, note: String) {
        guard let idx = history.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = history[idx]
        updated.site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        history[idx] = updated
        persistHistory()
        noteActivity()
    }

    func deleteEntry(_ entry: PasswordEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()
    }

    func clearHistory() { history.removeAll(); persistHistory() }

    // Полная замена истории (используется при импорте бэкапа).
    func replaceHistory(_ entries: [PasswordEntry]) {
        history = entries
        persistHistory()
    }

    // Слияние истории при импорте: добавляем только отсутствующие записи.
    @discardableResult
    func mergeHistory(_ entries: [PasswordEntry]) -> Int {
        let existing = Set(history.map { $0.id })
        let newOnes = entries.filter { !existing.contains($0.id) }
        history.insert(contentsOf: newOnes, at: 0)
        history.sort { $0.date > $1.date }
        persistHistory()
        return newOnes.count
    }

    // MARK: - Авто-блокировка

    func noteActivity() { armAutoLock() }

    private func armAutoLock() {
        autoLockWork?.cancel()
        guard isUnlocked, autoLockEnabled else { return }
        let minutes = max(0.5, autoLockMinutes)
        let work = DispatchWorkItem { [weak self] in self?.lock() }
        autoLockWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + minutes * 60, execute: work)
    }

    private func observeAppLifecycle() {
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.autoLockEnabled { self.lock() }
        }
        #endif
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) { Keychain.save(data, for: historyKey) }
    }

    private func loadHistory() {
        if let data = Keychain.read(historyKey),
           let decoded = try? JSONDecoder().decode([PasswordEntry].self, from: data) { history = decoded }
    }
}
