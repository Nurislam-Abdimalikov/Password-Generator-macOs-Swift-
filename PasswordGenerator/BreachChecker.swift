import Foundation
import CryptoKit

// MARK: - Проверка пароля на утечки через Have I Been Pwned (k-anonymity)
//
// Приватность: сам пароль НИКОГДА не отправляется в сеть. Считаем SHA-1,
// отправляем только первые 5 символов хеша (префикс). Сервис возвращает
// все суффиксы с этим префиксом, а сравнение делаем локально.
//
// ВНИМАНИЕ: для сетевого запроса в песочнице нужен доступ «Outgoing Connections».
// Он включён build-настройкой ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES.

enum BreachResult: Equatable {
    case safe
    case pwned(count: Int)
    case error(String)
}

enum BreachChecker {
    private static func sha1Hex(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    static func check(_ password: String) async -> BreachResult {
        guard !password.isEmpty else { return .safe }
        let hash = sha1Hex(password)
        let prefix = String(hash.prefix(5))
        let suffix = String(hash.dropFirst(5))

        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else {
            return .error("Некорректный запрос")
        }
        var request = URLRequest(url: url)
        request.addValue("KeyForge-PasswordGenerator", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let body = String(data: data, encoding: .utf8) else {
                return .error("Сервис недоступен")
            }
            for line in body.split(separator: "\n") {
                let parts = line.split(separator: ":")
                guard parts.count == 2 else { continue }
                if parts[0].trimmingCharacters(in: .whitespaces).uppercased() == suffix {
                    let count = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    return .pwned(count: count)
                }
            }
            return .safe
        } catch {
            return .error("Нет сети: \(error.localizedDescription)")
        }
    }
}
