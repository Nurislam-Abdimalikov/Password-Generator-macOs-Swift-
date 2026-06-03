import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct PasswordGeneratorApp: App {
    // Одна общая модель для окна и для строки меню
    @StateObject private var vm = PasswordViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentSize)

#if os(macOS)
        // 🧰 Иконка в строке меню — быстрая генерация без открытия окна
        MenuBarExtra("KeyForge", systemImage: "key.fill") {
            MenuBarView()
                .environmentObject(vm)
        }
        .menuBarExtraStyle(.window)
#endif
    }
}
