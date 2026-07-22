import Foundation

enum AppleWeatherFailure: Equatable {
    case locationDenied
    case serviceUnavailable
    case offline
}

enum AppleWeatherRecovery: Equatable {
    case useSavedCity
    case preserveLastKnown
    case unavailable
}

enum AppleWeatherDataPolicy {
    static let staleAfter: TimeInterval = 60 * 60

    static func isStale(updatedAt: TimeInterval, now: Date = Date()) -> Bool {
        guard updatedAt > 0 else { return true }
        return now.timeIntervalSince1970 - updatedAt > staleAfter
    }

    static func recovery(
        for failure: AppleWeatherFailure,
        hasSavedCity: Bool,
        hasLastKnownWeather: Bool
    ) -> AppleWeatherRecovery {
        if failure == .locationDenied, hasSavedCity {
            return .useSavedCity
        }
        return hasLastKnownWeather ? .preserveLastKnown : .unavailable
    }

    static func stylistContext(temperature: String, condition: String, city: String) -> String? {
        let temperature = temperature.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !temperature.isEmpty || !condition.isEmpty else { return nil }

        let weather = [temperature, condition].filter { !$0.isEmpty }.joined(separator: " ")
        return city.isEmpty ? weather : "\(weather) in \(city)"
    }
}
