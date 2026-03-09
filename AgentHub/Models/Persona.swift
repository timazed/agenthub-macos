import Foundation

struct PersonaContactProfile: Codable, Hashable {
    var fullName: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var phoneNumber: String?
    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?
}

struct Persona: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var profilePictureURL: String?
    var directoryPath: String
}
