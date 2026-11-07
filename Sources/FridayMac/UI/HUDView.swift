import SwiftUI

final class HUDViewModel: ObservableObject {
  /// How many recent mic levels the recording waveform shows (one per meter tick, ~60 ms each).
  static let waveformLength = 18

  @Published var state: PipelineState = .idle
  @Published var message: String = "Ready"
  @Published var duration: TimeInterval?
  @Published var level: Float = 0
  @Published var levels: [Float] = Array(repeating: 0, count: HUDViewModel.waveformLength)
  @Published var showsCompletionCheck: Bool = false

  func push(level: Float) {
    self.level = level
    var next = levels
    next.removeFirst()
    next.append(level)
    levels = next
  }

  func resetLevels() {
    level = 0
    levels = Array(repeating: 0, count: Self.waveformLength)
  }
}

/// One knob for the pill's overall size; every dimension below is multiplied by it.
private enum HUDSize {
  static let scale: CGFloat = 1.4
  static func of(_ value: CGFloat) -> CGFloat { value * scale }
}

/// Compact pill shown near the cursor. Recording: pulsing dot + live scrolling waveform + timer.
/// Other states: one icon + the status message. Mint green in light mode, deep green in dark mode.
struct HUDView: View {
  @ObservedObject var model: HUDViewModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = HUDPalette(dark: colorScheme == .dark)
    let shape = RoundedRectangle(cornerRadius: HUDSize.of(17), style: .continuous)

    HStack(spacing: HUDSize.of(9)) {
      switch model.state {
      case .recording:
        RecordingDot(color: palette.recordDot)
        Waveform(levels: model.levels, color: palette.wave)
        Text(String(format: "%.1fs", model.duration ?? 0))
          .font(.system(size: HUDSize.of(12), weight: .medium).monospacedDigit())
          .foregroundStyle(palette.secondaryText)
      case .transcribing:
        Spinner(color: palette.wave)
        messageText(palette)
      case .pasted, .idle:
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: HUDSize.of(14), weight: .semibold))
          .foregroundStyle(palette.success)
        messageText(palette)
      case .error:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: HUDSize.of(13), weight: .semibold))
          .foregroundStyle(palette.error)
        messageText(palette)
      }
    }
    .padding(.horizontal, HUDSize.of(13))
    .frame(minHeight: HUDSize.of(34))
    .padding(.vertical, model.state == .error ? HUDSize.of(6) : 0)
    .background(shape.fill(palette.fill))
    .overlay(shape.strokeBorder(palette.stroke, lineWidth: 1))
    .clipShape(shape)
    .fixedSize()
    .animation(.easeOut(duration: 0.16), value: model.state)
  }

  private func messageText(_ palette: HUDPalette) -> some View {
    Text(model.message)
      .font(.system(size: HUDSize.of(12.5), weight: .semibold))
      .foregroundStyle(palette.primaryText)
      .lineLimit(3)
      .frame(maxWidth: HUDSize.of(300), alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct HUDPalette {
  let fill: LinearGradient
  let stroke: Color
  let primaryText: Color
  let secondaryText: Color
  let wave: Color
  let recordDot: Color
  let success: Color
  let error: Color

  init(dark: Bool) {
    if dark {
      fill = LinearGradient(
        colors: [Color(red: 0.12, green: 0.24, blue: 0.17), Color(red: 0.09, green: 0.19, blue: 0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      stroke = Color(red: 0.36, green: 0.58, blue: 0.44).opacity(0.55)
      primaryText = Color(red: 0.86, green: 0.95, blue: 0.89)
      secondaryText = Color(red: 0.66, green: 0.80, blue: 0.71)
      wave = Color(red: 0.55, green: 0.85, blue: 0.65)
      recordDot = Color(red: 1.00, green: 0.42, blue: 0.38)
      success = Color(red: 0.49, green: 0.86, blue: 0.60)
      error = Color(red: 1.00, green: 0.55, blue: 0.48)
    } else {
      fill = LinearGradient(
        colors: [Color(red: 0.90, green: 0.97, blue: 0.92), Color(red: 0.84, green: 0.94, blue: 0.87)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      stroke = Color(red: 0.61, green: 0.77, blue: 0.66).opacity(0.7)
      primaryText = Color(red: 0.14, green: 0.25, blue: 0.19)
      secondaryText = Color(red: 0.26, green: 0.39, blue: 0.31)
      wave = Color(red: 0.24, green: 0.50, blue: 0.34)
      recordDot = Color(red: 0.88, green: 0.30, blue: 0.27)
      success = Color(red: 0.24, green: 0.62, blue: 0.38)
      error = Color(red: 0.74, green: 0.34, blue: 0.32)
    }
  }
}

/// Small dot that gently pulses while recording.
private struct RecordingDot: View {
  let color: Color

  var body: some View {
    TimelineView(.animation) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
      let pulse = 0.5 + 0.5 * cos(phase * 2 * .pi)
      Circle()
        .fill(color)
        .frame(width: HUDSize.of(8), height: HUDSize.of(8))
        .opacity(0.55 + 0.45 * pulse)
    }
    .frame(width: HUDSize.of(8), height: HUDSize.of(8))
  }
}

/// Rotating arc, drawn by hand so it matches the pill's colors.
private struct Spinner: View {
  let color: Color

  var body: some View {
    TimelineView(.animation) { context in
      let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
      ZStack {
        Circle().stroke(color.opacity(0.22), lineWidth: HUDSize.of(2))
        Circle()
          .trim(from: 0, to: 0.28)
          .stroke(color, style: StrokeStyle(lineWidth: HUDSize.of(2), lineCap: .round))
          .rotationEffect(.degrees(turns * 360))
      }
      .frame(width: HUDSize.of(13), height: HUDSize.of(13))
    }
    .frame(width: HUDSize.of(16), height: HUDSize.of(16))
  }
}

/// Recent mic levels, oldest on the left, newest entering on the right.
private struct Waveform: View {
  let levels: [Float]
  let color: Color

  var body: some View {
    HStack(alignment: .center, spacing: HUDSize.of(2)) {
      ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
        Capsule()
          .fill(color)
          .frame(width: HUDSize.of(2.5), height: Self.barHeight(for: level))
      }
    }
    .frame(height: HUDSize.of(16))
    .animation(.linear(duration: 0.06), value: levels)
  }

  /// Speech sits roughly at 0.4–0.7 on the meter's linear -60…0 dB scale; a mild curve keeps
  /// room noise low and lets louder syllables reach the top.
  static func barHeight(for level: Float) -> CGFloat {
    let shaped = pow(Double(max(0, min(1, level))), 1.5)
    return HUDSize.of(3) + CGFloat(shaped) * HUDSize.of(13)
  }
}
