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
            .frame(minWidth: 700, minHeight: 450)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
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
    let title: String
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color.black.opacity(0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.82))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}


struct TestView: View {
    var body: some View {
//        NavigationSplitView {
//            List {
//                Label("Messages", systemImage: "blubble.left.fill" )
//            }
//            .listStyle(.sidebar)
//        } detail: {
//            Text("content")
//        }
        VStack {
            Text("Test")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .frame(minWidth: 700, minHeight: 450)
    }
}
