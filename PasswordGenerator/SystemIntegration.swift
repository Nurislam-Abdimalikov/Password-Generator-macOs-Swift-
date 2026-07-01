import Foundation
#if os(macOS)
import AppKit
import ServiceManagement
#endif

// MARK: - Интеграция с системой: автозапуск и режим меню-бара

enum SystemIntegration {

    // Автозапуск при входе в систему (macOS 13+).
    static var launchAtLoginEnabled: Bool {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
        #else
        return false
        #endif
    }

    @discardableResult
    static func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        #if os(macOS)
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // Режим «только меню-бар»: прятать иконку в Dock, жить в строке меню.
    static func setMenuBarOnly(_ enabled: Bool) {
        #if os(macOS)
        NSApp.setActivationPolicy(enabled ? .accessory : .regular)
        if !enabled { NSApp.activate(ignoringOtherApps: true) }
        #endif
    }
}
