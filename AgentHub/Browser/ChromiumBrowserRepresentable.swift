import SwiftUI

struct ChromiumBrowserRepresentable: NSViewRepresentable {
    @ObservedObject var controller: ChromiumBrowserController

    func makeNSView(context: Context) -> AHChromiumBrowserView {
        controller.browserView
    }

    func updateNSView(_ nsView: AHChromiumBrowserView, context: Context) {
    }
}
