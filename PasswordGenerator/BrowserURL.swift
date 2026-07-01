import Foundation
#if os(macOS)
import AppKit

// MARK: - Определение сайта из активной вкладки браузера
//
// Через Apple Events спрашиваем у браузера адрес открытой вкладки и достаём домен.
// Требуется entitlement com.apple.security.automation.apple-events (build-настройка
// AUTOMATION_APPLE_EVENTS = YES) и пояснение NSAppleEventsUsageDescription.
// При первом обращении система один раз спросит разрешение на управление браузером.
//
// currentSite() возвращает домен ИЛИ текст ошибки с номером — чтобы было видно причину
// (например -1743 = нет разрешения/entitlement, -600 = браузер не запущен).

enum BrowserURL {
    struct Browser { let bundleID: String; let name: String; let script: String }

    // Порядок = приоритет. Берём первый запущенный браузер.
    static let browsers: [Browser] = [
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome",
                script: "tell application \"Google Chrome\" to get URL of active tab of front window"),
        Browser(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary",
                script: "tell application \"Google Chrome Canary\" to get URL of active tab of front window"),
        Browser(bundleID: "com.brave.Browser", name: "Brave Browser",
                script: "tell application \"Brave Browser\" to get URL of active tab of front window"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge",
                script: "tell application \"Microsoft Edge\" to get URL of active tab of front window"),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi",
                script: "tell application \"Vivaldi\" to get URL of active tab of front window"),
        Browser(bundleID: "com.apple.Safari", name: "Safari",
                script: "tell application \"Safari\" to get URL of front document")
    ]

    /// Короткий вызов: только домен (или nil).
    static func currentSiteDomain() -> String? { currentSite().domain }

    /// Домен активной вкладки + причина, если не получилось.
    static func currentSite() -> (domain: String?, error: String?) {
        let running = browsers.filter { isRunning($0.bundleID) }
        guard !running.isEmpty else {
            return (nil, "Ни один поддерживаемый браузер не запущен (Chrome/Brave/Edge/Vivaldi/Safari).")
        }
        var lastError: String?
        for browser in running {
            var errInfo: NSDictionary?
            guard let script = NSAppleScript(source: browser.script) else { continue }
            let output = script.executeAndReturnError(&errInfo)
            if let err = errInfo {
                let msg = (err[NSAppleScript.errorMessage] as? String) ?? "неизвестная ошибка"
                let num = (err[NSAppleScript.errorNumber] as? Int).map { String($0) } ?? "?"
                lastError = "\(browser.name): \(msg) [код \(num)]"
                continue
            }
            if let urlString = output.stringValue, let host = domain(from: urlString) {
                return (host, nil)
            }
            lastError = "\(browser.name): нет открытой вкладки с адресом http(s)."
        }
        return (nil, lastError ?? "Не удалось получить адрес вкладки.")
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func domain(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let host = comps.host, !host.isEmpty else { return nil }
        if let scheme = comps.scheme, scheme != "http", scheme != "https" { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
