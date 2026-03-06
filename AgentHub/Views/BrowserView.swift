import SwiftUI

struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WKWebViewContainer(viewModel: viewModel)
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                toolbarButton(systemName: "chevron.backward", action: { viewModel.goBack() })
                    .disabled(!viewModel.canGoBack)
                toolbarButton(systemName: "chevron.forward", action: { viewModel.goForward() })
                    .disabled(!viewModel.canGoForward)
                toolbarButton(systemName: "arrow.clockwise", action: { viewModel.reload() })
                    .disabled(viewModel.currentURL == nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.pageTitle.isEmpty ? "Browser" : viewModel.pageTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.currentURL?.absoluteString ?? "No page selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
    }
}
