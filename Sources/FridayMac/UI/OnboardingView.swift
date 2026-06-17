import SwiftUI

struct OnboardingView: View {
  @ObservedObject var controller: FridayController

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("Friday Setup")
          .font(.system(size: 24, weight: .semibold))

        Text("Complete setup in order: microphone, accessibility, input monitoring, then download your default model.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)

        stepCard(
          index: 1,
          title: "Microphone Permission",
          description: "Needed to record voice while holding Right Command.",
          done: controller.permissions.microphone,
          actionTitle: "Grant Microphone",
          action: controller.requestMicrophoneAccess,
          settingsAction: controller.openMicrophoneSettings
        )

        stepCard(
          index: 2,
          title: "Accessibility Permission",
          description: "Needed to trigger paste into other apps.",
          done: controller.permissions.accessibility,
          actionTitle: "Grant Accessibility",
          action: controller.requestAccessibilityAccess,
          settingsAction: controller.openAccessibilitySettings
        )

        stepCard(
          index: 3,
          title: "Input Monitoring",
          description: "Needed for global Right Command hold-to-talk capture.",
          done: controller.permissions.inputMonitoring,
          actionTitle: "Grant Input Monitoring",
          action: controller.requestInputMonitoringAccess,
          settingsAction: controller.openInputMonitoringSettings
        )

        stepCard(
          index: 4,
          title: "Install At Least One Model",
          description: "Models are local-only and stored under Application Support.",
          done: controller.settings.installedModels.contains(controller.settings.defaultModel),
          actionTitle: controller.downloadingModel == nil
            ? "Download \(controller.settings.defaultModel.displayName)"
            : "Downloading...",
          action: {
            controller.installModel(controller.settings.defaultModel)
          },
          settingsAction: nil,
          actionDisabled: controller.downloadingModel != nil
        )

        HStack {
          if controller.requiresOnboarding {
            Text("Setup incomplete")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.orange)
          } else {
            Text("Setup complete. Friday is ready.")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.green)
          }

          Spacer()
        }

        Text("Tip: Hold Right Command, speak, release to paste.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)

        Divider()

        modelPolicySection
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(.ultraThinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .stroke(Color.white.opacity(0.22), lineWidth: 1)
          )
      )
      .padding(20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var modelPolicySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Model Policy")
        .font(.system(size: 16, weight: .semibold))

      Text("Default model: \(controller.settings.defaultModel.displayName)")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)

      Text("Friday transcribes with the Medium model — accurate on everyday Chinese/English dictation and light on memory.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)

      ForEach([ModelTier.medium]) { tier in
        if let descriptor = controller.descriptor(for: tier) {
          modelCard(tier: tier, descriptor: descriptor)
        }
      }

      Text("After each dictation, Friday shows latency in ms (status + diagnostics). Lower is faster.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
  }

  private func modelCard(tier: ModelTier, descriptor: ModelDescriptor) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("\(descriptor.displayName) • \(descriptor.approxSizeMB)MB")
          .font(.system(size: 12, weight: .semibold))

        Text("Quality: \(descriptor.quality)")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      if controller.settings.defaultModel == tier {
        Text("Default")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.green)
      } else if controller.settings.installedModels.contains(tier) {
        Button("Use") {
          controller.setDefaultModel(tier)
        }
        .buttonStyle(.bordered)
        .disabled(controller.downloadingModel != nil)
      }

      if !controller.settings.installedModels.contains(tier) {
        Button(controller.downloadingModel == tier ? "Downloading..." : "Install") {
          controller.installModel(tier)
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.downloadingModel != nil)
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.07))
    )
  }

  private func stepCard(
    index: Int,
    title: String,
    description: String,
    done: Bool,
    actionTitle: String,
    action: @escaping () -> Void,
    settingsAction: (() -> Void)?,
    actionDisabled: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(index). \(title)")
          .font(.system(size: 14, weight: .semibold))

        Spacer()

        Label(done ? "Done" : "Pending", systemImage: done ? "checkmark.circle.fill" : "clock")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(done ? .green : .orange)
      }

      Text(description)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .disabled(done || actionDisabled)

        if let settingsAction {
          Button("Open System Settings", action: settingsAction)
            .buttonStyle(.bordered)
            .disabled(done)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(0.08))
    )
  }
}
