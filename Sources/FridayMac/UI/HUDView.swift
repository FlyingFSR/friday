import SwiftUI

final class HUDViewModel: ObservableObject {
  @Published var state: PipelineState = .idle
  @Published var message: String = "Ready"
  @Published var duration: TimeInterval?
  @Published var level: Float = 0
  @Published var showsCompletionCheck: Bool = false
}

struct HUDView: View {
  @ObservedObject var model: HUDViewModel

  var body: some View {
    let bubbleShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    let bubbleFill = LinearGradient(
      colors: [
        Color(red: 0.90, green: 0.97, blue: 0.92).opacity(0.98),
        Color(red: 0.84, green: 0.94, blue: 0.87).opacity(0.96)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    let primaryTextColor = Color(red: 0.14, green: 0.25, blue: 0.19)
    let secondaryTextColor = Color(red: 0.26, green: 0.39, blue: 0.31)

    ZStack(alignment: .bottomTrailing) {
      HStack(spacing: 14) {
        icon
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(iconColor)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 6) {
          Text(model.message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primaryTextColor)
            .lineLimit(2)

          if model.state == .recording {
            HStack(spacing: 10) {
              WaveBars(level: model.level)
                .frame(width: 66, height: 10)

              if let duration = model.duration {
                Text(String(format: "%.1fs", duration))
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(secondaryTextColor)
              }
            }
          }

          if model.state == .transcribing {
            ProgressView()
              .tint(Color(red: 0.30, green: 0.58, blue: 0.41))
              .controlSize(.small)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }

      if model.showsCompletionCheck && model.state != .pasted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color(red: 0.33, green: 0.71, blue: 0.47))
          .padding(.trailing, 8)
          .padding(.bottom, 8)
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(width: 280, alignment: .leading)
    .background(
      bubbleShape.fill(bubbleFill)
    )
    .overlay(
      bubbleShape
        .stroke(Color(red: 0.61, green: 0.77, blue: 0.66).opacity(0.55), lineWidth: 1)
    )
    .clipShape(bubbleShape)
    .animation(.easeOut(duration: 0.18), value: model.state)
    .animation(.easeOut(duration: 0.16), value: model.showsCompletionCheck)
  }

  private var icon: some View {
    Group {
      switch model.state {
      case .idle:
        Image(systemName: "mic")
      case .recording:
        Image(systemName: "waveform")
      case .transcribing:
        Image(systemName: "ellipsis.circle")
      case .pasted:
        Image(systemName: "checkmark.circle.fill")
      case .error:
        Image(systemName: "exclamationmark.triangle.fill")
      }
    }
  }

  private var iconColor: Color {
    switch model.state {
    case .idle:
      return Color(red: 0.34, green: 0.49, blue: 0.39)
    case .recording:
      return Color(red: 0.28, green: 0.54, blue: 0.38)
    case .transcribing:
      return Color(red: 0.30, green: 0.50, blue: 0.41)
    case .pasted:
      return Color(red: 0.33, green: 0.71, blue: 0.47)
    case .error:
      return Color(red: 0.74, green: 0.34, blue: 0.32)
    }
  }
}

private struct WaveBars: View {
  var level: Float

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<7, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2)
          .fill(Color(red: 0.27, green: 0.50, blue: 0.36).opacity(0.75))
          .frame(
            width: 4,
            height: max(2, CGFloat(level) * CGFloat(6 + index * 2))
          )
      }
    }
    .frame(maxHeight: .infinity, alignment: .center)
  }
}
