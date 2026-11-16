import Foundation
import Observation
import NotchBoardCore

@MainActor @Observable
final class WeatherService {
    private(set) var snapshot: WeatherSnapshot?
    private(set) var errorMessage: String?
    private let preferences: Preferences
    private var loop: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var placeName: String { preferences.place.name }

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    func refresh() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: OpenMeteo.forecastURL(for: preferences.place))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Weather service unavailable"
                return
            }
            snapshot = try OpenMeteo.decodeForecast(data)
            errorMessage = nil
        } catch {
            // Keep the last good snapshot; just note the failure.
            errorMessage = "Weather offline"
        }
    }

    func search(_ query: String) async -> [Place] {
        guard let url = OpenMeteo.geocodeURL(query: query),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return [] }
        return (try? OpenMeteo.decodeGeocode(data)) ?? []
    }

    func setPlace(_ place: Place) {
        preferences.place = place
        snapshot = nil
        Task { await refresh() }
    }
}
