import Foundation
import WebKit

final class BrowserProfile {
    let record: BrowserProfileRecord

    var profileId: String {
        record.profileId
    }

    var displayName: String {
        record.displayName
    }

    var storageScope: BrowserStorageScope {
        record.storageScope
    }

    init(record: BrowserProfileRecord = .default()) {
        self.record = record
    }

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        switch storageScope {
        case .sharedDefault:
            configuration.websiteDataStore = .default()
        }
        return configuration
    }
}
