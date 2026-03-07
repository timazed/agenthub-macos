import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isPanelPresented = false
    @Published var isEditorPresented = false
    @Published var isBrowserPresented = false
    @Published var editingTask: TaskRecord?

    func togglePanel() {
        isPanelPresented.toggle()
    }

    func openEditor(for task: TaskRecord?) {
        editingTask = task
        isEditorPresented = true
    }

    func openBrowser() {
        isBrowserPresented = true
    }

    func toggleBrowser() {
        isBrowserPresented.toggle()
    }

    func closeBrowser() {
        isBrowserPresented = false
    }

    func closeEditor() {
        editingTask = nil
        isEditorPresented = false
    }
}
