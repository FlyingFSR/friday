import SwiftUI

struct MenuContentView: View {
  @ObservedObject var controller: FridayController
  @State private var showingDiagnostics = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      Toggle("Start at Login", isOn: Binding(
        get: { controller.settings.autoStart },
        set: { controller.setAutoStart($0) }
      ))

      Divider()

      permissionSection
      modelSection
      diagnosticsSection

      Divider()

      Text(controller.statusMessage)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Button("Quit Friday") {
        NSApplication.shared.terminate(nil)
      }
      .buttonStyle(.borderless)
    }
    .padding(14)
    .frame(width: 360)
    .sheet(isPresented: $showingDiagnostics) {
      DiagnosticsView(lines: controller.diagnostics)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("Friday")
          .font(.system(size: 16, weight: .semibold))
        Text(AppInfo.versionLabel)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      Text("Hold Right Command to talk, release to paste.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
  }

  private var permissionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Permissions")
        .font(.system(size: 12, weight: .semibold))

      permissionRow(
        title: "Microphone",
        granted: controller.permissions.microphone,
        request: controller.requestMicrophoneAccess,
        openSettings: controller.openMicrophoneSettings
      )

      permissionRow(
        title: "Accessibility",
        granted: controller.permissions.accessibility,
        request: controller.requestAccessibilityAccess,
        openSettings: controller.openAccessibilitySettings
      )

      permissionRow(
        title: "Input Monitoring",
        granted: controller.permissions.inputMonitoring,
        request: controller.requestInputMonitoringAccess,
        openSettings: controller.openInputMonitoringSettings
      )
    }
  }

  private var modelSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Model")
        .font(.system(size: 12, weight: .semibold))

      ForEach([ModelTier.medium]) { tier in
        if let descriptor = controller.descriptor(for: tier) {
          modelRow(tier: tier, descriptor: descriptor)
        }
      }
    }
  }

  private func modelRow(tier: ModelTier, descriptor: ModelDescriptor) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(descriptor.displayName) • \(descriptor.approxSizeMB)MB")
          .font(.system(size: 11, weight: .medium))
        Text(descriptor.quality)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      if controller.settings.defaultModel == tier {
        Text("Default")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.green)
      } else if controller.settings.installedModels.contains(tier) {
        Button("Use") {
          controller.setDefaultModel(tier)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(controller.downloadingModel != nil)
      }

      if !controller.settings.installedModels.contains(tier) {
        Button(controller.downloadingModel == tier ? "Downloading..." : "Install") {
          controller.installModel(tier)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(controller.downloadingModel != nil)
      }
    }
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Diagnostics")
        .font(.system(size: 12, weight: .semibold))

      Button("Open Setup Assistant") {
        controller.openSetupAssistant()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Button("Open Diagnostics") {
        showingDiagnostics = true
      }
      .buttonStyle(.borderless)

      if controller.requiresOnboarding {
        Text("Setup incomplete: grant permissions and install default model.")
          .font(.system(size: 10))
          .foregroundStyle(.orange)
      }
    }
  }

  private func permissionRow(
    title: String,
    granted: Bool,
    request: @escaping () -> Void,
    openSettings: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(title)
        .font(.system(size: 11))
      Spacer()
      Text(granted ? "Granted" : "Missing")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(granted ? .green : .orange)

      if granted {
        EmptyView()
      } else {
        Button("Request") { request() }
          .buttonStyle(.bordered)
          .controlSize(.small)

        Button("Open Settings") { openSettings() }
          .buttonStyle(.borderless)
      }
    }
  }
}

private struct DiagnosticsView: View {
  let lines: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Friday Diagnostics")
        .font(.system(size: 14, weight: .semibold))

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(lines, id: \.self) { line in
            Text(line)
              .font(.system(size: 11, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(14)
    .frame(width: 620, height: 420)
  }
}
