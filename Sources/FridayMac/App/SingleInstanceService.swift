import Foundation

extension Notification.Name {
  static let fridayActivateExisting = Notification.Name("FridayActivateExisting")
}

enum SingleInstanceAcquireResult {
  case acquired
  case alreadyRunning
  case failed(String)
}

final class SingleInstanceService {
  private let activationTokenKey = "activationToken"
  private var lockFileDescriptor: Int32 = -1
  private let lockFileURL: URL
  private let tokenFileURL: URL
  private let fileManager: FileManager
  private var localActivationToken: String?
  private var existingInstanceToken: String?

  init(fileManager: FileManager = .default, appSupportDirectory: URL? = nil) {
    self.fileManager = fileManager
    let appSupport = appSupportDirectory
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let fridayDirectory = appSupport.appendingPathComponent("Friday", isDirectory: true)
    lockFileURL = fridayDirectory.appendingPathComponent("instance.lock")
    tokenFileURL = fridayDirectory.appendingPathComponent("instance.token")
  }

  func acquireLock() -> SingleInstanceAcquireResult {
    guard lockFileDescriptor == -1 else {
      return .acquired
    }

    do {
      try fileManager.createDirectory(at: lockFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      return .failed("create lock directory failed: \(error.localizedDescription)")
    }

    let descriptor = open(lockFileURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      let code = errno
      return .failed("open lock file failed: \(errorMessage(for: code))")
    }

    if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let code = errno
      let message = errorMessage(for: code)
      close(descriptor)
      if code == EWOULDBLOCK {
        existingInstanceToken = readActivationTokenFromDisk()
        return .alreadyRunning
      }
      return .failed("acquire lock failed: \(message)")
    }

    lockFileDescriptor = descriptor
    localActivationToken = UUID().uuidString
    existingInstanceToken = nil
    persistActivationToken(localActivationToken)
    return .acquired
  }

  func releaseLock() {
    guard lockFileDescriptor >= 0 else {
      return
    }

    flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)
    lockFileDescriptor = -1
    localActivationToken = nil
    existingInstanceToken = nil
    try? fileManager.removeItem(at: tokenFileURL)
  }

  func notifyExistingInstanceToActivate() {
    let token = existingInstanceToken ?? readActivationTokenFromDisk()
    guard let token, !token.isEmpty else {
      return
    }

    DistributedNotificationCenter.default().postNotificationName(
      .fridayActivateExisting,
      object: nil,
      userInfo: [activationTokenKey: token],
      options: [.deliverImmediately]
    )
  }

  func shouldAcceptActivation(_ userInfo: [AnyHashable: Any]?) -> Bool {
    guard let localActivationToken else {
      return false
    }
    guard let incomingToken = userInfo?[activationTokenKey] as? String else {
      return false
    }
    return incomingToken == localActivationToken
  }

  func currentActivationToken() -> String? {
    localActivationToken
  }

  deinit {
    releaseLock()
  }

  private func persistActivationToken(_ token: String?) {
    guard let token else {
      return
    }
    try? token.write(to: tokenFileURL, atomically: true, encoding: .utf8)
  }

  private func readActivationTokenFromDisk() -> String? {
    guard fileManager.fileExists(atPath: tokenFileURL.path) else {
      return nil
    }
    return try? String(contentsOf: tokenFileURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func errorMessage(for code: Int32) -> String {
    String(cString: strerror(code))
  }
}
