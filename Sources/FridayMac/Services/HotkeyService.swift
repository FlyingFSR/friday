import AppKit
import ApplicationServices
import Foundation

final class HotkeyService {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var globalMonitor: Any?
  private var isPressed = false
  private let rightCommandKeyCode: CGKeyCode = 54

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
      self?.handleFlagsChanged(
        keyCode: Int64(event.keyCode),
        hasCommand: event.modifierFlags.contains(.command)
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
      hasCommand: event.flags.contains(.maskCommand)
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

  private func handleFlagsChanged(keyCode: Int64, hasCommand: Bool) {
    guard keyCode == Int64(rightCommandKeyCode) else {
      return
    }

    if hasCommand && !isPressed {
      isPressed = true
      DispatchQueue.main.async { [weak self] in
        self?.onPress?()
      }
    } else if !hasCommand && isPressed {
      isPressed = false
      DispatchQueue.main.async { [weak self] in
        self?.onRelease?()
      }
    }
  }
}
