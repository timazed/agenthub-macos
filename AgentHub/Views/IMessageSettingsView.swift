import SwiftUI
import AppKit
import Combine

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
    private let themeViewModel: ThemeSettingsViewModel
    private let sidebarViewController: SettingsSidebarViewController
    private let detailHostingController: NSHostingController<AnyView>
    private let sidebarItem: NSSplitViewItem

    init(container: AppContainer) {
        viewModel = IMessageIntegrationViewModel(
            configStore: container.iMessageIntegrationConfigStore,
            whitelistService: container.iMessageWhitelistService,
            monitorService: container.iMessageMonitorService,
            permissionService: IMessagePermissionService()
        )
        themeViewModel = ThemeSettingsViewModel(runtimeConfigStore: container.runtimeConfigStore)
        sidebarViewController = SettingsSidebarViewController()
        detailHostingController = NSHostingController(rootView: AnyView(EmptyView()))
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
        themeViewModel.load()
        applySelection(.communicationChannels)
    }

    private func applySelection(_ destination: SettingsDestination) {
        switch destination {
        case .communicationChannels:
            detailHostingController.rootView = AnyView(CommunicationChannelsSettingsView(viewModel: viewModel))
        case .themes:
            detailHostingController.rootView = AnyView(ThemeSettingsView(viewModel: themeViewModel))
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
    private let label = NSTextField(labelWithString: "Settings")

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
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .communicationChannels:
            return "Communication Channels"
        case .themes:
            return "Themes"
        }
    }

    var subtitle: String {
        switch self {
        case .communicationChannels:
            return "iMessage and future channels"
        case .themes:
            return "Chat appearance and live previews"
        }
    }

    var systemImage: String {
        switch self {
        case .communicationChannels:
            return "message.badge.waveform.fill"
        case .themes:
            return "swatchpalette.fill"
        }
    }
}

@MainActor
private final class ThemeSettingsViewModel: ObservableObject {
    @Published private(set) var selectedTheme: AppTheme = .default
    @Published var errorMessage: String?

    private let runtimeConfigStore: AppRuntimeConfigStore
    private var observer: NSObjectProtocol?

    init(runtimeConfigStore: AppRuntimeConfigStore) {
        self.runtimeConfigStore = runtimeConfigStore
        observer = NotificationCenter.default.addObserver(
            forName: .runtimeConfigDidChange,
            object: runtimeConfigStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.load()
            }
        }
    }

    func load() {
        do {
            selectedTheme = try runtimeConfigStore.loadOrCreateDefault().theme
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ theme: AppTheme) {
        guard theme != selectedTheme else { return }

        do {
            var config = try runtimeConfigStore.loadOrCreateDefault()
            config.theme = theme
            config.updatedAt = Date()
            try runtimeConfigStore.save(config)
            selectedTheme = theme
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
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

private struct ThemeSettingsView: View {
    @ObservedObject var viewModel: ThemeSettingsViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        ThemeOptionCard(
                            theme: theme,
                            isSelected: viewModel.selectedTheme == theme,
                            onSelect: { viewModel.select(theme) }
                        )
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
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
                Label("Appearance", systemImage: "swatchpalette.fill")
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
                Text("Themes")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Choose the standard app appearance or switch chat to the animated Bubble Gum theme.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ThemeOptionCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                ThemePreviewCard(theme: theme)
                    .frame(height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.10), lineWidth: isSelected ? 2 : 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(theme.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(theme.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreviewCard: View {
    let theme: AppTheme

    var body: some View {
        ZStack {
            switch theme {
            case .default:
                DefaultThemePreview()
            case .bubbleGum:
                BubbleGumThemePreview()
            }
        }
    }
}

private struct DefaultThemePreview: View {
    @State private var sweepOffset: CGFloat = -1.1

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                MiniPreviewBubble(width: 120, alignment: .leading, fill: Color.white.opacity(0.58), textColor: Color.black.opacity(0.75))
                MiniPreviewBubble(width: 94, alignment: .trailing, fill: Color.blue.opacity(0.88), textColor: .white)
                MiniPreviewBubble(width: 144, alignment: .leading, fill: Color.white.opacity(0.48), textColor: Color.black.opacity(0.70))
            }
            .padding(16)

            GeometryReader { geometry in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.20), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geometry.size.width * 0.55)
                .rotationEffect(.degrees(14))
                .offset(x: sweepOffset * geometry.size.width)
            }
            .blendMode(.screen)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                sweepOffset = 1.2
            }
        }
    }
}

private struct BubbleGumThemePreview: View {
    var body: some View {
        ZStack {
            ChatMeshBackgroundView()

            VStack(spacing: 12) {
                MiniPreviewBubble(
                    width: 126,
                    alignment: .leading,
                    fill: Color(red: 0.33, green: 0.49, blue: 0.68).opacity(0.64),
                    textColor: .white.opacity(0.96)
                )
                MiniPreviewBubble(
                    width: 98,
                    alignment: .trailing,
                    fill: LinearGradient(
                        colors: [Color.blue.opacity(0.96), Color.cyan.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    textColor: .white
                )
                MiniPreviewBubble(
                    width: 152,
                    alignment: .leading,
                    fill: Color(red: 0.33, green: 0.49, blue: 0.68).opacity(0.54),
                    textColor: .white.opacity(0.96)
                )
            }
            .padding(16)
        }
    }
}

private struct MiniPreviewBubble<Fill: ShapeStyle>: View {
    let width: CGFloat
    let alignment: HorizontalAlignment
    let fill: Fill
    let textColor: Color

    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 18)
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(fill)
                .frame(width: width, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(textColor.opacity(0.92))
                        .frame(width: width * 0.54, height: 4)
                        .padding(.horizontal, 12)
                }

            if alignment == .leading {
                Spacer(minLength: 18)
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
