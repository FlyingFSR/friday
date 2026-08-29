import Testing
@testable import FridayMac

struct HotkeyServiceTests {
  @Test
  func supportedHotkeysUseExpectedMacKeyCodesAndModifiers() {
    let expected: [(PushToTalkKey, Int64, PushToTalkModifier)] = [
      (.rightCommand, 0x36, .command),
      (.leftCommand, 0x37, .command),
      (.rightOption, 0x3D, .option),
      (.leftOption, 0x3A, .option),
      (.rightControl, 0x3E, .control)
    ]

    #expect(PushToTalkKey.allCases.count == expected.count)
    for (hotkey, keyCode, modifier) in expected {
      #expect(hotkey.keyCode == keyCode)
      #expect(hotkey.modifier == modifier)
    }
  }

  @Test
  func eachSupportedHotkeyProducesPressAndReleaseTransitions() {
    for hotkey in PushToTalkKey.allCases {
      #expect(HotkeyService.transition(
        for: hotkey,
        keyCode: hotkey.keyCode,
        modifierIsActive: true,
        wasPressed: false
      ) == .pressed)
      #expect(HotkeyService.transition(
        for: hotkey,
        keyCode: hotkey.keyCode,
        modifierIsActive: false,
        wasPressed: true
      ) == .released)
    }
  }

  @Test
  func matcherIgnoresWrongKeyAndInactiveModifierPress() {
    #expect(HotkeyService.transition(
      for: .rightOption,
      keyCode: PushToTalkKey.leftOption.keyCode,
      modifierIsActive: true,
      wasPressed: false
    ) == nil)
    #expect(HotkeyService.transition(
      for: .rightOption,
      keyCode: PushToTalkKey.rightOption.keyCode,
      modifierIsActive: false,
      wasPressed: false
    ) == nil)
  }

  @Test
  func releaseStillMatchesWhenOtherSideModifierRemainsActive() {
    #expect(HotkeyService.transition(
      for: .rightCommand,
      keyCode: PushToTalkKey.rightCommand.keyCode,
      modifierIsActive: true,
      wasPressed: true
    ) == .released)
  }
}
