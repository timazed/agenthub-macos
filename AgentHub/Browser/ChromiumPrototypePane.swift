import SwiftUI

struct ChromiumPrototypePane: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isAddressBarFocused: Bool

    @ObservedObject var controller: ChromiumBrowserController

    var body: some View {
        VStack(spacing: 12) {
            header
            browserSurface
            controlsSurface
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Embedded Chromium")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.95))

                    Text("Prototype pane proving embedded browser control, page inspection, and search-driven flows.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.9))
                }

                Spacer(minLength: 0)

                statusBadge
            }

            HStack(spacing: 8) {
                navigationButton(systemName: "chevron.left", isEnabled: controller.state.canGoBack) {
                    controller.goBack()
                }
                navigationButton(systemName: "chevron.right", isEnabled: controller.state.canGoForward) {
                    controller.goForward()
                }
                navigationButton(systemName: controller.state.isLoading ? "xmark" : "arrow.clockwise", isEnabled: true) {
                    if controller.state.isLoading {
                        controller.stop()
                    } else {
                        controller.reload()
                    }
                }

                TextField("https://www.opentable.com", text: $controller.addressBarText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(fieldBackground)
                    .focused($isAddressBarFocused)
                    .onChange(of: isAddressBarFocused) { _, isFocused in
                        controller.setAddressBarEditing(isFocused)
                    }
                    .onSubmit {
                        controller.openCurrentAddress()
                    }

                Button("Open") {
                    controller.openCurrentAddress()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(panelBackground(cornerRadius: 22))
    }

    private var browserSurface: some View {
        ZStack(alignment: .bottomLeading) {
            ChromiumBrowserRepresentable(controller: controller)
                .id(controller.browserViewIdentity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(controller.state.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.94))

                Text(controller.state.urlString)
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(12)
            .background(panelBackground(cornerRadius: 16))
            .padding(12)
        }
        .frame(minHeight: 340)
    }

    private var controlsSurface: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                quickActionsSection
                approvalSection
                selectorSection
                inspectionSection
                traceSection
                snapshotsSection
                logSection
            }
        }
        .padding(14)
        .background(panelBackground(cornerRadius: 22))
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search Flow Playground")
                .font(.subheadline.weight(.semibold))

            TextField("Visible search query", text: $controller.quickSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)

            HStack(spacing: 8) {
                Button("Run Restaurant Flow") {
                    controller.runRestaurantSearchFlow()
                }
                .buttonStyle(.borderedProminent)

                Button("Fill Search") {
                    controller.fillVisibleSearchField()
                }
                .buttonStyle(.bordered)

                Button("Submit Search") {
                    controller.submitVisibleSearch()
                }
                .buttonStyle(.bordered)
            }

            TextField("Click visible text match", text: $controller.textMatch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)

            Button("Click Matching Result") {
                controller.clickMatchingText()
            }
            .buttonStyle(.bordered)

            Text(flowStatusLabel)
                .font(.caption)
                .foregroundStyle(flowStatusColor.opacity(0.95))
        }
    }

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selector Console")
                .font(.subheadline.weight(.semibold))

            TextField("CSS selector", text: $controller.selectorText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)

            TextField("Text for selector typing", text: $controller.selectorInputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)

            HStack(spacing: 8) {
                Button("Capture Snapshot") {
                    controller.captureSnapshot()
                }
                .buttonStyle(.bordered)

                Button("Type Text") {
                    controller.typeIntoSelector()
                }
                .buttonStyle(.bordered)

                Button("Click Selector") {
                    controller.clickSelector()
                }
                .buttonStyle(.bordered)

                Button("Inspect Page") {
                    controller.inspectPage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var approvalSection: some View {
        switch controller.approvalStatus {
        case .idle:
            EmptyView()
        case let .pending(pending):
            VStack(alignment: .leading, spacing: 10) {
                Text("Approval Required")
                    .font(.subheadline.weight(.semibold))

                Text(pending.detail)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.92))

                Text(pending.rationale)
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.86))

                HStack(spacing: 8) {
                    Button("Approve") {
                        controller.approvePendingAction()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reject") {
                        controller.rejectPendingAction()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var inspectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspection")
                .font(.subheadline.weight(.semibold))

            if let inspection = controller.lastInspection {
                Text("\(inspection.title) • \(inspection.formCount) forms • \(inspection.hasSearchField ? "search field detected" : "no search field detected")")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.92))

                ForEach(inspection.interactiveElements.prefix(8)) { element in
                    HStack(alignment: .top, spacing: 8) {
                        Text(element.role)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.secondary.opacity(0.85))
                            .frame(width: 82, alignment: .leading)

                        Text(element.label.isEmpty ? element.text : element.label)
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("Run `Inspect Page` to capture the current DOM summary and visible interactive controls.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.9))
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prototype Log")
                .font(.subheadline.weight(.semibold))

            ForEach(controller.logs.prefix(8)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.75))

                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.92))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(fieldBackground)
            }
        }
    }

    private var traceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action Trace")
                .font(.subheadline.weight(.semibold))

            if controller.actionTrace.isEmpty {
                Text("Run the restaurant flow to capture browser steps, retries, and outcomes.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.9))
            } else {
                ForEach(controller.actionTrace.prefix(10)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(traceColor(for: entry.status))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.name) · attempt \(entry.attempt)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary.opacity(0.92))

                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(Color.secondary.opacity(0.9))

                            Text(entry.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.secondary.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(fieldBackground)
                }
            }
        }
    }

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snapshots")
                .font(.subheadline.weight(.semibold))

            if controller.snapshots.isEmpty {
                Text("Snapshots are captured on important browser actions and can also be captured manually.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.9))
            } else {
                ForEach(controller.snapshots.prefix(4)) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.92))

                        Text(snapshot.filePath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.secondary.opacity(0.78))
                            .textSelection(.enabled)

                        Text(snapshot.url)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(fieldBackground)
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.state.runtimeReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(controller.state.runtimeReady ? "Ready" : "Initializing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fieldBackground)
    }

    private func navigationButton(systemName: String,
                                  isEnabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.45))
        .background(fieldBackground)
        .clipShape(Circle())
        .disabled(!isEnabled)
    }

    private func panelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .liquidGlass(cornerRadius: cornerRadius)
    }

    private var fieldBackground: some ShapeStyle {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.04, green: 0.06, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var flowStatusLabel: String {
        switch controller.flowStatus {
        case .idle:
            return "Flow idle"
        case let .running(message):
            return "Running: \(message)"
        case let .succeeded(message):
            return "Succeeded: \(message)"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }

    private var flowStatusColor: Color {
        switch controller.flowStatus {
        case .idle:
            return .secondary
        case .running:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private func traceColor(for status: ChromiumActionStatus) -> Color {
        switch status {
        case .running:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .yellow
        }
    }
}
