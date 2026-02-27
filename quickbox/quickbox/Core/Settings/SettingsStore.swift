import Foundation

final class SettingsStore {
    private let userDefaults: UserDefaults
    private let preferencesKey = "quickbox.preferences"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(AppPreferences.self, from: data)
        } catch {
            return .default
        }
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        userDefaults.set(data, forKey: preferencesKey)
    }
}
