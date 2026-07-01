import Foundation
#if os(macOS)
import AppKit

// MARK: - Определение сайта из активной вкладки браузера
//
// Через Apple Events спрашиваем у браузера адрес открытой вкладки и достаём домен.
// Требуется entitlement com.apple.security.automation.apple-events (build-настройка
// AUTOMATION_APPLE_EVENTS = YES) и пояснение NSAppleEventsUsageDescription.
// При первом обращении система один раз спросит разрешение на управление браузером.
// Если пользователь откажет — просто вернём nil и поле сайта останется пустым.

enum BrowserURL {
    private struct Browser { let bundleID: String; let script: String }

    // Порядок = приоритет. Берём первый запущенный браузер.
    private static let browsers: [Browser] = [
        Browser(bundleID: "com.google.Chrome",
                script: "tell application \"Google Chrome\" to get URL of active tab of front window"),
        Browser(bundleID: "com.google.Chrome.canary",
                script: "tell application \"Google Chrome Canary\" to get URL of active tab of front window"),
        Browser(bundleID: "com.brave.Browser",
                script: "tell application \"Brave Browser\" to get URL of active tab of front window"),
        Browser(bundleID: "com.microsoft.edgemac",
                script: "tell application \"Microsoft Edge\" to get URL of active tab of front window"),
        Browser(bundleID: "com.vivaldi.Vivaldi",
                script: "tell application \"Vivaldi\" to get URL of active tab of front window"),
        Browser(bundleID: "com.apple.Safari",
                script: "tell application \"Safari\" to get URL of front document")
    ]

    /// Домен активной вкладки первого запущенного браузера, либо nil.
    static func currentSiteDomain() -> String? {
        for browser in browsers where isRunning(browser.bundleID) {
            if let urlString = runScript(browser.script),
               let host = domain(from: urlString) {
                return host
            }
        }
        return nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }

    private static func domain(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let host = comps.host, !host.isEmpty else { return nil }
        // Только http/https — служебные страницы (chrome://, about:) игнорируем.
        if let scheme = comps.scheme, scheme != "http", scheme != "https" { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
