import Foundation
import Combine

final class BrowserViewModel: ObservableObject {
    enum Command: Equatable {
        case goBack
        case goForward
        case reload
    }

    @Published var currentURL: URL?
    @Published var pageTitle = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published private(set) var pendingCommand: Command?

    let profile: BrowserProfile
    var commandExecutor: ((Command) -> Void)?

    init(profile: BrowserProfile) {
        self.profile = profile
    }

    func open(url: URL) {
        currentURL = url
    }

    func goBack() {
        execute(.goBack)
    }

    func goForward() {
        execute(.goForward)
    }

    func reload() {
        execute(.reload)
    }

    func finishCommand(_ command: Command) {
        if pendingCommand == command {
            pendingCommand = nil
        }
    }

    func updateNavigationState(
        currentURL: URL?,
        pageTitle: String,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        self.currentURL = currentURL
        self.pageTitle = pageTitle
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    func close() {
        pendingCommand = nil
        currentURL = nil
        pageTitle = ""
        isLoading = false
        canGoBack = false
        canGoForward = false
    }

    private func execute(_ command: Command) {
        if let commandExecutor {
            commandExecutor(command)
        } else {
            pendingCommand = command
        }
    }
}
