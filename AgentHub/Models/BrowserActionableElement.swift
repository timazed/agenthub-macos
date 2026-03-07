import Foundation

enum BrowserElementRole: String, Codable, Hashable {
    case button
    case link
    case input
    case select
    case form
    case other
}

struct BrowserElementLocator: Codable, Hashable {
    var strategy: String
    var cssSelector: String?
    var textAnchor: String?
    var domPath: String?
}

struct BrowserActionableElement: Identifiable, Codable, Hashable {
    var id: String
    var role: BrowserElementRole
    var label: String
    var value: String?
    var disabled: Bool
    var hidden: Bool
    var locator: BrowserElementLocator
}
