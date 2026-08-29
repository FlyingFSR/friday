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
  private var isPressed = false
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
        modifierIsActive: self.modifierIsActive(in: event.modifierFlags)
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
    isPressed = false
  }

  var isRunning: Bool {
    eventTap != nil || globalMonitor != nil
  }

  func setSelectedHotkey(_ hotkey: PushToTalkKey) {
    guard selectedHotkey != hotkey else {
      return
    }

    if isPressed {
      isPressed = false
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
      modifierIsActive: modifierIsActive(in: event.flags)
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

  private func handleFlagsChanged(keyCode: Int64, modifierIsActive: Bool) {
    switch Self.transition(
      for: selectedHotkey,
      keyCode: keyCode,
      modifierIsActive: modifierIsActive,
      wasPressed: isPressed
    ) {
    case .pressed:
      isPressed = true
      DispatchQueue.main.async { [weak self] in
        self?.onPress?()
      }
    case .released:
      isPressed = false
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
    modifierIsActive: Bool,
    wasPressed: Bool
  ) -> Transition? {
    guard keyCode == hotkey.keyCode else {
      return nil
    }
    if wasPressed {
      // flagsChanged is emitted for the selected physical key's transition.
      // Release even if the same modifier on the other side is still held.
      return .released
    }
    return modifierIsActive ? .pressed : nil
  }

  private func modifierIsActive(in flags: CGEventFlags) -> Bool {
    switch selectedHotkey.modifier {
    case .command:
      return flags.contains(.maskCommand)
    case .option:
      return flags.contains(.maskAlternate)
    case .control:
      return flags.contains(.maskControl)
    }
  }

  private func modifierIsActive(in flags: NSEvent.ModifierFlags) -> Bool {
    switch selectedHotkey.modifier {
    case .command:
      return flags.contains(.command)
    case .option:
      return flags.contains(.option)
    case .control:
      return flags.contains(.control)
    }
  }
}
