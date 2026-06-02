import Testing
@testable import FridayMac

struct AudioCaptureSessionTests {
  @Test
  func startStopArmsCaptureWithoutLiveSampling() throws {
    let service = AudioCaptureService()

    #expect(service.isContinuousCaptureRunning == false)
    try service.startContinuousCapture()
    #expect(service.isContinuousCaptureRunning == true)

    service.stopContinuousCapture()
    #expect(service.isContinuousCaptureRunning == false)
  }
}
