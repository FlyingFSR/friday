import Foundation
import Testing
@testable import FridayMac

struct HUDWaveformShaperTests {
  /// Continuous speech: stays in a narrow, fairly loud band with syllable-sized movement.
  private let steadySpeech: [Float] = (0..<HUDWaveformShaper.historyLength).map { tick in
    let wobble = sin(Float(tick) * 0.9)
    return 0.64 + 0.1 * wobble
  }

  @Test
  func emptyHistoryIsFlat() {
    let heights = HUDWaveformShaper.heights(history: [])
    #expect(heights.count == HUDWaveformShaper.barCount)
    #expect(heights.allSatisfy { $0 == 0 })
  }

  @Test
  func roomNoiseStaysFlat() {
    let noise: [Float] = (0..<HUDWaveformShaper.historyLength).map { Float($0 % 3) * 0.02 + 0.16 }
    #expect(HUDWaveformShaper.heights(history: noise).allSatisfy { $0 == 0 })
  }

  @Test
  func steadySpeechHasClearHighsAndLows() throws {
    let heights = HUDWaveformShaper.heights(history: steadySpeech)
    let inner = Array(heights[6...12])
    let tallest = try #require(inner.max())
    let shortest = try #require(inner.min())
    #expect(tallest > 0.6)
    #expect(shortest < 0.2)
  }

  @Test
  func barsAreMirroredAroundTheMiddle() {
    let heights = HUDWaveformShaper.heights(history: steadySpeech)
    for (left, right) in zip(heights, heights.reversed()) {
      #expect(left == right)
    }
  }

  @Test
  func newestSoundIsInTheMiddle() {
    var history = Array(repeating: Float(0.6), count: HUDWaveformShaper.historyLength - 1)
    history.append(0.9)
    let heights = HUDWaveformShaper.heights(history: history)
    let middle = HUDWaveformShaper.barCount / 2
    #expect(heights[middle] > 0.9)
    #expect(heights[middle - 1] < 0.5)
    #expect(heights[middle + 1] < 0.5)
  }

  /// Bars that look "tall" once the decorative taper is taken back out.
  private func tallBarCount(_ heights: [Double]) -> Int {
    heights.indices.filter {
      heights[$0] / HUDWaveformShaper.envelope(barIndex: $0) >= 0.6
    }.count
  }

  @Test
  func firstWordsAfterKeyPressDoNotFillEveryBar() {
    let silence = Array(repeating: Float(0.15), count: 5)
    let speech: [Float] = (0..<19).map { 0.7 + Float($0 % 4) * 0.02 }
    #expect(tallBarCount(HUDWaveformShaper.heights(history: silence + speech)) < 14)
  }

  @Test
  func speechAfterAPauseDoesNotFillEveryBar() {
    let speech: [Float] = (0..<20).map { 0.7 + Float($0 % 4) * 0.02 }
    let pause = Array(repeating: Float(0.15), count: 16)
    let resumed: [Float] = (0..<12).map { 0.7 + Float($0 % 4) * 0.02 }
    #expect(tallBarCount(HUDWaveformShaper.heights(history: speech + pause + resumed)) < 14)
  }

  @Test
  func silentMomentsStayLowBetweenWords() {
    var history = Array(repeating: Float(0.7), count: 20)
    history.append(0.15)
    let heights = HUDWaveformShaper.heights(history: history)
    #expect(heights[HUDWaveformShaper.barCount / 2] == 0)
  }

  @Test
  func barsTaperTowardBothEnds() {
    let middle = HUDWaveformShaper.barCount / 2
    #expect(HUDWaveformShaper.envelope(barIndex: middle) == 1)
    #expect(HUDWaveformShaper.envelope(barIndex: 0) < 0.3)
    #expect(HUDWaveformShaper.envelope(barIndex: middle - 2) > HUDWaveformShaper.envelope(barIndex: middle - 6))
  }

  @Test
  func olderBarsAreEmptyUntilEnoughSoundHasArrived() {
    let heights = HUDWaveformShaper.heights(history: [0.5, 0.8])
    #expect(heights.count == HUDWaveformShaper.barCount)
    #expect(heights[0] == 0)
    #expect(heights[HUDWaveformShaper.barCount - 1] == 0)
  }
}
