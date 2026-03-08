import SwiftUI

struct CodexLoginGateView: View {
    @ObservedObject var viewModel: AuthViewModel
    let onStartLogin: () -> Void
    let onRetryStatus: () -> Void
    let onCancelLogin: () -> Void
    let onUseDefaultPersonality: () -> Void
    let onSavePersonality: (String) -> Void
    @State private var personalityDraft = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    Color.black.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("AgentHub")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.55))

                    Text(viewModel.statusTitle)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(viewModel.statusMessage)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                if let challenge = viewModel.currentChallenge {
                    challengeCard(challenge)
                }

                if viewModel.showsBrowserWaitingCard {
                    browserWaitingCard
                }

                if viewModel.currentStep == .persona {
                    personaStepCard
                } else {
                    authActions
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }
            .padding(40)
            .frame(maxWidth: 680)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(24)
        }
        .onAppear {
            seedPersonalityDraftIfNeeded()
        }
        .onChange(of: viewModel.currentStep) { _, _ in
            seedPersonalityDraftIfNeeded()
        }
    }

    private var authActions: some View {
        VStack(spacing: 12) {
            Button(action: onStartLogin) {
                Text(viewModel.primaryButtonTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isBusy)

            HStack(spacing: 12) {
                Button("Check again", action: onRetryStatus)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy)

                if viewModel.isAwaitingBrowserCompletion {
                    Button("Cancel", action: onCancelLogin)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 360)
    }

    private func challengeCard(_ challenge: AuthLoginChallenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browser sign-in")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 6) {
                Text("Verification URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(challenge.verificationURL.absoluteString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("One-time code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(challenge.userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

            if let minutes = challenge.expiresInMinutes {
                Text("Expires in \(minutes) minutes")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
        }
        .padding(20)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var browserWaitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Complete sign-in in your browser")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Codex opened a browser-based sign-in flow. Finish the login in the browser window, then return here once the page confirms you are signed in.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var personaStepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Default personality")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))

            TextEditor(text: $personalityDraft)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .frame(minHeight: 180)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

            Text("This text defines the starting personality for the default assistant. You can keep it as-is or customize it now.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))

            HStack(spacing: 12) {
                Button("Use default", action: onUseDefaultPersonality)
                    .buttonStyle(.bordered)

                Button("Continue") {
                    onSavePersonality(personalityDraft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func seedPersonalityDraftIfNeeded() {
        guard viewModel.currentStep == .persona else { return }
        if personalityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            personalityDraft = viewModel.defaultPersonalityText
        }
    }
}
