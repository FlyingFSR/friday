import Testing
import AppKit
@testable import FridayMac

struct PasteServiceClipboardTests {
  // Use an isolated, uniquely-named pasteboard so tests never touch the user's
  // real clipboard and can run in parallel without interfering with each other.
  private func makeScratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("friday-test-\(UUID().uuidString)"))
  }

  @Test
  func snapshotRestoreRoundTripsMultipleItemsAndTypes() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    let plain = NSPasteboardItem()
    plain.setString("hello world", forType: .string)
    let rich = NSPasteboardItem()
    rich.setString("https://example.com", forType: .string)
    rich.setString("<a href=\"https://example.com\">link</a>", forType: .html)
    pasteboard.clearContents()
    pasteboard.writeObjects([plain, rich])

    let service = PasteService()
    let snapshot = service.captureSnapshot(from: pasteboard)

    // Simulate Friday overwriting the clipboard with the transcribed text.
    pasteboard.clearContents()
    pasteboard.setString("TRANSCRIBED", forType: .string)

    service.restore(snapshot, to: pasteboard)

    let items = pasteboard.pasteboardItems ?? []
    #expect(items.count == 2)
    #expect(items.first?.string(forType: .string) == "hello world")
    let restoredRich = items.dropFirst().first
    #expect(restoredRich?.string(forType: .string) == "https://example.com")
    #expect(restoredRich?.string(forType: .html) == "<a href=\"https://example.com\">link</a>")
  }

  @Test
  func snapshotIsAValueCopyUnaffectedByLaterClipboardChanges() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)

    let service = PasteService()
    let snapshot = service.captureSnapshot(from: pasteboard)

    // The clipboard changes after the snapshot is taken; restore must still
    // reproduce what was captured, not the later content.
    pasteboard.clearContents()
    pasteboard.setString("overwritten", forType: .string)

    service.restore(snapshot, to: pasteboard)

    #expect(pasteboard.string(forType: .string) == "original")
  }
}
