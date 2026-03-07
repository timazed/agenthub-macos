import Foundation
import Combine

@MainActor
final class ActivityLogViewModel: ObservableObject {
    @Published var events: [ActivityEvent] = []
    @Published var errorMessage: String?

    private let store: ActivityLogStore

    init(store: ActivityLogStore) {
        self.store = store
    }

    func load() {
        do {
            events = try store.load(limit: 100)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(event: ActivityEvent) {
        do {
            try store.delete(eventId: event.id)
            events.removeAll { $0.id == event.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
