import SwiftUI
import AppKit

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var windowController: SettingsWindowController?

    func show(container: AppContainer) {
        if let windowController {
            present(windowController.window)
            return
        }

        let controller = SettingsWindowController(container: container) { [weak self] in
            self?.windowController = nil
        }
        windowController = controller
        present(controller.window)
    }

    private func present(_ window: NSWindow?) {
        AppPresentationController.shared.presentWindow(window)
        AppPresentationController.shared.presentWindow(identifier: AppWindowRegistry.settingsWindowIdentifier)
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController: SettingsSplitViewController
    private let onClose: () -> Void

    init(container: AppContainer, onClose: @escaping () -> Void) {
        splitViewController = SettingsSplitViewController(container: container)
        self.onClose = onClose

        let window = NSWindow(contentViewController: splitViewController)
        super.init(window: window)

        configure(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(window: NSWindow) {
        window.delegate = self
        window.setFrame(NSRect(x: 0, y: 0, width: 880, height: 680), display: false)
        window.center()
        window.minSize = NSSize(width: 760, height: 620)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.closable)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("agenthub-settings-toolbar"))
        toolbar.delegate = splitViewController
        toolbar.displayMode = .default
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar

        AppPresentationController.shared.registerWindow(
            window,
            identifier: AppWindowRegistry.settingsWindowIdentifier
        )
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class SettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private let viewModel: IMessageIntegrationViewModel
    private let sidebarViewController: SettingsSidebarViewController
    private let detailHostingController: NSHostingController<CommunicationChannelsSettingsView>
    private let sidebarItem: NSSplitViewItem

    init(container: AppContainer) {
        viewModel = IMessageIntegrationViewModel(
            configStore: container.iMessageIntegrationConfigStore,
            whitelistService: container.iMessageWhitelistService,
            monitorService: container.iMessageMonitorService,
            permissionService: IMessagePermissionService()
        )
        sidebarViewController = SettingsSidebarViewController()
        detailHostingController = NSHostingController(
            rootView: CommunicationChannelsSettingsView(viewModel: viewModel)
        )
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)

        super.init(nibName: nil, bundle: nil)

        sidebarViewController.onSelectionChange = { [weak self] destination in
            self?.applySelection(destination)
        }

        sidebarItem.minimumThickness = 260
        sidebarItem.maximumThickness = 360
        sidebarItem.automaticMaximumThickness = 360
        sidebarItem.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        detailItem.automaticallyAdjustsSafeAreaInsets = true
        detailItem.titlebarSeparatorStyle = .none

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        minimumThicknessForInlineSidebars = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.autosaveName = "agenthub-settings-split"
        splitView.dividerStyle = .paneSplitter
        splitView.isVertical = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        detailHostingController.view.wantsLayer = true
        detailHostingController.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        sidebarViewController.select(.communicationChannels)
        viewModel.load()
    }

    private func applySelection(_ destination: SettingsDestination) {
        switch destination {
        case .communicationChannels:
            detailHostingController.rootView = CommunicationChannelsSettingsView(viewModel: viewModel)
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.image = NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "Toggle Sidebar"
            )
            item.target = self
            item.action = #selector(toggleSidebar(_:))
            return item
        case .sidebarTrackingSeparator:
            let item = NSTrackingSeparatorToolbarItem(itemIdentifier: itemIdentifier)
            item.splitView = splitView
            item.dividerIndex = 0
            return item
        default:
            return nil
        }
    }
}

@MainActor
private final class SettingsSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private enum Item: Hashable {
        case section
        case destination(SettingsDestination)
    }

    var onSelectionChange: ((SettingsDestination) -> Void)?

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings-sidebar"))
    private let sectionItem = Item.section

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView

        outlineView.translatesAutoresizingMaskIntoConstraints = false
        outlineView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        outlineView.autoresizingMask = [.width, .height]
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 0
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.floatsGroupRows = false
        outlineView.focusRingType = .none
        outlineView.delegate = self
        outlineView.dataSource = self

        tableColumn.resizingMask = .autoresizingMask
        tableColumn.isEditable = false
        outlineView.addTableColumn(tableColumn)
        outlineView.outlineTableColumn = tableColumn

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = outlineView

        rootView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outlineView.reloadData()
        outlineView.expandItem(sectionItem)
    }

    func select(_ destination: SettingsDestination) {
        for row in 0..<outlineView.numberOfRows {
            guard
                let item = outlineView.item(atRow: row) as? Item,
                case .destination(let candidate) = item,
                candidate == destination
            else {
                continue
            }

            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            onSelectionChange?(destination)
            return
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item as? Item {
        case nil:
            return 1
        case .section:
            return SettingsDestination.allCases.count
        case .destination:
            return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item as? Item {
        case nil:
            return sectionItem
        case .section:
            return Item.destination(SettingsDestination.allCases[index])
        case .destination:
            preconditionFailure("Unexpected child request for leaf item")
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if case .section = item as? Item {
            return true
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if case .section = item as? Item {
            return true
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if case .destination = item as? Item {
            return true
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch item as? Item {
        case .section:
            return 30
        case .destination:
            return 52
        case .none:
            return 44
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let item = item as? Item else { return nil }

        switch item {
        case .section:
            return SettingsSidebarSectionCellView()
        case .destination(let destination):
            let cellView = SettingsSidebarDestinationCellView()
            cellView.configure(with: destination)
            return cellView
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard outlineView.selectedRow >= 0 else { return }
        guard
            let item = outlineView.item(atRow: outlineView.selectedRow) as? Item,
            case .destination(let destination) = item
        else {
            return
        }

        onSelectionChange?(destination)
    }
}

private final class SettingsSidebarSectionCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "Integrations")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SettingsSidebarDestinationCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.contentTintColor = .labelColor

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        addSubview(iconView)
        addSubview(textStack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with destination: SettingsDestination) {
        iconView.image = NSImage(
            systemSymbolName: destination.systemImage,
            accessibilityDescription: destination.title
        )
        titleField.stringValue = destination.title
        subtitleField.stringValue = destination.subtitle
    }
}

private enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case communicationChannels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .communicationChannels:
            return "Communication Channels"
        }
    }

    var subtitle: String {
        switch self {
        case .communicationChannels:
            return "iMessage and future channels"
        }
    }

    var systemImage: String {
        switch self {
        case .communicationChannels:
            return "message.badge.waveform.fill"
        }
    }
}

private struct CommunicationChannelsSettingsView: View {
    @ObservedObject var viewModel: IMessageIntegrationViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                IMessageSettingsSection(viewModel: viewModel)
                    .frame(maxWidth: 860)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Primary Channel", systemImage: "message.badge.waveform.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Communication Channels")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Configure inbound channels, review permissions, and decide which senders can trigger an agent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct IMessageSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: IMessageIntegrationViewModel

    private var rowBackground: Color {
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.55)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable iMessage", isOn: Binding(
                    get: { viewModel.config.isEnabled },
                    set: { viewModel.setEnabled($0) }
                ))
                .toggleStyle(.switch)

                Text("Only whitelisted senders can trigger an agent. Mention an agent with `@Name` to execute a query.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                permissionsSection

                Divider()
                    .overlay(Color.white.opacity(0.08))

                senderSection
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "message.badge.waveform.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("iMessage")
                    .font(.headline)
                Text("Live integration, sender filtering, and permission checks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(viewModel.config.isEnabled ? "Enabled" : "Disabled")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(viewModel.config.isEnabled ? Color.green : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(viewModel.config.isEnabled ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
            )
    }

    private var senderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allowed Senders")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                TextField("Phone number or handle", text: $viewModel.draftHandle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(rowBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                Button("Add", action: viewModel.addHandle)
                    .buttonStyle(.borderedProminent)
            }

            if viewModel.config.allowedHandles.isEmpty {
                Text("No sender whitelist entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.config.allowedHandles, id: \.self) { handle in
                        removableWhitelistRow(handle, removeAction: { viewModel.removeHandle(handle) })
                    }
                }
            }
        }
    }

    private func removableWhitelistRow(_ text: String, removeAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button("Remove", action: removeAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowContainer)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.subheadline.weight(.semibold))

            permissionRow(
                title: "Full Disk Access",
                state: viewModel.permissionStatus.fullDiskAccess,
                actionTitle: "Open Settings",
                action: viewModel.openFullDiskAccessSettings
            )

            permissionRow(
                title: "Messages Automation",
                state: viewModel.permissionStatus.automation,
                actionTitle: "Open Settings",
                action: viewModel.openAutomationSettings
            )

            HStack(spacing: 8) {
                Button("Refresh", action: viewModel.refreshPermissions)
                    .buttonStyle(.bordered)

                Button("Reveal AgentHub", action: viewModel.revealAppInFinder)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)

            Text(viewModel.permissionStatus.appPath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 2)
        }
    }

    private func permissionRow(
        title: String,
        state: IMessagePermissionStatus.State,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(permissionColor(for: state))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(permissionLabel(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if state != .granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowContainer)
    }

    private var rowContainer: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.45), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                radius: 24,
                x: 0,
                y: 18
            )
    }

    private func permissionLabel(for state: IMessagePermissionStatus.State) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .missing:
            return "Missing"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func permissionColor(for state: IMessagePermissionStatus.State) -> Color {
        switch state {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .unavailable:
            return .secondary
        }
    }
}
