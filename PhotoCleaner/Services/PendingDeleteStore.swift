import Foundation

final class PendingDeleteStore {
    private let key = "pendingDeleteAssetIDs"
    private let defaults = UserDefaults.standard

    func save(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: key)
        }
    }

    func load() -> [String] {
        guard let data = defaults.data(forKey: key),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return ids
    }
}
