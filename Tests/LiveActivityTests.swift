// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The pure parts of the activities SasNotch adds: Focus state, weather
/// symbols, and the island's shape settings.
enum LiveActivityTests {
    static func run(_ suite: TestSuite) {
        focus(suite)
        weather(suite)
        shape(suite)
    }

    private static func focus(_ suite: TestSuite) {
        func json(_ text: String) -> Data { Data(text.utf8) }
        suite.expect(FocusSupport.isActive(assertions: json(#"{"data":[{"storeAssertionRecords":[{"a":1}]}]}"#)) == true,
                     "a store with assertion records means a Focus is on")
        suite.expect(FocusSupport.isActive(assertions: json(#"{"data":[{"storeAssertionRecords":[]}]}"#)) == false
                        && FocusSupport.isActive(assertions: json(#"{"data":[{}]}"#)) == false
                        && FocusSupport.isActive(assertions: json(#"{"data":[]}"#)) == false,
                     "an empty store means no Focus is on")
        suite.expect(FocusSupport.isActive(assertions: Data()) == nil
                        && FocusSupport.isActive(assertions: json("not json")) == nil
                        && FocusSupport.isActive(assertions: json(#"{"other":1}"#)) == nil,
                     "a file that is not the assertions store leaves the state unknown")
    }

    private static func weather(_ suite: TestSuite) {
        suite.expect(WeatherCodes.symbol(for: 0, isDay: true) == "sun.max.fill"
                        && WeatherCodes.symbol(for: 0, isDay: false) == "moon.stars.fill"
                        && WeatherCodes.symbol(for: 2, isDay: false) == "cloud.moon.fill",
                     "clear and partly cloudy skies turn to night symbols after dark")
        suite.expect(WeatherCodes.symbol(for: 61, isDay: true) == "cloud.rain.fill"
                        && WeatherCodes.symbol(for: 61, isDay: false) == "cloud.rain.fill"
                        && WeatherCodes.symbol(for: 95, isDay: true) == "cloud.bolt.rain.fill"
                        && WeatherCodes.symbol(for: 73, isDay: true) == "cloud.snow.fill",
                     "rain, storms and snow keep their symbol day and night")
        suite.expect(WeatherCodes.symbol(for: 1234, isDay: true) == "cloud.sun.fill"
                        && WeatherCodes.summary(for: 1234) == "Cloudy",
                     "an unknown code still shows something sensible")
        let codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        suite.expect(codes.allSatisfy { !WeatherCodes.summary(for: $0).isEmpty },
                     "every WMO code Open-Meteo reports has a summary")
    }

    private static func shape(_ suite: TestSuite) {
        let size = NotchCompactSize(width: 31, height: 3.6)
        suite.expect(size.width == 32 && size.height == 4,
                     "the resting size keeps even widths and whole-point heights")
        let clamped = NotchCompactSize(width: -50, height: 99)
        suite.expect(clamped.width == 0 && clamped.height == CGFloat(NotchCompactSize.heightRange.upperBound),
                     "the resting size never shrinks the island and stops at its maximum")
        suite.expect(NotchCompactSize(width: .nan, height: .infinity) == .zero,
                     "an unreadable resting size adds nothing")

        let domain = "com.sasnotch.tests.island-shape.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchCornerRadius.custom(forHeight: 32, in: defaults) == nil
                        && NotchCornerRadius.custom(forHeight: 480, in: defaults) == nil,
                     "without a saved radius both states follow the automatic corners")
        defaults.set(NotchCornerRadius.automatic, forKey: DefaultsKey.notchCompactCornerRadius)
        suite.expect(NotchCornerRadius.custom(forHeight: 32, in: defaults) == nil, "Auto keeps the automatic corners")
        defaults.set(6.0, forKey: DefaultsKey.notchCompactCornerRadius)
        defaults.set(36.0, forKey: DefaultsKey.notchExpandedCornerRadius)
        suite.expect(NotchCornerRadius.custom(forHeight: 32, in: defaults) == 6
                        && NotchCornerRadius.custom(forHeight: 480, in: defaults) == 36,
                     "the resting and open islands each read their own radius")
        defaults.set(500.0, forKey: DefaultsKey.notchExpandedCornerRadius)
        suite.expect(NotchCornerRadius.custom(forHeight: 480, in: defaults)
                        == CGFloat(NotchCornerRadius.expandedRange.upperBound),
                     "a radius out of range is brought back into it")
    }
}
