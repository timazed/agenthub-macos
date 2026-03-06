import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isPanelPresented = false
    @Published var isEditorPresented = false
    @Published var editingTask: TaskRecord?

    func togglePanel() {
        isPanelPresented.toggle()
    }

    func openEditor(for task: TaskRecord?) {
        editingTask = task
        isEditorPresented = true
    }

    func closeEditor() {
        editingTask = nil
        isEditorPresented = false
    }
}
