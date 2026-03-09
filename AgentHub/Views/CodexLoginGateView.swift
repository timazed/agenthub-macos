import SwiftUI

struct CodexLoginGateView: View {
    private enum LayoutMode {
        case wide
        case collapsed
    }

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: AuthViewModel
    let onStartLogin: () -> Void
    let onRetryStatus: () -> Void
    let onCancelLogin: () -> Void
    let onUseDefaultPersonality: () -> Void
    let onSavePersonality: (String) -> Void
    let onSaveAgentName: (String) -> Void

    @State private var personalityDraft = ""
    @State private var agentNameDraft = ""
    private let widePanelHeight: CGFloat = 540
    private let wideLayoutWidthThreshold: CGFloat = 980
    private let wideLayoutHeightThreshold: CGFloat = 700

    private var palette: OnboardingPalette {
        OnboardingPalette.resolve(for: colorScheme)
    }

    var body: some View {
        OnboardingShell {
            GeometryReader { geometry in
                let layoutMode = layoutMode(for: geometry.size)

                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch layoutMode {
                        case .wide:
                            wideLayout
                        case .collapsed:
                            compactLayout
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: geometry.size.height - 48, alignment: .top)
                }
            }
        }
        .onAppear {
            seedDraftsIfNeeded()
        }
        .onChange(of: viewModel.currentStep) { _, _ in
            seedDraftsIfNeeded()
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 26) {
            narrativeRail(maxWidth: 340)
                .frame(width: 340)
                .frame(height: widePanelHeight, alignment: .top)
            stepSurface(maxWidth: 720)
                .frame(maxWidth: 720)
                .frame(height: widePanelHeight, alignment: .top)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 22) {
            narrativeRail(maxWidth: .infinity)
            stepSurface(maxWidth: .infinity)
        }
    }

    private func layoutMode(for size: CGSize) -> LayoutMode {
        if size.width >= wideLayoutWidthThreshold && size.height >= wideLayoutHeightThreshold {
            return .wide
        }
        return .collapsed
    }

    private func narrativeRail(maxWidth: CGFloat) -> some View {
        OnboardingSecondaryPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("AgentHub")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(2.4)
                    .foregroundStyle(palette.subdued)

                if let presentation = viewModel.onboardingPresentation {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(presentation.eyebrow)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.accent)

                        Text(presentation.title)
                            .font(.system(size: 31, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.title)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(presentation.message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    progressDots(
                        current: presentation.currentStepNumber,
                        total: presentation.totalSteps
                    )
                } else {
                    Text(viewModel.statusTitle)
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.title)

                    Text(viewModel.statusMessage)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    railPoint(
                        title: "Continuous entry",
                        message: "The setup visuals are designed to carry straight into the assistant home instead of feeling like a disconnected modal."
                    )
                    railPoint(
                        title: "System appearance",
                        message: "Colors adapt to macOS light and dark mode automatically with no separate appearance setting."
                    )
                    railPoint(
                        title: "Default assistant first",
                        message: "The assistant you configure here becomes the one that appears in chat and scheduled work."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func stepSurface(maxWidth: CGFloat) -> some View {
        Group {
            switch viewModel.currentStep {
            case .persona:
                personaStep
            case .name:
                nameStep
            default:
                authStep
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var authStep: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect your Codex account")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.title)

                        Text("Authenticate once and AgentHub can hand you off into the main assistant surface with chat, tasks, and activity ready.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    authStatusBadge
                }

                OnboardingSecondaryPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        featureLine("Chat stays attached to a named default assistant.")
                        featureLine("Background tasks inherit the same assistant context.")
                        featureLine("You only need to do this setup flow once.")
                    }
                }

                if let challenge = viewModel.currentChallenge {
                    challengeCard(challenge)
                } else if viewModel.showsBrowserWaitingCard {
                    browserWaitingCard
                } else {
                    OnboardingSecondaryPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What happens next")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.title)

                            Text("We’ll open the Codex sign-in flow in your browser. Once authentication is confirmed, onboarding continues directly into assistant setup.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(palette.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onStartLogin) {
                        Text(viewModel.primaryButtonTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var personaStep: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default assistant instructions")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.title)

                    Text("These instructions become the baseline personality for the assistant you’ll enter the app with.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        personaEditor
                        personaAside
                            .frame(width: 208)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        personaEditor
                        compactPersonaSummary
                    }
                }

                HStack(spacing: 12) {
                    Button("Use default", action: onUseDefaultPersonality)
                        .buttonStyle(.bordered)

                    Button("Continue") {
                        onSavePersonality(personalityDraft)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var nameStep: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 18) {
                    assistantIdentityBadge

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name your assistant")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.title)

                        Text("This is the name that appears when onboarding hands off into the main assistant home.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                OnboardingSecondaryPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display name")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.subdued)

                        TextField("Default", text: $agentNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.title)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(palette.fieldFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(palette.fieldStroke, lineWidth: 1)
                                    )
                            )

                        Text("Used in the chat header and assistant-facing task context.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.body)
                    }
                }

                HStack(spacing: 12) {
                    Label("Next stop: assistant home", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.body)

                    Spacer(minLength: 0)

                    Button("Continue") {
                        onSaveAgentName(agentNameDraft)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(agentNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var personaEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instructions")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.subdued)

            TextEditor(text: $personalityDraft)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(palette.title)
                .frame(minHeight: 160, idealHeight: 176, maxHeight: 190)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(palette.fieldStroke, lineWidth: 1)
                        )
                )
        }
    }

    private var personaAside: some View {
        OnboardingSecondaryPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where it shows up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.title)

                featureLine("The first assistant chat after setup.")
                featureLine("Any default scheduled task instructions.")
                featureLine("The identity that carries into the home flow.")
            }
        }
    }

    private var compactPersonaSummary: some View {
        OnboardingSecondaryPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Used for chat, scheduled work, and the assistant identity you enter home with.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    summaryChip("Chat")
                    summaryChip("Tasks")
                    summaryChip("Home")
                }
            }
        }
    }

    private var assistantIdentityBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.accent, palette.glowB.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 74, height: 74)

            Text(String(agentNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
        }
    }

    private var authStatusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isAuthenticated ? Color.green : palette.accent)
                .frame(width: 10, height: 10)

            Text(viewModel.isAuthenticated ? "Connected" : "Not connected")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(palette.accentSoft)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(palette.fieldStroke, lineWidth: 1)
                )
        )
    }

    private func challengeCard(_ challenge: AuthLoginChallenge) -> some View {
        OnboardingSecondaryPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Browser sign-in")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.title)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Verification URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.subdued)
                    Text(challenge.verificationURL.absoluteString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(palette.title)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("One-time code")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.subdued)
                    Text(challenge.userCode)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.title)
                        .textSelection(.enabled)
                }

                if let minutes = challenge.expiresInMinutes {
                    Text("Expires in \(minutes) minutes")
                        .font(.caption)
                        .foregroundStyle(palette.body)
                }
            }
        }
    }

    private var browserWaitingCard: some View {
        OnboardingSecondaryPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Finish sign-in in your browser")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.title)

                Text("Complete the Codex sign-in page in your browser. AgentHub will continue automatically as soon as the login state flips to authenticated.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressDots(current: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == current ? palette.accent : palette.fieldStroke)
                    .frame(width: index == current ? 28 : 10, height: 8)
            }
        }
    }

    private func featureLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(palette.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(palette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func railPoint(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.title)

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(palette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.title)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.accentSoft)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(palette.fieldStroke, lineWidth: 1)
                    )
            )
    }

    private func seedDraftsIfNeeded() {
        switch viewModel.currentStep {
        case .persona:
            if personalityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                personalityDraft = viewModel.defaultPersonalityText
            }
        case .name:
            if agentNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentNameDraft = viewModel.defaultAgentName
            }
        default:
            break
        }
    }
}
