import Foundation
import Combine
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isConfigured = false

    private let updaterController: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    init(bundle: Bundle) {
        guard SparkleConfiguration(bundle: bundle) != nil else {
            self.updaterController = nil
            self.canCheckForUpdates = false
            self.isConfigured = false
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self.isConfigured = true
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            guard let self else { return }
            Task { @MainActor in
                self.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        updaterController.checkForUpdates(nil)
    }
}

private struct SparkleConfiguration {
    let feedURL: URL
    let publicKey: String

    init?(bundle: Bundle) {
        guard let rawFeedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: rawFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              feedURL.scheme?.isEmpty == false else {
            return nil
        }

        guard let rawPublicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return nil
        }

        let publicKey = rawPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty,
              publicKey != "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" else {
            return nil
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}
