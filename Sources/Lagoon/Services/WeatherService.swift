import AppKit
import CoreLocation
import Observation
import SwiftUI

struct WeatherNow: Equatable {
    var temperature: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
}

struct HourForecast: Equatable {
    var label: String
    var temperature: Double
    var code: Int
    var isDay: Bool
}

struct CityResult: Identifiable, Equatable {
    var id: String { "\(name)-\(latitude)-\(longitude)" }
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
}

/// Clima de Open-Meteo (gratis, sin clave). Se actualiza como mucho cada 30 min y solo
/// cuando se mira (Inicio o el detalle del clima).
@Observable
final class WeatherService {
    enum State: Equatable { case idle, loading, loaded, noLocation, failed, choosingCity }

    var state: State = .idle
    var current: WeatherNow?
    var hours: [HourForecast] = []
    var cityName = ""
    var updatedAt: Date?

    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private var stateBeforeChoosing: State = .idle

    /// Ciudad para el reloj ("lunes, 27 de septiembre · Madrid").
    var localCityName: String {
        if !cityName.isEmpty { return cityName }
        return WorldClock.cityName(TimeZone.current)
    }

    func format(_ temperature: Double) -> String {
        "\(Int(temperature.rounded()))°"
    }

    func updatedDescription(now: Date) -> String {
        guard let updatedAt else { return "ahora" }
        return Formatters.relative(updatedAt, now: now)
    }

    // MARK: - Actualización

    func refreshIfNeeded() {
        guard !AppEnvironment.isSnapshot, state != .loading, state != .choosingCity else { return }
        if let updatedAt, current != nil, Date().timeIntervalSince(updatedAt) < 30 * 60 { return }
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard !AppEnvironment.isSnapshot else { return }
        if let lat = Prefs.defaults.object(forKey: Prefs.weatherCityLat) as? Double,
           let lon = Prefs.defaults.object(forKey: Prefs.weatherCityLon) as? Double {
            cityName = Prefs.string(Prefs.weatherCityName) ?? ""
            fetch(latitude: lat, longitude: lon)
            return
        }
        state = current == nil ? .loading : state
        location.request { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(place):
                self.cityName = place.name
                self.fetch(latitude: place.latitude, longitude: place.longitude)
            case .failure:
                if self.current == nil { self.state = .noLocation }
            }
        }
    }

    func enableLocation() {
        Prefs.defaults.removeObject(forKey: Prefs.weatherCityLat)
        Prefs.defaults.removeObject(forKey: Prefs.weatherCityLon)
        Prefs.defaults.removeObject(forKey: Prefs.weatherCityName)
        if location.isDenied {
            SystemLinks.open(.location)
            return
        }
        state = .loading
        refresh(force: true)
    }

    func startChoosingCity() {
        stateBeforeChoosing = state
        state = .choosingCity
    }

    func cancelChoosingCity() {
        state = stateBeforeChoosing == .choosingCity ? .noLocation : stateBeforeChoosing
    }

    func choose(_ city: CityResult) {
        Prefs.defaults.set(city.latitude, forKey: Prefs.weatherCityLat)
        Prefs.defaults.set(city.longitude, forKey: Prefs.weatherCityLon)
        Prefs.defaults.set(city.name, forKey: Prefs.weatherCityName)
        cityName = city.name
        current = nil
        state = .loading
        fetch(latitude: city.latitude, longitude: city.longitude)
    }

    private func fetch(latitude: Double, longitude: Double) {
        if current == nil { state = .loading }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        if Prefs.bool(Prefs.useFahrenheit) {
            components.queryItems?.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }
        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let parsed = data.flatMap { try? JSONDecoder().decode(ForecastResponse.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let parsed, error == nil else {
                    if self.current == nil { self.state = .failed }
                    return
                }
                self.apply(parsed)
            }
        }.resume()
    }

    private func apply(_ response: ForecastResponse) {
        let timeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? .current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date()
        var list: [HourForecast] = []
        for (index, time) in response.hourly.time.enumerated() {
            guard let date = parser.date(from: time),
                  date > now.addingTimeInterval(-3600),
                  index < response.hourly.temperature_2m.count else { continue }
            list.append(HourForecast(label: "\(calendar.component(.hour, from: date))",
                                     temperature: response.hourly.temperature_2m[index],
                                     code: response.hourly.weather_code[safe: index] ?? 0,
                                     isDay: (response.hourly.is_day[safe: index] ?? 1) == 1))
            if list.count == 6 { break }
        }
        if !list.isEmpty {
            list[0] = HourForecast(label: "Ahora", temperature: response.current.temperature_2m,
                                   code: response.current.weather_code, isDay: response.current.is_day == 1)
        }
        withAnimation(.easeOut(duration: 0.25)) {
            current = WeatherNow(temperature: response.current.temperature_2m,
                                 code: response.current.weather_code,
                                 isDay: response.current.is_day == 1,
                                 high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                                 low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m)
            hours = list
            updatedAt = Date()
            state = .loaded
        }
    }

    // MARK: - Buscador de ciudades

    static func searchCities(_ term: String) async -> [CityResult] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: term),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "es"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(GeocodingResponse.self, from: data) else { return [] }
        return (response.results ?? []).map { result in
            CityResult(name: result.name,
                       region: [result.admin1, result.country].compactMap { $0 }.joined(separator: ", "),
                       latitude: result.latitude,
                       longitude: result.longitude)
        }
    }

    // MARK: - Iconos y textos (códigos WMO)

    static func symbol(code: Int, isDay: Bool) -> (icon: MS, color: Color) {
        switch code {
        case 0: return isDay ? (.wbSunny, Palette.yellow) : (.bedtime, .white(0.7))
        case 1, 2: return isDay ? (.partlyCloudyDay, Palette.yellow) : (.partlyCloudyNight, .white(0.7))
        case 3: return (.cloud, .white(0.7))
        case 45, 48: return (.foggy, .white(0.7))
        case 51...57: return (.grain, Palette.blue)
        case 61...67, 80...82: return (.rainy, Palette.blue)
        case 71...77, 85, 86: return (.weatherSnowy, .white(0.85))
        case 95...99: return (.thunderstorm, Palette.yellow)
        default: return (.cloud, .white(0.7))
        }
    }

    static func description(code: Int) -> String {
        switch code {
        case 0: return "Despejado"
        case 1: return "Mayormente despejado"
        case 2: return "Parcialmente nublado"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51...57: return "Llovizna"
        case 61...65: return "Lluvia"
        case 66, 67: return "Lluvia helada"
        case 71...77: return "Nieve"
        case 80...82: return "Chubascos"
        case 85, 86: return "Chubascos de nieve"
        case 95...99: return "Tormenta"
        default: return "—"
        }
    }
}

// MARK: - Modelos de Open-Meteo

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let is_day: [Int]
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let utc_offset_seconds: Int
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }

    let results: [Result]?
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Ubicación aproximada

struct Place {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// Pide una única ubicación aproximada (precisión de ~3 km) y la ciudad.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<Place, Error>) -> Void)?

    enum LocationError: Error { case denied, unavailable }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func request(_ completion: @escaping (Result<Place, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .lagoon) { [weak self] placemarks, _ in
            let name = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea ?? ""
            self?.finish(.success(Place(name: name,
                                        latitude: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude)))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Place, Error>) {
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(result) }
    }
}
