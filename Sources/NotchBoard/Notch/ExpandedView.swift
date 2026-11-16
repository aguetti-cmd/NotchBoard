import SwiftUI
import NotchBoardCore

/// The open panel: a header beside the notch, then three columns.
struct ExpandedView: View {
    let model: AppModel
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: max(notchSize.height, 28))
            HStack(alignment: .top, spacing: 10) {
                MusicCard(music: model.music)
                    .frame(width: 230)
                AgendaCard(agenda: model.agenda)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    WeatherCard(weather: model.weather)
                    if model.preferences.showUsage {
                        UsageCard(usage: model.usage)
                    }
                }
                .frame(width: 210)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
    }

    /// Left and right of the hardware notch; the middle stays empty.
    private var header: some View {
        HStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: notchSize.width + 20)
            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            Button {
                model.isPinned.toggle()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.isPinned ? Theme.accent : Theme.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPinned ? "Unpin" : "Keep open")
        }
        .padding(.horizontal, 28)
    }
}

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    var action: (() -> Void)? = nil
    @ViewBuilder let content: Content
    @Environment(\.glassAmount) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).kerning(0.6)
                Spacer()
                if let action {
                    Button(action: action) {
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Theme.tertiary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // More glass behind means a darker card, so white text keeps its contrast.
        .background {
            let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                card.fill(Color.black.opacity(0.28 * glass))
                card.fill(Theme.card)
            }
        }
    }
}

/// A short message with an optional button, for empty and blocked states.
struct NoticeView: View {
    let text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.22), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

enum SystemSettings {
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
