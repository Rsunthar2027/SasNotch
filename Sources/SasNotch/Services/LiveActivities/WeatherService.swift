// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026 Atoll Contributors
// Copyright (C) 2026 SasNotch contributors
//
// The forecast request and weather-code symbols follow Atoll's
// LockScreenWeatherManager (Ebullioscopic/Atoll, GPL-3.0-or-later), which
// reads Open-Meteo. Weather data by Open-Meteo.com (CC BY 4.0).

import CoreLocation
import Foundation

/// Current conditions for the lock screen. The place is a city typed in
/// Settings, found with Open-Meteo's geocoder, or, with no city, the Mac's
/// location after the person allows it. Nothing is sent but coordinates.
/// Main thread only, like the island it reports to; network reads run in
/// a task and publish back on the main thread, which is what makes the
/// unchecked Sendable conformance hold.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherService()

    struct Snapshot: Equatable {
        let temperature: Double
        let unit: String
        let symbol: String
        let summary: String
        let place: String?
        let fetched: Date
    }

    @Published private(set) var snapshot: Snapshot?

    private let session: URLSession
    private var refreshTimer: Timer?
    private var location: CLLocationManager?
    private var pendingLocation: CheckedContinuation<CLLocation?, Never>?
    private var fetching = false
    static let refreshInterval: TimeInterval = 30 * 60

    override private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        super.init()
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchLockScreenSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockWeather)
    }

    func syncWithPreferences() {
        guard Self.isEnabled() else {
            refreshTimer?.invalidate(); refreshTimer = nil
            snapshot = nil
            return
        }
        if refreshTimer == nil {
            let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
        refresh()
    }

    /// Fetches now unless a fresh reading is already in hand.
    func refreshIfStale() {
        guard Self.isEnabled() else { return }
        if let snapshot, Date().timeIntervalSince(snapshot.fetched) < Self.refreshInterval / 2 { return }
        refresh()
    }

    func refresh() {
        guard Self.isEnabled(), !fetching else { return }
        fetching = true
        let city = UserDefaults.standard.string(forKey: DefaultsKey.notchLockWeatherCity)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task {
            let next = await self.fetchSnapshot(city: city)
            DispatchQueue.main.async {
                self.fetching = false
                if let next { self.snapshot = next }
            }
        }
    }

    private func fetchSnapshot(city: String) async -> Snapshot? {
        let place: (latitude: Double, longitude: Double, name: String?)?
        if city.isEmpty {
            place = await currentLocation().map { ($0.coordinate.latitude, $0.coordinate.longitude, nil) }
        } else {
            place = await geocode(city)
        }
        guard let place, let reading = await forecast(latitude: place.latitude, longitude: place.longitude) else { return nil }
        return Snapshot(temperature: reading.temperature, unit: reading.unit,
                        symbol: WeatherCodes.symbol(for: reading.code, isDay: reading.isDay),
                        summary: WeatherCodes.summary(for: reading.code), place: place.name, fetched: Date())
    }

    // MARK: Open-Meteo

    private struct GeocodeResponse: Decodable {
        struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Result]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let weather_code: Int?
            let is_day: Int?
        }
        struct Units: Decodable { let temperature_2m: String? }
        let current: Current?
        let current_units: Units?
    }

    private func geocode(_ city: String) async -> (latitude: Double, longitude: Double, name: String?)? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                                  URLQueryItem(name: "format", value: "json")]
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let first = (try? JSONDecoder().decode(GeocodeResponse.self, from: data))?.results?.first
        else { return nil }
        return (first.latitude, first.longitude, first.name)
    }

    private func forecast(latitude: Double, longitude: Double)
        async -> (temperature: Double, unit: String, code: Int, isDay: Bool)? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var items = [
            // The API reads a point as the decimal separator, in every region.
            URLQueryItem(name: "latitude", value: String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if Self.usesFahrenheit() { items.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit")) }
        components?.queryItems = items
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ForecastResponse.self, from: data),
              let temperature = decoded.current?.temperature_2m
        else { return nil }
        return (temperature, Self.usesFahrenheit() ? "°F" : "°C",
                decoded.current?.weather_code ?? 0, (decoded.current?.is_day ?? 1) == 1)
    }

    static func usesFahrenheit(locale: Locale = .current) -> Bool {
        locale.measurementSystem == .us
    }

    // MARK: Location

    private func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { self.requestLocation(continuation) }
        }
    }

    private func requestLocation(_ continuation: CheckedContinuation<CLLocation?, Never>) {
        let manager = location ?? CLLocationManager()
        location = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .denied, .restricted:
            continuation.resume(returning: nil)
            return
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 3600 {
            continuation.resume(returning: cached)
            return
        }
        pendingLocation?.resume(returning: nil)
        pendingLocation = continuation
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        pendingLocation?.resume(returning: locations.last)
        pendingLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingLocation?.resume(returning: nil)
        pendingLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted else { return }
        pendingLocation?.resume(returning: nil)
        pendingLocation = nil
    }
}

/// Lock screen weather and battery wording, added by SasNotch. English for now.
enum LockWidgetText {
    static let weatherToggle = "Weather"
    static let weatherCaption = "Current conditions from Open-Meteo. Type a city, or leave it empty to use this Mac's location."
    static let cityField = "City"
    static let cityPlaceholder = "Use my location"
    static let batteryToggle = "Charging"
    static let batteryCaption = "Battery level while charging, and when it runs low."
}
