import Foundation

/// Today's weather for the widget, from Open-Meteo (free, no account or key).
///
/// The place is a city the user types in Settings: the app never asks for
/// the Mac's location. Nothing runs in the background: the forecast is
/// fetched when the widget opens and what it has is more than twenty minutes
/// old (or the place changed), and the last answer is kept so it shows at
/// once the next time.
@MainActor
final class WeatherService: ObservableObject {
    struct Place: Codable, Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    struct Reading: Codable, Equatable {
        var temperature: Double
        var high: Double
        var low: Double
        var code: Int
        var isDay: Bool
        var fahrenheit: Bool
        var fetchedAt: Date
        var placeName: String
    }

    @Published private(set) var place: Place?
    @Published private(set) var reading: Reading?
    @Published private(set) var isLoading = false
    /// The last problem, for Settings and the widget.
    @Published private(set) var problem: String?
    /// What's typed in Settings' city box before it's looked up.
    @Published var cityDraft = ""

    /// How old a reading may be before the widget fetches again.
    static let maxAge: TimeInterval = 20 * 60

    private let defaults = UserDefaults.standard
    private static let placeKey = "weather.place"
    private static let readingKey = "weather.reading"

    init() {
        place = defaults.data(forKey: Self.placeKey).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        reading = defaults.data(forKey: Self.readingKey).flatMap { try? JSONDecoder().decode(Reading.self, from: $0) }
        cityDraft = place?.name.components(separatedBy: ",").first ?? ""
    }

    // MARK: - Choosing a place

    /// Looks the city up and keeps the best match.
    func setCity(_ name: String) async {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            place = nil
            reading = nil
            defaults.removeObject(forKey: Self.placeKey)
            defaults.removeObject(forKey: Self.readingKey)
            problem = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            components.queryItems = [
                URLQueryItem(name: "name", value: query),
                URLQueryItem(name: "count", value: "1"),
                URLQueryItem(name: "language", value: "en"),
            ]
            let data = try await Self.fetch(components.url!)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let latitude = first["latitude"] as? Double,
                  let longitude = first["longitude"] as? Double,
                  let city = first["name"] as? String else {
                problem = "No city called \"\(query)\" was found."
                return
            }
            let country = first["country"] as? String
            let place = Place(name: [city, country].compactMap { $0 }.joined(separator: ", "), latitude: latitude, longitude: longitude)
            self.place = place
            defaults.set(try? JSONEncoder().encode(place), forKey: Self.placeKey)
            problem = nil
            reading = nil
            await refresh(force: true)
        } catch {
            problem = "Couldn't reach Open-Meteo."
        }
    }

    // MARK: - Fetching

    /// Fetches when the reading is missing or stale; `force` always does.
    func refresh(force: Bool = false) async {
        guard let place else { return }
        if !force, let reading, reading.placeName == place.name,
           Date().timeIntervalSince(reading.fetchedAt) < Self.maxAge { return }
        guard !isLoading || force else { return }
        isLoading = true
        defer { isLoading = false }
        let fahrenheit = Locale.current.measurementSystem == .us
        do {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(place.latitude)),
                URLQueryItem(name: "longitude", value: String(place.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
                URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "forecast_days", value: "1"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            ]
            let data = try await Self.fetch(components.url!)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
                  let code = (current["weather_code"] as? NSNumber)?.intValue else {
                problem = "Open-Meteo sent something unexpected."
                return
            }
            let daily = json["daily"] as? [String: Any]
            let high = ((daily?["temperature_2m_max"] as? [NSNumber])?.first)?.doubleValue ?? temperature
            let low = ((daily?["temperature_2m_min"] as? [NSNumber])?.first)?.doubleValue ?? temperature
            let isDay = ((current["is_day"] as? NSNumber)?.intValue ?? 1) == 1
            let reading = Reading(
                temperature: temperature, high: high, low: low, code: code, isDay: isDay,
                fahrenheit: fahrenheit, fetchedAt: Date(), placeName: place.name
            )
            self.reading = reading
            defaults.set(try? JSONEncoder().encode(reading), forKey: Self.readingKey)
            problem = nil
        } catch {
            problem = "Couldn't reach Open-Meteo."
        }
    }

    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    // MARK: - Describing it

    /// A word and a glyph for a WMO weather code.
    static func describe(code: Int, isDay: Bool) -> (text: String, symbol: String) {
        switch code {
        case 0: return ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return ("Mostly clear", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 2: return ("Partly cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Overcast", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82: return ("Showers", "cloud.heavyrain.fill")
        case 85, 86: return ("Snow showers", "cloud.snow.fill")
        case 95, 96, 99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("Unknown", "cloud.fill")
        }
    }
}
