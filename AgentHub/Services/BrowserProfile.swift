import Foundation
import WebKit

final class BrowserProfile {
    init() {}

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }
}
