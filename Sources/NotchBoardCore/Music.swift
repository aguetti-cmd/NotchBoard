import Foundation

public enum PlayerState: String, Sendable, Equatable {
    case playing, paused, stopped
}

public struct NowPlaying: Sendable, Equatable {
    public let state: PlayerState
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let position: Double

    /// Identifies the track, so artwork is only fetched when it changes.
    public var trackKey: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

/// Apple Music AppleScript. Fields are separated by a unit-separator
/// character so titles containing tabs or pipes cannot break parsing.
public enum MusicScript {
    public static let separator = "\u{1F}"

    public static let state = """
    tell application "Music"
        set pState to player state as string
        if pState is "stopped" then return "stopped"
        set sep to (character id 31)
        set t to current track
        return pState & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string)
    end tell
    """

    public static let artwork = """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        on error
            try
                return data of artwork 1 of current track
            end try
        end try
    end tell
    """

    public static let playPause = "tell application \"Music\" to playpause"
    public static let next = "tell application \"Music\" to next track"
    public static let previous = "tell application \"Music\" to previous track"

    public static func parseState(_ output: String) -> NowPlaying? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "stopped" {
            return NowPlaying(state: .stopped, title: "", artist: "", album: "", duration: 0, position: 0)
        }
        let parts = trimmed.components(separatedBy: separator)
        guard parts.count == 6 else { return nil }
        let state: PlayerState
        switch parts[0] {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .paused  // fast forwarding, rewinding: treat as paused
        }
        return NowPlaying(
            state: state,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: number(parts[4]),
            position: number(parts[5])
        )
    }

    /// AppleScript coerces reals with the system decimal separator.
    static func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }
}
