// Adapted from WindowPaste, MIT; upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import Carbon
import Foundation

/// Carbon 回调不能捕获上下文，所以用全局入口转到 AppState。
private var registeredHotKeyHandler: (() -> Void)?

private func carbonHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    registeredHotKeyHandler?()
    return noErr
}

@MainActor
final class WindowPasteHotKeyManager {
    static let shared = WindowPasteHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var activeHotKey: WindowPasteHotKey?

    func setHandler(_ handler: @escaping () -> Void) {
        registeredHotKeyHandler = {
            DispatchQueue.main.async {
                handler()
            }
        }
        ensureEventHandler()
    }

    @discardableResult
    func apply(_ hotKey: WindowPasteHotKey) -> WindowPasteHotKeyRegisterResult {
        if let problem = hotKey.problem() {
            return problem
        }

        removeHotKeyRef()
        let status = registerRef(hotKey)
        if status == noErr {
            activeHotKey = hotKey
            return .registered
        }

        if let activeHotKey {
            _ = registerRef(activeHotKey)
        }

        if status == eventHotKeyExistsErr {
            return .conflict(L10n.tr("这个快捷键已被其他软件占用"))
        }
        return .failed(L10n.tr("快捷键注册失败（%1$@）", String(describing: status)))
    }

    func suspend() {
        removeHotKeyRef()
    }

    func resume() {
        guard let activeHotKey else { return }
        _ = registerRef(activeHotKey)
    }

    func unregister() {
        removeHotKeyRef()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        registeredHotKeyHandler = nil
        activeHotKey = nil
    }

    private func ensureEventHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerRef(_ hotKey: WindowPasteHotKey) -> OSStatus {
        removeHotKeyRef()
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCode("AMWP")
        hotKeyID.id = 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
        return status
    }

    private func removeHotKeyRef() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(byte)
    }
    return result
}
