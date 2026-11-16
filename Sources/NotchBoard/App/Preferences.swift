import Foundation
import Observation
import NotchBoardCore
import ServiceManagement

@MainActor @Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    var place: Place {
        didSet {
            if let data = try? JSONEncoder().encode(place) { defaults.set(data, forKey: "place") }
        }
    }

    var showUsage: Bool {
        didSet { defaults.set(showUsage, forKey: "showUsage") }
    }

    init() {
        if let data = defaults.data(forKey: "place"),
           let saved = try? JSONDecoder().decode(Place.self, from: data) {
            place = saved
        } else {
            place = .bangkok
        }
        showUsage = defaults.object(forKey: "showUsage") as? Bool ?? true
    }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
