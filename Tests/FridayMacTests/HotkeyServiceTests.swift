import Testing
@testable import FridayMac

struct HotkeyServiceTests {
  private let all: Set<PushToTalkModifier> = [.command, .option, .control]

  @Test
  func supportedHotkeysUseExpectedMacKeyCodesAndModifiers() {
    let expected: [(PushToTalkKey, [(Int64, PushToTalkModifier)])] = [
      (.rightCommand, [(0x36, .command)]),
      (.leftCommand, [(0x37, .command)]),
      (.rightOption, [(0x3D, .option)]),
      (.leftOption, [(0x3A, .option)]),
      (.rightControl, [(0x3E, .control)]),
      (.rightCommandOrControl, [(0x36, .command), (0x3E, .control)])
    ]

    #expect(PushToTalkKey.allCases.count == expected.count)
    for (hotkey, keys) in expected {
      #expect(hotkey.physicalKeys.map(\.keyCode) == keys.map(\.0))
      #expect(hotkey.physicalKeys.map(\.modifier) == keys.map(\.1))
    }
  }

  @Test
  func everyAcceptedPhysicalKeyProducesPressAndReleaseTransitions() {
    for hotkey in PushToTalkKey.allCases {
      for key in hotkey.physicalKeys {
        #expect(HotkeyService.transition(
          for: hotkey,
          keyCode: key.keyCode,
          activeModifiers: [key.modifier],
          pressedKeyCode: nil
        ) == .pressed)
        #expect(HotkeyService.transition(
          for: hotkey,
          keyCode: key.keyCode,
          activeModifiers: [],
          pressedKeyCode: key.keyCode
        ) == .released)
      }
    }
  }

  @Test
  func matcherIgnoresWrongKeyAndInactiveModifierPress() {
    #expect(HotkeyService.transition(
      for: .rightOption,
      keyCode: PushToTalkPhysicalKey.leftOption.keyCode,
      activeModifiers: all,
      pressedKeyCode: nil
    ) == nil)
    #expect(HotkeyService.transition(
      for: .rightOption,
      keyCode: PushToTalkPhysicalKey.rightOption.keyCode,
      activeModifiers: [],
      pressedKeyCode: nil
    ) == nil)
    // A press only counts when the matching key's own modifier is active.
    #expect(HotkeyService.transition(
      for: .rightCommandOrControl,
      keyCode: PushToTalkPhysicalKey.rightControl.keyCode,
      activeModifiers: [.command],
      pressedKeyCode: nil
    ) == nil)
  }

  @Test
  func combinedHotkeyIgnoresLeftSideKeys() {
    for key in [PushToTalkPhysicalKey.leftCommand, .leftOption, .rightOption] {
      #expect(HotkeyService.transition(
        for: .rightCommandOrControl,
        keyCode: key.keyCode,
        activeModifiers: all,
        pressedKeyCode: nil
      ) == nil)
    }
  }

  @Test
  func releaseStillMatchesWhenOtherSideModifierRemainsActive() {
    #expect(HotkeyService.transition(
      for: .rightCommand,
      keyCode: PushToTalkPhysicalKey.rightCommand.keyCode,
      activeModifiers: [.command],
      pressedKeyCode: PushToTalkPhysicalKey.rightCommand.keyCode
    ) == .released)
  }

  @Test
  func combinedHotkeyOnlyReleasesOnTheKeyThatStartedIt() {
    let rightCommand = PushToTalkPhysicalKey.rightCommand.keyCode
    let rightControl = PushToTalkPhysicalKey.rightControl.keyCode
    // Holding Right Command, tapping Right Control neither restarts nor ends it.
    #expect(HotkeyService.transition(
      for: .rightCommandOrControl,
      keyCode: rightControl,
      activeModifiers: [.command, .control],
      pressedKeyCode: rightCommand
    ) == nil)
    #expect(HotkeyService.transition(
      for: .rightCommandOrControl,
      keyCode: rightControl,
      activeModifiers: [.command],
      pressedKeyCode: rightCommand
    ) == nil)
    #expect(HotkeyService.transition(
      for: .rightCommandOrControl,
      keyCode: rightCommand,
      activeModifiers: [.control],
      pressedKeyCode: rightCommand
    ) == .released)
  }

  @Test
  func combinedHotkeyRoundTripsThroughSettingsRawValue() {
    #expect(PushToTalkKey(rawValue: "right_command_or_control") == .rightCommandOrControl)
  }
}
