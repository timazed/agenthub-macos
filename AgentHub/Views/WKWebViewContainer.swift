import SwiftUI
import WebKit

struct WKWebViewContainer: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let automationService: BrowserAutomationService?

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, automationService: automationService)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = viewModel.profile.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(to: webView)
        context.coordinator.loadCurrentURLIfNeeded()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(to: webView)
        context.coordinator.handleModelUpdates()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let viewModel: BrowserViewModel
        private let automationService: BrowserAutomationService?
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []

        init(viewModel: BrowserViewModel, automationService: BrowserAutomationService?) {
            self.viewModel = viewModel
            self.automationService = automationService
        }

        func attach(to webView: WKWebView) {
            guard self.webView !== webView else { return }
            observations.removeAll()
            self.webView = webView
            viewModel.commandExecutor = { [weak self] command in
                self?.execute(command)
            }

            if let sessionID = viewModel.sessionID {
                automationService?.attach(webView: webView, to: sessionID)
            }

            observations = [
                webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                    self?.syncState()
                },
                webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                    self?.syncState()
                },
                webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                    self?.syncState()
                },
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                    self?.syncState()
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                    self?.syncState()
                }
            ]
        }

        func loadCurrentURLIfNeeded() {
            guard let webView, let url = viewModel.currentURL else { return }
            if webView.url != url {
                webView.load(URLRequest(url: url))
            }
        }

        func handleModelUpdates() {
            loadCurrentURLIfNeeded()
            handlePendingCommand()
        }

        private func handlePendingCommand() {
            guard let webView, let command = viewModel.pendingCommand else { return }
            _ = webView
            execute(command)
            viewModel.finishCommand(command)
        }

        private func execute(_ command: BrowserViewModel.Command) {
            guard let webView else { return }

            switch command {
            case let .open(url):
                webView.load(URLRequest(url: url))
            case .goBack:
                if webView.canGoBack {
                    webView.goBack()
                }
            case .goForward:
                if webView.canGoForward {
                    webView.goForward()
                }
            case .reload:
                webView.reload()
            }
        }

        private func syncState() {
            guard let webView else { return }
            DispatchQueue.main.async {
                if let sessionID = self.viewModel.sessionID {
                    self.automationService?.attach(webView: webView, to: sessionID)
                    self.automationService?.activeSession?.syncState()
                    if let mode = self.automationService?.activeSession?.mode {
                        self.viewModel.updateSessionMode(mode)
                    }
                }
                self.viewModel.updateNavigationState(
                    currentURL: webView.url,
                    pageTitle: webView.title ?? "",
                    isLoading: webView.isLoading,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncState()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncState()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            syncState()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            syncState()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        deinit {
            if let sessionID = viewModel.sessionID {
                Task { @MainActor [automationService] in
                    automationService?.detach(sessionID: sessionID)
                }
            }
        }
    }
}
