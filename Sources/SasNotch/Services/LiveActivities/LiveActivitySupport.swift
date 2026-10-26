// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026 Atoll Contributors
// Copyright (C) 2026 SasNotch contributors
//
// Pure helpers behind the Focus and weather activities, kept apart from the
// services so the tests can compile them alone. Adapted from Atoll
// (Ebullioscopic/Atoll, GPL-3.0-or-later).

import Foundation

enum FocusSupport {
    /// Reads Assertions.json: a Focus is on while its first store holds
    /// assertion records. Nil when the file is not what macOS writes.
    static func isActive(assertions data: Data) -> Bool? {
        guard !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        guard let first = entries.first else { return false }
        return !((first["storeAssertionRecords"] as? [Any]) ?? []).isEmpty
    }
}

enum WeatherCodes {
    /// WMO weather codes as Open-Meteo reports them.
    static func symbol(for code: Int, isDay: Bool) -> String {
        let symbol: String
        switch code {
        case 0: symbol = "sun.max.fill"
        case 1, 2: symbol = "cloud.sun.fill"
        case 3: symbol = "cloud.fill"
        case 45, 48: symbol = "cloud.fog.fill"
        case 51, 53, 55: symbol = "cloud.drizzle.fill"
        case 56, 57, 66, 67: symbol = "cloud.sleet.fill"
        case 61, 63, 65: symbol = "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: symbol = "cloud.snow.fill"
        case 80, 81, 82: symbol = "cloud.heavyrain.fill"
        case 95, 96, 99: symbol = "cloud.bolt.rain.fill"
        default: symbol = "cloud.sun.fill"
        }
        guard !isDay else { return symbol }
        switch symbol {
        case "sun.max.fill": return "moon.stars.fill"
        case "cloud.sun.fill": return "cloud.moon.fill"
        default: return symbol
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

}
