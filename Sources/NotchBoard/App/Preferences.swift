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

    /// World clock places, home first. Fixed for now; no Settings UI yet.
    let clockZones = ClockZone.defaults

    enum GlassStyle: String, CaseIterable, Identifiable {
        case regular, clear
        var id: String { rawValue }
        var title: String { self == .regular ? "Regular" : "Clear" }
    }

    /// Liquid Glass on the open panel. The collapsed notch stays solid black.
    var glassEnabled: Bool {
        didSet { defaults.set(glassEnabled, forKey: "glassEnabled") }
    }

    var glassStyle: GlassStyle {
        didSet { defaults.set(glassStyle.rawValue, forKey: "glassStyle") }
    }

    /// 0 is solid black, 1 is untinted glass.
    var glassAmount: Double {
        didSet { defaults.set(glassAmount, forKey: "glassAmount") }
    }

    /// What the panel actually renders, after the toggle.
    var effectiveGlass: Double { glassEnabled ? glassAmount : 0 }

    init() {
        if let data = defaults.data(forKey: "place"),
           let saved = try? JSONDecoder().decode(Place.self, from: data) {
            place = saved
        } else {
            place = .bangkok
        }
        showUsage = defaults.object(forKey: "showUsage") as? Bool ?? true
        glassEnabled = defaults.object(forKey: "glassEnabled") as? Bool ?? true
        glassStyle = GlassStyle(rawValue: defaults.string(forKey: "glassStyle") ?? "") ?? .regular
        glassAmount = min(max(defaults.object(forKey: "glassAmount") as? Double ?? 0.6, 0), 1)
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
