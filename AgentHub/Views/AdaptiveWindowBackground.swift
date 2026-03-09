import AppKit
import SwiftUI

struct AdaptiveWindowBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .ignoresSafeArea()
    }
}
