import Foundation
import Observation

/// Shared state for the notch and the settings window.
@MainActor @Observable
final class AppModel {
    let preferences = Preferences()
    let music = MusicService()
    let agenda = AgendaService()
    let weather: WeatherService
    let usage = UsageService()

    var isExpanded = false {
        didSet { music.fastPolling = isExpanded }
    }
    var isPinned = false
    /// Held open while Settings is on screen, so appearance changes show live.
    var isPreviewing = false
    /// Set by the AppDelegate; called from the panel's gear button.
    @ObservationIgnored var openSettings: () -> Void = {}

    init() {
        weather = WeatherService(preferences: preferences)
    }

    func start() {
        music.start()
        agenda.start()
        weather.start()
        if preferences.showUsage { usage.start() }
    }

    func refreshAll() {
        Task {
            await music.refresh()
            agenda.refresh()
            await weather.refresh()
            await usage.refresh()
        }
    }
}
