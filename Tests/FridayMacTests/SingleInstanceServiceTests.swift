import Foundation
import Testing
@testable import FridayMac

struct SingleInstanceServiceTests {
  @Test
  func activationTokenValidationRejectsWrongToken() throws {
    let fileManager = FileManager.default
    let appSupportDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("friday-instance-test-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: appSupportDirectory)
    }

    let service = SingleInstanceService(fileManager: fileManager, appSupportDirectory: appSupportDirectory)
    defer {
      service.releaseLock()
    }

    let result = service.acquireLock()
    switch result {
    case .acquired:
      break
    case .alreadyRunning:
      Issue.record("Expected lock acquisition in isolated test directory.")
      return
    case .failed(let reason):
      Issue.record("Lock acquisition failed: \(reason)")
      return
    }

    let token = try #require(service.currentActivationToken())
    #expect(service.shouldAcceptActivation(["activationToken": token]))
    #expect(!service.shouldAcceptActivation(["activationToken": "wrong-token"]))
    #expect(!service.shouldAcceptActivation(nil))
  }
}
