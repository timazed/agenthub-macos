import AppKit
import Foundation

private final class BrowserControllerStore {
    @MainActor
    lazy var controller = ChromiumBrowserController()
}

@MainActor
private final class HeadlessBrowserHost: NSObject, NSWindowDelegate {
    var window: NSWindow!
    private weak var browserView: AHChromiumBrowserView?

    init(controller: ChromiumBrowserController) {
        super.init()
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 960)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.alphaValue = 0.0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        let contentView = NSView(frame: frame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = contentView

        controller.browserView.frame = contentView.bounds
        controller.browserView.autoresizingMask = [.width, .height]
        contentView.addSubview(controller.browserView)
        contentView.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        window.orderOut(nil)

        self.window = window
        self.browserView = controller.browserView
    }

    func teardown(controller: ChromiumBrowserController) {
        controller.prepareForShutdown()
        window.delegate = nil
        browserView?.removeFromSuperview()
        window.orderOut(nil)
        window.close()
        AHChromiumShutdownRuntime()
        controller.resetBrowserView()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        browserView?.shouldAllowHostWindowClose() ?? true
    }
}

final class AppContainer {
    let paths: AppPaths
    let appExecutableURL: URL
    let personaManager: PersonaManager
    let userProfileManager: UserProfileManager
    let workspaceManager: WorkspaceManager
    let assistantSessionStore: AssistantSessionStore
    let runtimeConfigStore: AppRuntimeConfigStore
    let taskStore: TaskStore
    let taskRunStore: TaskRunStore
    let activityLogStore: ActivityLogStore
    let chatRuntime: CodexRuntime
    let chatSessionService: ChatSessionService
    let taskOrchestrator: TaskOrchestrator
    let scheduleRunner: ScheduleRunner
    private let browserControllerStore: BrowserControllerStore
    private var headlessBrowserHost: HeadlessBrowserHost?

    private init(
        paths: AppPaths,
        appExecutableURL: URL,
        personaManager: PersonaManager,
        userProfileManager: UserProfileManager,
        workspaceManager: WorkspaceManager,
        assistantSessionStore: AssistantSessionStore,
        runtimeConfigStore: AppRuntimeConfigStore,
        taskStore: TaskStore,
        taskRunStore: TaskRunStore,
        activityLogStore: ActivityLogStore,
        chatRuntime: CodexRuntime,
        chatSessionService: ChatSessionService,
        taskOrchestrator: TaskOrchestrator,
        scheduleRunner: ScheduleRunner,
        browserControllerStore: BrowserControllerStore
    ) {
        self.paths = paths
        self.appExecutableURL = appExecutableURL
        self.personaManager = personaManager
        self.userProfileManager = userProfileManager
        self.workspaceManager = workspaceManager
        self.assistantSessionStore = assistantSessionStore
        self.runtimeConfigStore = runtimeConfigStore
        self.taskStore = taskStore
        self.taskRunStore = taskRunStore
        self.activityLogStore = activityLogStore
        self.chatRuntime = chatRuntime
        self.chatSessionService = chatSessionService
        self.taskOrchestrator = taskOrchestrator
        self.scheduleRunner = scheduleRunner
        self.browserControllerStore = browserControllerStore
    }

    @MainActor
    var browserController: ChromiumBrowserController {
        browserControllerStore.controller
    }

    @MainActor
    func installHeadlessBrowserHostIfNeeded() {
        guard headlessBrowserHost == nil else { return }
        headlessBrowserHost = HeadlessBrowserHost(controller: browserControllerStore.controller)
    }

    @MainActor
    func teardownHeadlessBrowserHost() {
        headlessBrowserHost?.teardown(controller: browserControllerStore.controller)
        headlessBrowserHost = nil
    }

    static func makeDefault() throws -> AppContainer {
        let paths = AppPaths(root: AppPaths.defaultRoot())
        try paths.prepare()

        let appExecutableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let personaManager = PersonaManager(paths: paths)
        let userProfileManager = UserProfileManager(paths: paths)
        let workspaceManager = WorkspaceManager()
        let assistantSessionStore = AssistantSessionStore(paths: paths)
        let runtimeConfigStore = AppRuntimeConfigStore(paths: paths)
        _ = try runtimeConfigStore.loadOrCreateDefault()
        let taskStore = try TaskStore(paths: paths)
        let taskRunStore = TaskRunStore(paths: paths)
        let activityLogStore = ActivityLogStore(paths: paths)
        let browserControllerStore = BrowserControllerStore()
        let chatRuntime = CodexCLIRuntime()
        let chatSessionService = ChatSessionService(
            sessionStore: assistantSessionStore,
            personaManager: personaManager,
            userProfileManager: userProfileManager,
            runtime: chatRuntime,
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            browserControllerProvider: { browserControllerStore.controller }
        )
        let taskOrchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            personaManager: personaManager,
            workspaceManager: workspaceManager,
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            runtimeFactory: { CodexCLIRuntime() }
        )
        let scheduleRunner = ScheduleRunner(
            taskStore: taskStore,
            orchestrator: taskOrchestrator,
            paths: paths
        )

        return AppContainer(
            paths: paths,
            appExecutableURL: appExecutableURL,
            personaManager: personaManager,
            userProfileManager: userProfileManager,
            workspaceManager: workspaceManager,
            assistantSessionStore: assistantSessionStore,
            runtimeConfigStore: runtimeConfigStore,
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            chatRuntime: chatRuntime,
            chatSessionService: chatSessionService,
            taskOrchestrator: taskOrchestrator,
            scheduleRunner: scheduleRunner,
            browserControllerStore: browserControllerStore
        )
    }

    static func makeHeadless() throws -> AppContainer {
        try makeDefault()
    }
}
