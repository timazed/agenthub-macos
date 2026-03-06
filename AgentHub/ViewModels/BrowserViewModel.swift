import Foundation
import Combine

final class BrowserViewModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var pageTitle = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false

    func open(url: URL) {
        currentURL = url
    }

    func close() {
        currentURL = nil
        pageTitle = ""
        isLoading = false
        canGoBack = false
        canGoForward = false
    }
}
