import Foundation

public struct WeatherSnapshot: Sendable, Equatable {
    public let temperature: Double
    public let apparent: Double
    public let humidity: Int
    public let code: Int
    public let isDay: Bool
    public let high: Double?
    public let low: Double?
    public let precipitationChance: Int?
    public let fetchedAt: Date
}

public struct Place: Sendable, Equatable, Codable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let country: String?

    public init(name: String, latitude: Double, longitude: Double, country: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
    }

    public static let bangkok = Place(name: "Bangkok", latitude: 13.7563, longitude: 100.5018, country: "Thailand")
}

/// Open-Meteo: free, no API key. https://open-meteo.com
public enum OpenMeteo {
    public static func forecastURL(for place: Place) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", place.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        return c.url!
    }

    public static func geocodeURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "5"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
        ]
        return c.url
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
            let precipitation_probability_max: [Double?]?
        }
        let current: Current
        let daily: Daily?
    }

    private struct GeocodeResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
        }
        let results: [Result]?
    }

    public static func decodeForecast(_ data: Data, fetchedAt: Date = .now) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherSnapshot(
            temperature: r.current.temperature_2m,
            apparent: r.current.apparent_temperature,
            humidity: Int(r.current.relative_humidity_2m.rounded()),
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            high: r.daily?.temperature_2m_max?.first ?? nil,
            low: r.daily?.temperature_2m_min?.first ?? nil,
            precipitationChance: (r.daily?.precipitation_probability_max?.first ?? nil).map { Int($0.rounded()) },
            fetchedAt: fetchedAt
        )
    }

    public static func decodeGeocode(_ data: Data) throws -> [Place] {
        let r = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        return (r.results ?? []).map {
            Place(name: $0.name, latitude: $0.latitude, longitude: $0.longitude, country: $0.country)
        }
    }
}

/// WMO weather interpretation codes, as used by Open-Meteo.
public enum WeatherCode {
    public static func describe(_ code: Int, isDay: Bool) -> (symbol: String, label: String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1: return (isDay ? "sun.max.fill" : "moon.fill", "Mostly clear")
        case 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51, 53, 55: return ("cloud.drizzle.fill", "Drizzle")
        case 56, 57: return ("cloud.sleet.fill", "Freezing drizzle")
        case 61: return ("cloud.rain.fill", "Light rain")
        case 63: return ("cloud.rain.fill", "Rain")
        case 65: return ("cloud.heavyrain.fill", "Heavy rain")
        case 66, 67: return ("cloud.sleet.fill", "Freezing rain")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "Snow")
        case 80, 81: return ("cloud.sun.rain.fill", "Showers")
        case 82: return ("cloud.heavyrain.fill", "Heavy showers")
        case 85, 86: return ("cloud.snow.fill", "Snow showers")
        case 95: return ("cloud.bolt.rain.fill", "Thunderstorm")
        case 96, 99: return ("cloud.bolt.rain.fill", "Thunderstorm, hail")
        default: return ("cloud.fill", "Unknown")
        }
    }
}
