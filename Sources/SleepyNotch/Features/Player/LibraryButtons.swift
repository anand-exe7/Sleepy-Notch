import SwiftUI

/// The heart: like or unlike the current song. Beside the transport
/// buttons, quiet until used.
struct LikeButton: View {
    @ObservedObject var library: LibraryController

    var body: some View {
        Button { library.toggleLike() } label: {
            symbol
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!library.canAct)
        .opacity(library.canAct ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(library.isLiked == true ? "Remove from Liked Songs" : "Add to Liked Songs")
    }

    @ViewBuilder
    private var symbol: some View {
        if case .problem = library.flash {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Status.warning)
        } else {
            Image(systemName: library.isLiked == true ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(library.isLiked == true ? Theme.Text.primary : Theme.Text.secondary)
        }
    }

    private var help: String {
        if case .problem(let message) = library.flash { return message }
        return library.isLiked == true ? "Remove from Liked Songs" : "Add to Liked Songs"
    }
}

/// The playlist menu: pick a playlist to add the current song to.
struct PlaylistMenu: View {
    @ObservedObject var library: LibraryController

    var body: some View {
        Menu {
            if library.playlists.isEmpty {
                Text(library.isLoadingPlaylists ? "Loading playlists…" : "No playlists to add to")
            }
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.add(to: playlist) }
            }
        } label: {
            symbol
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!library.canAct)
        .opacity(library.canAct ? 1 : 0.35)
        .help(help)
        .accessibilityLabel("Add to playlist")
    }

    @ViewBuilder
    private var symbol: some View {
        if case .added = library.flash {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
        } else {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private var help: String {
        if case .added(let name) = library.flash { return "Added to \(name)" }
        return "Add to playlist"
    }
}
