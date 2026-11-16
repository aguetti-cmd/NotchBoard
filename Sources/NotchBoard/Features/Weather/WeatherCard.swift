import SwiftUI
import NotchBoardCore

struct WeatherCard: View {
    let weather: WeatherService

    var body: some View {
        Card(title: weather.placeName, symbol: "location.fill") {
            if let w = weather.snapshot {
                let d = WeatherCode.describe(w.code, isDay: w.isDay)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: d.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Int(w.temperature.rounded()))°")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(d.label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let high = w.high, let low = w.low {
                            Text("H \(Int(high.rounded()))°  L \(Int(low.rounded()))°")
                        }
                        Text("Feels \(Int(w.apparent.rounded()))°")
                        if let rain = w.precipitationChance {
                            Text("Rain \(rain)%")
                        }
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                }
            } else {
                NoticeView(text: weather.errorMessage ?? "Loading weather…")
            }
        }
    }
}
