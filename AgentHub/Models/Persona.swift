import Foundation

struct Persona: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var directoryPath: String
}
