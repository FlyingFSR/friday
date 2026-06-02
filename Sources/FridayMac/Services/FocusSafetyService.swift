import Carbon
import Foundation

final class FocusSafetyService {
  func shouldBlockPaste(blockSecureInput: Bool) -> Bool {
    guard blockSecureInput else {
      return false
    }
    return IsSecureEventInputEnabled()
  }
}
