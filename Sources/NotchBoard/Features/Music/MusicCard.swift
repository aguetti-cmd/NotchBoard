import SwiftUI
import NotchBoardCore

struct MusicCard: View {
    let music: MusicService

    var body: some View {
        Card(title: "Music", symbol: "music.note", action: music.openMusic) {
            switch music.status {
            case .notRunning:
                NoticeView(text: "Music isn't open.", buttonTitle: "Open Music", action: music.openMusic)
            case .notAuthorized:
                NoticeView(text: "NotchBoard needs permission to control Music.",
                           buttonTitle: "Open Automation Settings") { SystemSettings.open("Privacy_Automation") }
            case .failed(let message):
                NoticeView(text: message)
            case .ready:
                if let np = music.nowPlaying, np.state != .stopped {
                    player(np)
                } else {
                    NoticeView(text: "Nothing playing.", buttonTitle: "Play") { music.playPause() }
                }
            }
        }
    }

    private func player(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkView(image: music.artwork, size: 54, corner: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(np.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Text(np.album).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Theme.accent).frame(width: proxy.size.width * np.progress)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(TimeFormat.clock(np.position))
                    Spacer()
                    Text("-" + TimeFormat.clock(max(np.duration - np.position, 0)))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 22) {
                Spacer()
                transport("backward.fill", size: 14, action: music.previous)
                transport(np.state == .playing ? "pause.fill" : "play.fill", size: 20, action: music.playPause)
                transport("forward.fill", size: 14, action: music.next)
                Spacer()
            }
        }
    }

    private func transport(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
