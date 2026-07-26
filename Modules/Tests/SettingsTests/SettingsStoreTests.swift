import Foundation
import Testing

@testable import Settings

private final class MemoryPersistence: PreferencesPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private(set) var writeCount = 0

    init(data: Data? = nil) {
        self.data = data
    }

    func load() -> Data? {
        lock.withLock { data }
    }

    func save(_ newData: Data) {
        lock.withLock {
            data = newData
            writeCount += 1
        }
    }
}

@Suite @MainActor struct SettingsStoreTests {
    @Test func defaultsApplyWhenNothingIsStored() {
        let store = SettingsStore(persistence: MemoryPersistence())
        #expect(store.preferences == Preferences())
    }

    @Test func preferencesRoundTrip() throws {
        let persistence = MemoryPersistence()
        let store = SettingsStore(persistence: persistence)
        store.preferences.enableAlwaysHiddenSection = true
        store.preferences.autoRehide = .onFocusedAppChange
        store.flush()

        let reloaded = SettingsStore(persistence: persistence)
        #expect(reloaded.preferences.enableAlwaysHiddenSection)
        #expect(reloaded.preferences.autoRehide == .onFocusedAppChange)
    }

    @Test func writingTheSameValueDoesNotPersist() {
        let persistence = MemoryPersistence()
        let store = SettingsStore(persistence: persistence)
        store.preferences = store.preferences
        store.flush()
        #expect(persistence.writeCount == 1)  // only the explicit flush
    }

    @Test func corruptStoredDataFallsBackToDefaults() {
        let store = SettingsStore(persistence: MemoryPersistence(data: Data("not json".utf8)))
        #expect(store.preferences == Preferences())
    }

    @Test func burstOfEditsCoalescesIntoOneWrite() async throws {
        let persistence = MemoryPersistence()
        let store = SettingsStore(persistence: persistence)
        for _ in 0..<10 { store.preferences.revealOnHover.toggle() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(persistence.writeCount == 1)
    }
}
