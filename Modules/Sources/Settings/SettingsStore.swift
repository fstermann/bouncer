import BouncerFoundation
import Foundation
import Observation

/// Where preferences live. Injectable so tests never touch the real defaults domain.
/// Only ever used from the main actor, so it carries no `Sendable` requirement.
public protocol PreferencesPersistence {
    func load() -> Data?
    func save(_ data: Data)
}

public struct UserDefaultsPersistence: PreferencesPersistence {
    private static let key = "preferences"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Data? { defaults.data(forKey: Self.key) }
    public func save(_ data: Data) { defaults.set(data, forKey: Self.key) }
}

/// Single source of truth for preferences.
///
/// The whole configuration is one JSON blob: one read at launch, one coalesced write
/// per burst of edits, instead of a write per toggle.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private var storage: Preferences
    @ObservationIgnored private let persistence: PreferencesPersistence
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// How long edits are coalesced before hitting disk.
    @ObservationIgnored private let saveDebounce = Duration.milliseconds(250)

    public var preferences: Preferences {
        get {
            access(keyPath: \.preferences)
            return storage
        }
        set {
            guard newValue != storage else { return }
            withMutation(keyPath: \.preferences) { storage = newValue }
            scheduleSave()
        }
    }

    public init(persistence: PreferencesPersistence = UserDefaultsPersistence()) {
        self.persistence = persistence
        if let data = persistence.load(), let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            storage = decoded
        } else {
            storage = Preferences()
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [saveDebounce] in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Writes immediately. Call on termination so a pending debounce is not lost.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            persistence.save(try JSONEncoder().encode(storage))
        } catch {
            Log.settings.error("Encoding preferences failed: \(error, privacy: .public)")
        }
    }
}
