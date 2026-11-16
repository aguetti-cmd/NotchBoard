import Foundation
import Testing
@testable import NotchBoardCore

@Suite struct UsageTests {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func line(id: String, req: String = "r1", session: String = "s1",
              ts: String = "2026-11-16T02:43:41.111Z", output: Int = 10, type: String = "assistant") -> Data {
        Data("""
        {"type":"\(type)","sessionId":"\(session)","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(id)","model":"m","usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":\(output)}}}
        """.utf8)
    }

    @Test func parsesAssistantLine() throws {
        let r = try #require(UsageLineParser.parse(line(id: "msg_1")))
        #expect(r.key == "msg_1|r1")
        #expect(r.input == 2 && r.cacheCreation == 100 && r.cacheRead == 1000 && r.output == 10)
        #expect(r.sessionId == "s1")
    }

    @Test func ignoresNonAssistantAndJunk() {
        #expect(UsageLineParser.parse(line(id: "x", type: "user")) == nil)
        #expect(UsageLineParser.parse(Data("{\"type\":\"assistant\"}".utf8)) == nil)
        #expect(UsageLineParser.parse(Data("not json \"usage\"".utf8)) == nil)
    }

    @Test func dedupesRepeatedContentBlocks() throws {
        var agg = UsageAggregator()
        let a = try #require(UsageLineParser.parse(line(id: "msg_1")))
        let first = agg.add(a, calendar: utc)
        let repeated = agg.add(a, calendar: utc)
        #expect(first && !repeated)
        let b = try #require(UsageLineParser.parse(line(id: "msg_2", session: "s2", output: 5)))
        agg.add(b, calendar: utc)
        let end = try #require(UsageLineParser.parseDate("2026-11-16T12:00:00Z"))
        let days = agg.days(endingAt: end, count: 2, calendar: utc)
        #expect(days.map(\.day) == ["2026-11-15", "2026-11-16"])
        #expect(days[0].total == 0)
        #expect(days[1].output == 15)
        #expect(days[1].sessions == 2)
        #expect(days[1].responses == 2)
        #expect(days[1].total == 2 * (2 + 100 + 1000) + 15)
    }

    @Test func scannerReadsIncrementallyAndSkipsPartialLines() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.jsonl")
        let now = Date()
        let ts = now.formatted(.iso8601)
        var body = line(id: "a", ts: ts) + Data("\n".utf8) + line(id: "b", ts: ts)  // second line unterminated
        try body.write(to: file)

        let scanner = UsageScanner(root: dir, calendar: utc)
        var today = await scanner.scan(now: now, dayCount: 1)
        #expect(today.last?.responses == 1)

        body += Data("\n".utf8) + line(id: "a", ts: ts) + Data("\n".utf8)  // finish b, repeat a
        try body.write(to: file)
        today = await scanner.scan(now: now, dayCount: 1)
        #expect(today.last?.responses == 2)
    }
}

@Suite struct MusicTests {
    @Test func parsesPlaying() throws {
        let s = ["playing", "Song, Pt. 2", "Artist", "Album", "245,5", "12.25"].joined(separator: MusicScript.separator)
        let np = try #require(MusicScript.parseState(s))
        #expect(np.state == .playing)
        #expect(np.title == "Song, Pt. 2")
        #expect(np.duration == 245.5)
        #expect(np.position == 12.25)
        #expect(abs(np.progress - 12.25 / 245.5) < 0.0001)
    }

    @Test func parsesStoppedAndRejectsGarbage() {
        #expect(MusicScript.parseState("stopped\n")?.state == .stopped)
        #expect(MusicScript.parseState("playing") == nil)
    }
}

@Suite struct WeatherTests {
    @Test func decodesForecast() throws {
        let json = """
        {"current":{"time":"2026-11-16T10:00","temperature_2m":31.4,"apparent_temperature":36.0,"relative_humidity_2m":68,"weather_code":2,"is_day":1},
         "daily":{"time":["2026-11-16"],"temperature_2m_max":[33.1],"temperature_2m_min":[25.0],"precipitation_probability_max":[40]}}
        """
        let w = try OpenMeteo.decodeForecast(Data(json.utf8))
        #expect(w.temperature == 31.4 && w.humidity == 68 && w.code == 2 && w.isDay)
        #expect(w.high == 33.1 && w.low == 25.0 && w.precipitationChance == 40)
    }

    @Test func decodesForecastWithNullDaily() throws {
        let json = """
        {"current":{"temperature_2m":20,"apparent_temperature":19,"relative_humidity_2m":50,"weather_code":0,"is_day":0},
         "daily":{"temperature_2m_max":[null],"temperature_2m_min":[null],"precipitation_probability_max":[null]}}
        """
        let w = try OpenMeteo.decodeForecast(Data(json.utf8))
        #expect(w.high == nil && w.precipitationChance == nil && !w.isDay)
    }

    @Test func decodesGeocode() throws {
        let json = #"{"results":[{"name":"Chiang Mai","latitude":18.79,"longitude":98.98,"country":"Thailand"}]}"#
        let places = try OpenMeteo.decodeGeocode(Data(json.utf8))
        #expect(places.first?.name == "Chiang Mai")
        #expect(try OpenMeteo.decodeGeocode(Data("{}".utf8)).isEmpty)
        #expect(OpenMeteo.geocodeURL(query: "  ") == nil)
    }

    @Test func mapsCodes() {
        #expect(WeatherCode.describe(0, isDay: false).symbol == "moon.stars.fill")
        #expect(WeatherCode.describe(95, isDay: true).label == "Thunderstorm")
        #expect(WeatherCode.describe(1234, isDay: true).label == "Unknown")
    }
}

@Suite struct FormattingTests {
    @Test func compactTokens() {
        #expect(TokenFormat.compact(950) == "950")
        #expect(TokenFormat.compact(12_400) == "12K")
        #expect(TokenFormat.compact(3_100_000) == "3.1M")
        #expect(TokenFormat.compact(1_200_000_000) == "1.2B")
    }

    @Test func clock() {
        #expect(TimeFormat.clock(187.9) == "3:07")
        #expect(TimeFormat.clock(.nan) == "0:00")
    }

    @Test func notchGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let g = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 32, leftAuxWidth: 662, rightAuxWidth: 662, menuBarHeight: 24)
        #expect(g.hasNotch && g.notch == CGRect(x: 662, y: 950, width: 188, height: 32))
        let flat = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 0, leftAuxWidth: nil, rightAuxWidth: nil, menuBarHeight: 24)
        #expect(!flat.hasNotch && flat.notch.midX == 756 && flat.notch.maxY == 982)
    }
}
