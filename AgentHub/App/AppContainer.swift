import Foundation

final class AppContainer {
    let paths: AppPaths
    let appExecutableURL: URL
    let personaManager: PersonaManager
    let workspaceManager: WorkspaceManager
    let assistantSessionStore: AssistantSessionStore
    let runtimeConfigStore: AppRuntimeConfigStore
    let authStore: AuthStore
    let taskStore: TaskStore
    let taskRunStore: TaskRunStore
    let activityLogStore: ActivityLogStore
    let chatRuntime: AssistantRuntime
    let authManager: AuthManager
    let chatSessionService: ChatSessionService
    let taskOrchestrator: TaskOrchestrator
    let scheduleRunner: ScheduleRunner
    let iMessageIntegrationConfigStore: IMessageIntegrationConfigStore
    let iMessageWhitelistService: IMessageWhitelistService
    let iMessageMentionParser: IMessageMentionParser
    let externalAgentExecutionService: ExternalAgentExecutionService
    let iMessageReplyService: IMessageReplyService
    let iMessageCommandRouter: IMessageCommandRouter
    let iMessageMonitorService: IMessageMonitorService

    private init(
        paths: AppPaths,
        appExecutableURL: URL,
        personaManager: PersonaManager,
        workspaceManager: WorkspaceManager,
        assistantSessionStore: AssistantSessionStore,
        runtimeConfigStore: AppRuntimeConfigStore,
        authStore: AuthStore,
        taskStore: TaskStore,
        taskRunStore: TaskRunStore,
        activityLogStore: ActivityLogStore,
        chatRuntime: AssistantRuntime,
        authManager: AuthManager,
        chatSessionService: ChatSessionService,
        taskOrchestrator: TaskOrchestrator,
        scheduleRunner: ScheduleRunner,
        iMessageIntegrationConfigStore: IMessageIntegrationConfigStore,
        iMessageWhitelistService: IMessageWhitelistService,
        iMessageMentionParser: IMessageMentionParser,
        externalAgentExecutionService: ExternalAgentExecutionService,
        iMessageReplyService: IMessageReplyService,
        iMessageCommandRouter: IMessageCommandRouter,
        iMessageMonitorService: IMessageMonitorService
    ) {
        self.paths = paths
        self.appExecutableURL = appExecutableURL
        self.personaManager = personaManager
        self.workspaceManager = workspaceManager
        self.assistantSessionStore = assistantSessionStore
        self.runtimeConfigStore = runtimeConfigStore
        self.authStore = authStore
        self.taskStore = taskStore
        self.taskRunStore = taskRunStore
        self.activityLogStore = activityLogStore
        self.chatRuntime = chatRuntime
        self.authManager = authManager
        self.chatSessionService = chatSessionService
        self.taskOrchestrator = taskOrchestrator
        self.scheduleRunner = scheduleRunner
        self.iMessageIntegrationConfigStore = iMessageIntegrationConfigStore
        self.iMessageWhitelistService = iMessageWhitelistService
        self.iMessageMentionParser = iMessageMentionParser
        self.externalAgentExecutionService = externalAgentExecutionService
        self.iMessageReplyService = iMessageReplyService
        self.iMessageCommandRouter = iMessageCommandRouter
        self.iMessageMonitorService = iMessageMonitorService
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
        _ = try runtimeConfigStore.loadOrCreateDefault()
        _ = try authStore.loadOrCreateDefault()
        let taskStore = try TaskStore(paths: paths)
        let taskRunStore = TaskRunStore(paths: paths)
        let activityLogStore = ActivityLogStore(paths: paths)
        let chatRuntime = CodexCLIRuntime()
        let authManager = AuthManager(
            store: authStore,
            providerClient: CodexAuthProviderClient(runtime: chatRuntime, paths: paths)
        )
        let iMessageIntegrationConfigStore = IMessageIntegrationConfigStore(paths: paths)
        _ = try iMessageIntegrationConfigStore.loadOrCreateDefault()
        let iMessageWhitelistService = IMessageWhitelistService()
        let iMessageMentionParser = IMessageMentionParser(personaManager: personaManager)
        let externalAgentExecutionService = ExternalAgentExecutionService(
            runtimeConfigStore: runtimeConfigStore,
            sessionStore: assistantSessionStore,
            paths: paths,
            runtimeFactory: { CodexCLIRuntime() }
        )
        let iMessageReplyService = IMessageReplyService()
        let iMessageCommandRouter = IMessageCommandRouter(
            configStore: iMessageIntegrationConfigStore,
            whitelistService: iMessageWhitelistService,
            mentionParser: iMessageMentionParser,
            executionService: externalAgentExecutionService,
            replyService: iMessageReplyService,
            activityLogStore: activityLogStore,
            sessionStore: assistantSessionStore,
            personaManager: personaManager
        )
        let iMessageMonitorService = IMessageMonitorService(
            configStore: iMessageIntegrationConfigStore,
            router: iMessageCommandRouter,
            activityLogStore: activityLogStore
        )
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
        iMessageMonitorService.refresh()

        return AppContainer(
            paths: paths,
            appExecutableURL: appExecutableURL,
            personaManager: personaManager,
            workspaceManager: workspaceManager,
            assistantSessionStore: assistantSessionStore,
            runtimeConfigStore: runtimeConfigStore,
            authStore: authStore,
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            chatRuntime: chatRuntime,
            authManager: authManager,
            chatSessionService: chatSessionService,
            taskOrchestrator: taskOrchestrator,
            scheduleRunner: scheduleRunner,
            iMessageIntegrationConfigStore: iMessageIntegrationConfigStore,
            iMessageWhitelistService: iMessageWhitelistService,
            iMessageMentionParser: iMessageMentionParser,
            externalAgentExecutionService: externalAgentExecutionService,
            iMessageReplyService: iMessageReplyService,
            iMessageCommandRouter: iMessageCommandRouter,
            iMessageMonitorService: iMessageMonitorService
        )
    }

    static func makeHeadless() throws -> AppContainer {
        try makeDefault()
    }
}
