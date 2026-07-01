import SwiftUI
import Security
import CryptoKit
#if os(macOS)
import AppKit
import AVKit
#endif

// MARK: - Криптостойкая генерация случайных чисел

enum SecureRandom {
    /// Криптостойкое случайное беззнаковое 32-битное число.
    private static func randomUInt32() -> UInt32 {
        var value: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &value) {
            SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, $0.baseAddress!)
        }
        // На случай сбоя источника — безопасный системный ГПСЧ (тоже криптостойкий на Apple).
        if status != errSecSuccess { return UInt32.random(in: UInt32.min...UInt32.max) }
        return value
    }

    /// Равномерное целое в диапазоне 0..<upperBound без смещения по модулю (rejection sampling).
    static func int(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound должен быть положительным")
        let bound = UInt32(min(upperBound, Int(UInt32.max)))
        let limit = UInt32.max - (UInt32.max % bound)
        var r = randomUInt32()
        while r >= limit { r = randomUInt32() }
        return Int(r % bound)
    }

    /// Криптостойкий выбор случайного элемента коллекции.
    static func element<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        return array[int(array.count)]
    }

    /// Криптостойкое целое в замкнутом диапазоне.
    static func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(range.count)
    }

    /// Криптостойкая перетасовка (Fisher–Yates).
    static func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = int(i + 1)
            result.swapAt(i, j)
        }
        return result
    }
}

// MARK: - Хеширование PIN-кода

enum PINHasher {
    /// SHA-256(соль || PIN) в hex. Соль защищает от радужных таблиц.
    static func hash(_ pin: String, salt: Data) -> String {
        var data = salt
        data.append(Data(pin.utf8))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Случайная соль (16 байт).
    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }
}

// MARK: - Ключевые утилиты

// Хранилище в Keychain
enum Keychain {
    @discardableResult
    static func save(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveString(_ value: String, for key: String) {
        save(Data(value.utf8), for: key)
    }

    static func readString(_ key: String) -> String? {
        guard let data = read(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// Раскрашивает пароль: цифры — синие, символы — розовые, буквы — светлые
func coloredPassword(_ password: String) -> Text {
    var result = Text("")
    for ch in password {
        let piece: Text
        if ch.isNumber {
            piece = Text(String(ch)).foregroundColor(Color(red: 0.45, green: 0.70, blue: 1.0))
        } else if ch.isLetter {
            piece = Text(String(ch)).foregroundColor(.white)
        } else {
            piece = Text(String(ch)).foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.80))
        }
        result = result + piece
    }
    return result
}

#if os(macOS)
// Видео-фон (AppKit layer-backed, зацикленный)
struct VideoBackground: NSViewRepresentable {
    let resource: String
    let ext: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return container
        }

        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = container.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(playerLayer)

        player.isMuted = true
        player.play()
        context.coordinator.player = player
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }
}
#endif

// Общая стеклянная карточка
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Brand.stroke, lineWidth: 1)
            )
    }
}
