import SwiftUI
import WebKit

struct WKWebViewContainer: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(to: webView)
        context.coordinator.loadCurrentURLIfNeeded()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(to: webView)
        context.coordinator.handleModelUpdates()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let viewModel: BrowserViewModel
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        func attach(to webView: WKWebView) {
            guard self.webView !== webView else { return }
            observations.removeAll()
            self.webView = webView
            viewModel.commandExecutor = { [weak self] command in
                self?.execute(command)
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
    }
}
