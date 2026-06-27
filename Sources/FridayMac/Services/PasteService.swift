import AppKit
import Foundation
import ApplicationServices

final class PasteService {
  private var activeRestoreToken: UUID?

  struct PasteboardPayload {
    let type: NSPasteboard.PasteboardType
    let data: Data
  }

  struct PasteboardSnapshot {
    let items: [[PasteboardPayload]]
  }

  func paste(_ text: String, restoreClipboard: Bool) throws {
    let pasteboard = NSPasteboard.general
    let snapshot = restoreClipboard ? captureSnapshot(from: pasteboard) : nil
    let restoreToken = UUID()
    activeRestoreToken = restoreToken

    try copyToClipboard(text)
    let changeCountAfterInjection = pasteboard.changeCount

    try sendCommandV()

    if let snapshot {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        defer {
          if self.activeRestoreToken == restoreToken {
            self.activeRestoreToken = nil
          }
        }
        guard self.activeRestoreToken == restoreToken else {
          return
        }
        // Skip restore if user or another app already changed clipboard content.
        guard pasteboard.changeCount == changeCountAfterInjection else {
          return
        }
        self.restore(snapshot, to: pasteboard)
      }
    } else {
      activeRestoreToken = nil
    }
  }

  func copyToClipboard(_ text: String) throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      throw FridayError.pasteFailed
    }
  }

  private func sendCommandV() throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      throw FridayError.pasteFailed
    }

    let keyCodeV: CGKeyCode = 9

    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
    else {
      throw FridayError.pasteFailed
    }

    down.flags = .maskCommand
    up.flags = .maskCommand

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  func captureSnapshot(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
    let payload = (pasteboard.pasteboardItems ?? []).map { item in
      var itemPayloads: [PasteboardPayload] = []
      for type in item.types {
        guard let data = item.data(forType: type) else {
          continue
        }
        itemPayloads.append(PasteboardPayload(type: type, data: data))
      }
      return itemPayloads
    }
    return PasteboardSnapshot(items: payload)
  }

  func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !snapshot.items.isEmpty else {
      return
    }

    let pasteboardItems = snapshot.items.map { payloads -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for payload in payloads {
        item.setData(payload.data, forType: payload.type)
      }
      return item
    }

    pasteboard.writeObjects(pasteboardItems)
  }
}
