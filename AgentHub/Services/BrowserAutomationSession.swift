import Combine
import Foundation
import WebKit

enum BrowserSessionMode: String, Codable, Hashable {
    case manual
    case agentControlling
    case awaitingConfirmation
}

enum BrowserAutomationAction: Equatable {
    case open(URL)
    case goBack
    case goForward
    case reload
    case click(targetID: String)
    case fill(targetID: String, value: String)
    case select(targetID: String, value: String)
    case submit(targetID: String)
}

enum BrowserAutomationSessionError: LocalizedError {
    case sessionUnavailable
    case webViewUnavailable
    case snapshotUnavailable
    case targetNotFound(String)
    case scriptExecutionFailed

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            return "Browser automation session is unavailable"
        case .webViewUnavailable:
            return "Browser web view is not attached"
        case .snapshotUnavailable:
            return "Browser page snapshot is unavailable"
        case let .targetNotFound(targetID):
            return "Browser target was not found: \(targetID)"
        case .scriptExecutionFailed:
            return "Browser page script execution failed"
        }
    }
}

protocol BrowserWebViewControlling: AnyObject {
    var currentURL: URL? { get }
    var pageTitle: String { get }
    var isLoadingPage: Bool { get }
    var canNavigateBack: Bool { get }
    var canNavigateForward: Bool { get }

    func loadRequest(_ request: URLRequest)
    func navigateBack()
    func navigateForward()
    func reloadPage()
    func evaluate(script: String) async throws -> Any?
}

extension WKWebView: BrowserWebViewControlling {
    var currentURL: URL? { url }
    var pageTitle: String { title ?? "" }
    var isLoadingPage: Bool { isLoading }
    var canNavigateBack: Bool { canGoBack }
    var canNavigateForward: Bool { canGoForward }

    func loadRequest(_ request: URLRequest) {
        _ = load(request)
    }

    func navigateBack() {
        _ = goBack()
    }

    func navigateForward() {
        _ = goForward()
    }

    func reloadPage() {
        _ = reload()
    }

    func evaluate(script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}

@MainActor
final class BrowserAutomationSession: ObservableObject {
    @Published private(set) var record: BrowserSessionRecord
    @Published private(set) var mode: BrowserSessionMode

    let profile: BrowserProfile

    private weak var webView: BrowserWebViewControlling?
    private(set) var latestSnapshot: BrowserPageSnapshot?
    
    var isWebViewAttached: Bool {
        webView != nil
    }

    init(
        profile: BrowserProfile,
        record: BrowserSessionRecord? = nil,
        mode: BrowserSessionMode = .manual
    ) {
        self.profile = profile
        self.record = record ?? BrowserSessionRecord(
            id: UUID(),
            profileId: profile.profileId,
            currentURL: nil,
            title: "",
            isLoading: false,
            startedAt: Date()
        )
        self.mode = mode
    }

    func attach(webView: BrowserWebViewControlling) {
        self.webView = webView
        syncState()
    }

    func detachWebView() {
        webView = nil
        record.currentURL = nil
        record.isLoading = false
    }

    func setMode(_ mode: BrowserSessionMode) {
        self.mode = mode
    }

    func execute(_ action: BrowserAutomationAction) async throws {
        guard let webView else {
            throw BrowserAutomationSessionError.webViewUnavailable
        }

        switch action {
        case let .open(url):
            webView.loadRequest(URLRequest(url: url))
        case .goBack:
            if webView.canNavigateBack {
                webView.navigateBack()
            }
        case .goForward:
            if webView.canNavigateForward {
                webView.navigateForward()
            }
        case .reload:
            webView.reloadPage()
        case let .click(targetID):
            try await performDOMAction(script: BrowserAutomationSession.clickScript(targetID: targetID), targetID: targetID)
        case let .fill(targetID, value):
            try await performDOMAction(script: BrowserAutomationSession.fillScript(targetID: targetID, value: value), targetID: targetID)
        case let .select(targetID, value):
            try await performDOMAction(script: BrowserAutomationSession.selectScript(targetID: targetID, value: value), targetID: targetID)
        case let .submit(targetID):
            try await performDOMAction(script: BrowserAutomationSession.submitScript(targetID: targetID), targetID: targetID)
        }

        syncState()
    }

    func syncState() {
        record.currentURL = webView?.currentURL?.absoluteString
        record.title = webView?.pageTitle ?? ""
        record.isLoading = webView?.isLoadingPage ?? false
    }

    func inspectPage() async throws -> BrowserPageSnapshot {
        guard let webView else {
            throw BrowserAutomationSessionError.webViewUnavailable
        }

        let result = try await webView.evaluate(script: Self.snapshotScript)
        guard let payload = result as? [String: Any] else {
            throw BrowserAutomationSessionError.scriptExecutionFailed
        }

        let visibleTextSummary = payload["visibleTextSummary"] as? String ?? ""
        let elements = (payload["actionableElements"] as? [[String: Any]] ?? []).compactMap(Self.makeActionableElement)
        let snapshot = BrowserPageSnapshot(
            id: UUID().uuidString,
            sessionId: record.id,
            currentURL: payload["currentURL"] as? String ?? record.currentURL,
            title: payload["title"] as? String ?? record.title,
            isLoading: payload["isLoading"] as? Bool ?? record.isLoading,
            visibleTextSummary: visibleTextSummary,
            actionableElements: elements,
            createdAt: Date()
        )

        latestSnapshot = snapshot
        record.currentURL = snapshot.currentURL
        record.title = snapshot.title
        record.isLoading = snapshot.isLoading
        return snapshot
    }

    private func performDOMAction(script: String, targetID: String) async throws {
        guard let webView else {
            throw BrowserAutomationSessionError.webViewUnavailable
        }

        let result = try await webView.evaluate(script: script)
        guard let payload = result as? [String: Any], let ok = payload["ok"] as? Bool else {
            throw BrowserAutomationSessionError.scriptExecutionFailed
        }
        if !ok {
            throw BrowserAutomationSessionError.targetNotFound(targetID)
        }
    }

    private static func makeActionableElement(_ payload: [String: Any]) -> BrowserActionableElement? {
        guard let id = payload["id"] as? String, !id.isEmpty else { return nil }
        let role = BrowserElementRole(rawValue: (payload["role"] as? String) ?? "") ?? .other
        let locator = BrowserElementLocator(
            strategy: "hybrid",
            cssSelector: payload["cssSelector"] as? String,
            textAnchor: payload["textAnchor"] as? String,
            domPath: payload["domPath"] as? String
        )
        return BrowserActionableElement(
            id: id,
            role: role,
            label: payload["label"] as? String ?? "",
            value: payload["value"] as? String,
            disabled: payload["disabled"] as? Bool ?? false,
            hidden: payload["hidden"] as? Bool ?? false,
            locator: locator
        )
    }

    private static let snapshotScript = """
    (() => {
      const describe = (el, index) => {
        const role = (el.getAttribute('role') || el.tagName || 'other').toLowerCase();
        const id = `el_${index}`;
        el.setAttribute('data-agenthub-target-id', id);
        const tag = el.tagName.toLowerCase();
        const cssSelector = el.id ? `#${el.id}` : null;
        return {
          id,
          role: tag === 'button' ? 'button' : tag === 'a' ? 'link' : tag === 'input' ? 'input' : tag === 'select' ? 'select' : tag === 'form' ? 'form' : (role || 'other'),
          label: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim(),
          value: el.value || null,
          disabled: Boolean(el.disabled),
          hidden: el.hidden || el.getAttribute('aria-hidden') === 'true',
          cssSelector,
          textAnchor: (el.innerText || '').trim().slice(0, 120),
          domPath: tag
        };
      };

      const nodes = Array.from(document.querySelectorAll('button, a, input, select, form, [role="button"], [role="link"]'));
      return {
        currentURL: window.location.href,
        title: document.title,
        isLoading: document.readyState !== 'complete',
        visibleTextSummary: (document.body?.innerText || '').trim().replace(/\\s+/g, ' ').slice(0, 4000),
        actionableElements: nodes.slice(0, 200).map(describe)
      };
    })();
    """

    private static func clickScript(targetID: String) -> String {
        """
        (() => {
          const el = document.querySelector('[data-agenthub-target-id="\(escaped(targetID))"]');
          if (!el) return { ok: false };
          el.click();
          return { ok: true };
        })();
        """
    }

    private static func fillScript(targetID: String, value: String) -> String {
        """
        (() => {
          const el = document.querySelector('[data-agenthub-target-id="\(escaped(targetID))"]');
          if (!el) return { ok: false };
          el.focus();
          el.value = "\(escaped(value))";
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return { ok: true };
        })();
        """
    }

    private static func selectScript(targetID: String, value: String) -> String {
        """
        (() => {
          const el = document.querySelector('[data-agenthub-target-id="\(escaped(targetID))"]');
          if (!el) return { ok: false };
          el.value = "\(escaped(value))";
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return { ok: true };
        })();
        """
    }

    private static func submitScript(targetID: String) -> String {
        """
        (() => {
          const el = document.querySelector('[data-agenthub-target-id="\(escaped(targetID))"]');
          if (!el) return { ok: false };
          if (typeof el.requestSubmit === 'function') {
            el.requestSubmit();
          } else if (typeof el.submit === 'function') {
            el.submit();
          } else {
            el.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          }
          return { ok: true };
        })();
        """
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
