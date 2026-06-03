#if os(macOS)
import Carbon
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register() {
        unregister()

        // Define the hotkey: Control + Option + Command + G
        let modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_G)

        var eventHotKeyID = EventHotKeyID(signature: OSType(0x484b4d47), id: 1) // 'HKMG'
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Install the event handler
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let hotKeyManager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            hotKeyManager.handleHotKey(eventRef: eventRef)
            return noErr
        }, 1, &eventSpec, selfPointer, &handlerRef)

        guard status == noErr, let handlerRef else {
            eventHandlerRef = nil
            return
        }
        eventHandlerRef = handlerRef

        // Register the hotkey
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, eventHotKeyID, GetApplicationEventTarget(), OptionBits(0), &hotKeyRef)

        if registerStatus != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKey(eventRef: EventRef?) {
        onTrigger?()
    }

    deinit {
        unregister()
    }
}

#else

import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?

    private init() {}

    func register() {}
    func unregister() {}
}

#endif
