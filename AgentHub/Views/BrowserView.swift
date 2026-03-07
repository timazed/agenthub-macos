import SwiftUI

struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var automationService: BrowserAutomationService
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let confirmation = automationService.pendingConfirmation,
               confirmation.sessionId == viewModel.sessionID {
                confirmationBanner(confirmation)
            } else {
                statusBanner
            }
            Divider()
            WKWebViewContainer(viewModel: viewModel, automationService: automationService)
        }
        .frame(minWidth: 420, minHeight: 620)
        .background(Color.black.opacity(0.04))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                toolbarButton(systemName: "chevron.backward", action: { viewModel.goBack() })
                    .disabled(!viewModel.canGoBack)
                toolbarButton(systemName: "chevron.forward", action: { viewModel.goForward() })
                    .disabled(!viewModel.canGoForward)
                toolbarButton(systemName: "arrow.clockwise", action: { viewModel.reload() })
                    .disabled(viewModel.currentURL == nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.pageTitle.isEmpty ? "Browser" : viewModel.pageTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.currentURL?.absoluteString ?? "No page selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text("\(viewModel.profile.displayName) · \(modeLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let sessionID = viewModel.sessionID {
                Button(viewModel.sessionMode == .manual ? "Resume Agent" : "Take Over") {
                    let nextMode: BrowserSessionMode = viewModel.sessionMode == .manual ? .agentControlling : .manual
                    automationService.setMode(nextMode, sessionID: sessionID)
                    viewModel.updateSessionMode(nextMode)
                }
                .buttonStyle(.bordered)
            }

            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(statusColor.opacity(0.12))
    }

    private func confirmationBanner(_ confirmation: BrowserConfirmationRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Confirmation Required")
                    .font(.subheadline.weight(.semibold))
                Text(confirmation.target.map { "\(confirmation.actionType.rawValue) \($0)" } ?? confirmation.actionType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reject") {
                resolve(.rejected)
            }
            .buttonStyle(.bordered)
            Button("Take Over") {
                resolve(.takeOver)
            }
            .buttonStyle(.bordered)
            Button("Approve") {
                resolve(.approved)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.14))
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
    }

    private var modeLabel: String {
        switch viewModel.sessionMode {
        case .manual:
            return "Manual"
        case .agentControlling:
            return "Agent controlling"
        case .awaitingConfirmation:
            return "Awaiting confirmation"
        }
    }

    private var statusText: String {
        switch viewModel.sessionMode {
        case .manual:
            return "Manual control is active. The agent will not act until resumed."
        case .agentControlling:
            return "Agent control is active in this browser session."
        case .awaitingConfirmation:
            return "The agent is paused and waiting for your confirmation."
        }
    }

    private var statusIcon: String {
        switch viewModel.sessionMode {
        case .manual:
            return "hand.raised.fill"
        case .agentControlling:
            return "bolt.horizontal.circle.fill"
        case .awaitingConfirmation:
            return "pause.circle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.sessionMode {
        case .manual:
            return .blue
        case .agentControlling:
            return .green
        case .awaitingConfirmation:
            return .orange
        }
    }

    private func resolve(_ resolution: BrowserConfirmationResolution) {
        guard let sessionID = viewModel.sessionID else { return }
        do {
            try automationService.resolveConfirmation(sessionID: sessionID, resolution: resolution)
            switch resolution {
            case .approved:
                viewModel.updateSessionMode(.agentControlling)
            case .rejected, .takeOver:
                viewModel.updateSessionMode(.manual)
            case .pending:
                viewModel.updateSessionMode(.awaitingConfirmation)
            }
        } catch {
            return
        }
    }
}
