import Foundation
import CryptoKit
import CommonCrypto
#if os(macOS)
import AppKit
#endif

// MARK: - Зашифрованный бэкап истории паролей
//
// Формат файла (.kfbackup) — JSON:
//   { "version": 1, "salt": <base64>, "data": <base64(nonce+ciphertext+tag)> }
// Ключ выводится из парольной фразы через PBKDF2-HMAC-SHA256 (200k итераций),
// шифрование — AES-256-GCM (аутентифицированное). Без правильной фразы данные не расшифровать.

enum BackupError: LocalizedError {
    case wrongPassword
    case corrupted
    case empty

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "Неверная парольная фраза или файл повреждён."
        case .corrupted: return "Файл бэкапа повреждён или имеет неверный формат."
        case .empty: return "Нечего экспортировать — история пуста."
        }
    }
}

enum BackupManager {
    private struct Payload: Codable {
        let version: Int
        let salt: String
        let data: String
    }

    // Вывод 256-битного ключа из фразы (PBKDF2-HMAC-SHA256).
    private static func deriveKey(passphrase: String, salt: Data, rounds: UInt32 = 200_000) -> SymmetricKey {
        let passData = Data(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        _ = derived.withUnsafeMutableBytes { derivedPtr in
            passData.withUnsafeBytes { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: CChar.self).baseAddress, passData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress, 32
                    )
                }
            }
        }
        return SymmetricKey(data: Data(derived))
    }

    static func encrypt(_ entries: [PasswordEntry], passphrase: String) throws -> Data {
        guard !entries.isEmpty else { throw BackupError.empty }
        let salt = PINHasher.newSalt()
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let plaintext = try JSONEncoder().encode(entries)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.corrupted }
        let payload = Payload(version: 1,
                              salt: salt.base64EncodedString(),
                              data: combined.base64EncodedString())
        return try JSONEncoder().encode(payload)
    }

    static func decrypt(_ fileData: Data, passphrase: String) throws -> [PasswordEntry] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: fileData),
              let salt = Data(base64Encoded: payload.salt),
              let combined = Data(base64Encoded: payload.data) else {
            throw BackupError.corrupted
        }
        let key = deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([PasswordEntry].self, from: plaintext)
        } catch {
            throw BackupError.wrongPassword
        }
    }

    // MARK: - Панели сохранения/открытия (macOS)
    #if os(macOS)
    static func presentExport(_ entries: [PasswordEntry], passphrase: String) throws {
        let data = try encrypt(entries, passphrase: passphrase)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyForge-backup.kfbackup"
        panel.canCreateDirectories = true
        panel.title = "Сохранить зашифрованный бэкап"
        if panel.runModal() == .OK, let url = panel.url {
            try data.write(to: url)
        }
    }

    static func presentImport(passphrase: String) throws -> [PasswordEntry]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Выберите файл бэкапа"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try Data(contentsOf: url)
        return try decrypt(data, passphrase: passphrase)
    }
    #endif
}
