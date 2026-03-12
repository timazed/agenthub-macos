import SwiftUI

struct AgentAvatarView: View {
    let name: String
    let profilePictureURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.41, green: 0.34, blue: 0.76), Color(red: 0.17, green: 0.18, blue: 0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initial)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
        }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else { return "A" }
        return String(character).uppercased()
    }

    private var imageURL: URL? {
        guard let profilePictureURL else { return nil }
        let trimmed = profilePictureURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
