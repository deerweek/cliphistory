import Carbon
import Foundation

final class HotkeyListener: @unchecked Sendable {
    var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature = fourCharCode("CLPH")

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(_ combo: HotkeyCombo) {
        unregister()
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("剪贴板记录注册快捷键失败：\(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    fileprivate func handlePress() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onPress?()
            }
        }
    }

    private func installHandler() {
        HotkeyBridge.listener = self
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}

private enum HotkeyBridge {
    static weak var listener: HotkeyListener?
}

private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    HotkeyBridge.listener?.handlePress()
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + UInt32(byte)
    }
    return result
}

extension HotkeyCombo {
    var keyCode: UInt32 {
        switch self {
        case .commandD, .shiftCommandD:
            return UInt32(kVK_ANSI_D)
        case .shiftCommandV, .optionCommandV, .controlCommandV:
            return UInt32(kVK_ANSI_V)
        case .optionSpace:
            return UInt32(kVK_Space)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandD:
            return UInt32(cmdKey)
        case .shiftCommandD, .shiftCommandV:
            return UInt32(cmdKey | shiftKey)
        case .optionCommandV:
            return UInt32(cmdKey | optionKey)
        case .controlCommandV:
            return UInt32(cmdKey | controlKey)
        case .optionSpace:
            return UInt32(optionKey)
        }
    }
}
