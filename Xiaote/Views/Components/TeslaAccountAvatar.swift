import SwiftUI

struct TeslaAccountAvatar: View {
    let profile: FleetAccountProfile?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.surface)

            Group {
                if let url = profile?.profileImageURL {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            .frame(width: size - 5, height: size - 5)
            .clipShape(Circle())

            Circle().stroke(AppTheme.hairline, lineWidth: 0.75)
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.9))
            .padding(size * 0.24)
    }
}

struct TeslaAccountAvatarLabel: View {
    let profile: FleetAccountProfile?
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: 9) {
            if isSignedIn {
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("已连接")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            TeslaAccountAvatar(profile: profile)
        }
        .contentShape(Rectangle())
    }
}
