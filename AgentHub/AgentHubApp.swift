import SwiftUI
import Combine

struct AgentHubApp: App {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = bootstrap.container {
                    AppShellView(container: container)
                } else if let errorMessage = bootstrap.errorMessage {
                    LaunchStateView(
                        title: "Failed to Launch AgentHub",
                        message: errorMessage
                    )
                } else {
                    LaunchStateView(
                        title: "Opening AgentHub",
                        message: "Preparing runtime and local state…"
                    )
                    .task {
                        await bootstrap.loadIfNeeded()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Spacer()
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .frame(minWidth: 800, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 800, height: 800)
    }
}

@MainActor
private final class AppBootstrap: ObservableObject {
    @Published var container: AppContainer?
    @Published var errorMessage: String?

    private var didStart = false

    func loadIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        let startedAt = Date()
        Self.log("bootstrap_start")

        do {
            let container = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try AppContainer.makeDefault())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.container = container
            self.errorMessage = nil
            Self.log("bootstrap_success duration_ms=\(Self.durationMillis(since: startedAt))")
        } catch {
            self.errorMessage = error.localizedDescription
            Self.log("bootstrap_failed duration_ms=\(Self.durationMillis(since: startedAt)) error=\(error.localizedDescription)")
        }
    }

    private static func durationMillis(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    private static func log(_ message: String) {
        let line = "[AgentHub][Startup] \(message)"
        print(line)

        let fileManager = FileManager.default
        let logsDirectory = AppPaths.defaultRoot().appendingPathComponent("logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("startup.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(timestamp)] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}

private struct LaunchStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        OnboardingShell(maxWidth: 760) {
            OnboardingPanel(padding: 30) {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.title)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(palette.body)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 700)
    }
}
