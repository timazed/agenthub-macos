import Foundation

enum AuthMethod: String, Codable, CaseIterable, Hashable {
    case deviceCode
    case apiKey
    case externalSetup

    var displayName: String {
        switch self {
        case .deviceCode:
            return "Device Code"
        case .apiKey:
            return "API Key"
        case .externalSetup:
            return "External Setup"
        }
    }
}
