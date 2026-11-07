import AppKit
import ApplicationServices
import Foundation

final class HotkeyService {
  enum Transition: Equatable {
    case pressed
    case released
  }

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var globalMonitor: Any?
  // keyCode of the physical key currently holding push-to-talk down, if any.
  private var pressedKeyCode: Int64?
  private(set) var selectedHotkey: PushToTalkKey = .rightCommand

  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?

  func start() throws {
    guard eventTap == nil, globalMonitor == nil else {
      return
    }

    if let tap = makeEventTap() {
      eventTap = tap
      runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

      if let source = runLoopSource {
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      }

      CGEvent.tapEnable(tap: tap, enable: true)
      return
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
      guard let self else { return }
      self.handleFlagsChanged(
        keyCode: Int64(event.keyCode),
        activeModifiers: Self.activeModifiers(in: event.modifierFlags)
      )
    }

    guard globalMonitor != nil else {
      throw FridayError.hotkeyTapUnavailable
    }
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }

    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }

    runLoopSource = nil
    eventTap = nil
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    pressedKeyCode = nil
  }

  var isRunning: Bool {
    eventTap != nil || globalMonitor != nil
  }

  func setSelectedHotkey(_ hotkey: PushToTalkKey) {
    guard selectedHotkey != hotkey else {
      return
    }

    if pressedKeyCode != nil {
      pressedKeyCode = nil
      DispatchQueue.main.async { [weak self] in
        self?.onRelease?()
      }
    }
    selectedHotkey = hotkey
  }

  private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else {
      return Unmanaged.passUnretained(event)
    }

    handleFlagsChanged(
      keyCode: event.getIntegerValueField(.keyboardEventKeycode),
      activeModifiers: Self.activeModifiers(in: event.flags)
    )

    return Unmanaged.passUnretained(event)
  }

  private func makeEventTap() -> CFMachPort? {
    let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else {
        return Unmanaged.passUnretained(event)
      }

      let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
      return service.handleEvent(type: type, event: event)
    }

    return CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func handleFlagsChanged(keyCode: Int64, activeModifiers: Set<PushToTalkModifier>) {
    switch Self.transition(
      for: selectedHotkey,
      keyCode: keyCode,
      activeModifiers: activeModifiers,
      pressedKeyCode: pressedKeyCode
    ) {
    case .pressed:
      pressedKeyCode = keyCode
      DispatchQueue.main.async { [weak self] in
        self?.onPress?()
      }
    case .released:
      pressedKeyCode = nil
      DispatchQueue.main.async { [weak self] in
        self?.onRelease?()
      }
    case nil:
      break
    }
  }

  static func transition(
    for hotkey: PushToTalkKey,
    keyCode: Int64,
    activeModifiers: Set<PushToTalkModifier>,
    pressedKeyCode: Int64?
  ) -> Transition? {
    if let pressedKeyCode {
      // flagsChanged is emitted for the held physical key's transition.
      // Release even if the same modifier on the other side is still held;
      // ignore the other accepted key while one is already holding.
      return keyCode == pressedKeyCode ? .released : nil
    }
    guard let key = hotkey.physicalKeys.first(where: { $0.keyCode == keyCode }) else {
      return nil
    }
    return activeModifiers.contains(key.modifier) ? .pressed : nil
  }

  private static func activeModifiers(in flags: CGEventFlags) -> Set<PushToTalkModifier> {
    var modifiers: Set<PushToTalkModifier> = []
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    return modifiers
  }

  private static func activeModifiers(in flags: NSEvent.ModifierFlags) -> Set<PushToTalkModifier> {
    var modifiers: Set<PushToTalkModifier> = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    return modifiers
  }
}
