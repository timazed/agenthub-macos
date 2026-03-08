import Foundation

final class AppContainer {
    let paths: AppPaths
    let appExecutableURL: URL
    let personaManager: PersonaManager
    let workspaceManager: WorkspaceManager
    let assistantSessionStore: AssistantSessionStore
    let runtimeConfigStore: AppRuntimeConfigStore
    let authStore: AuthStore
    let onboardingStore: OnboardingStore
    let taskStore: TaskStore
    let taskRunStore: TaskRunStore
    let activityLogStore: ActivityLogStore
    let chatRuntime: AssistantRuntime
    let authManager: AuthManager
    let onboardingManager: OnboardingManager
    let chatSessionService: ChatSessionService
    let taskOrchestrator: TaskOrchestrator
    let scheduleRunner: ScheduleRunner

    private init(
        paths: AppPaths,
        appExecutableURL: URL,
        personaManager: PersonaManager,
        workspaceManager: WorkspaceManager,
        assistantSessionStore: AssistantSessionStore,
        runtimeConfigStore: AppRuntimeConfigStore,
        authStore: AuthStore,
        onboardingStore: OnboardingStore,
        taskStore: TaskStore,
        taskRunStore: TaskRunStore,
        activityLogStore: ActivityLogStore,
        chatRuntime: AssistantRuntime,
        authManager: AuthManager,
        onboardingManager: OnboardingManager,
        chatSessionService: ChatSessionService,
        taskOrchestrator: TaskOrchestrator,
        scheduleRunner: ScheduleRunner
    ) {
        self.paths = paths
        self.appExecutableURL = appExecutableURL
        self.personaManager = personaManager
        self.workspaceManager = workspaceManager
        self.assistantSessionStore = assistantSessionStore
        self.runtimeConfigStore = runtimeConfigStore
        self.authStore = authStore
        self.onboardingStore = onboardingStore
        self.taskStore = taskStore
        self.taskRunStore = taskRunStore
        self.activityLogStore = activityLogStore
        self.chatRuntime = chatRuntime
        self.authManager = authManager
        self.onboardingManager = onboardingManager
        self.chatSessionService = chatSessionService
        self.taskOrchestrator = taskOrchestrator
        self.scheduleRunner = scheduleRunner
    }

    static func makeDefault() throws -> AppContainer {
        let paths = AppPaths(root: AppPaths.defaultRoot())
        try paths.prepare()

        let appExecutableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let personaManager = PersonaManager(paths: paths)
        let workspaceManager = WorkspaceManager()
        let assistantSessionStore = AssistantSessionStore(paths: paths)
        let runtimeConfigStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        let onboardingStore = OnboardingStore(paths: paths)
        _ = try runtimeConfigStore.loadOrCreateDefault()
        _ = try authStore.loadOrCreateDefault()
        _ = try onboardingStore.loadOrCreateDefault()
        let taskStore = try TaskStore(paths: paths)
        let taskRunStore = TaskRunStore(paths: paths)
        let activityLogStore = ActivityLogStore(paths: paths)
        let chatRuntime = CodexCLIRuntime()
        let authManager = AuthManager(
            store: authStore,
            providerClient: CodexAuthProviderClient(runtime: chatRuntime, paths: paths)
        )
        let onboardingManager = OnboardingManager(store: onboardingStore)
        let chatSessionService = ChatSessionService(
            sessionStore: assistantSessionStore,
            personaManager: personaManager,
            runtime: chatRuntime,
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            authManager: authManager
        )
        let taskOrchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            personaManager: personaManager,
            workspaceManager: workspaceManager,
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            authManager: authManager,
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
            workspaceManager: workspaceManager,
            assistantSessionStore: assistantSessionStore,
            runtimeConfigStore: runtimeConfigStore,
            authStore: authStore,
            onboardingStore: onboardingStore,
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            chatRuntime: chatRuntime,
            authManager: authManager,
            onboardingManager: onboardingManager,
            chatSessionService: chatSessionService,
            taskOrchestrator: taskOrchestrator,
            scheduleRunner: scheduleRunner
        )
    }

    static func makeHeadless() throws -> AppContainer {
        try makeDefault()
    }
}
