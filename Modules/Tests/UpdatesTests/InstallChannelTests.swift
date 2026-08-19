import Foundation
import Testing

@testable import Updates

struct InstallChannelTests {
    private func emptyDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "InstallChannelTests-\(UUID().uuidString)"))
    }

    @Test func directWhenMarkerAbsent() throws {
        #expect(InstallChannel.current(defaults: try emptyDefaults()) == .direct)
    }

    @Test func homebrewWhenMarkerSet() throws {
        let defaults = try emptyDefaults()
        defaults.set(true, forKey: InstallChannel.homebrewKey)
        #expect(InstallChannel.current(defaults: defaults) == .homebrew)
    }

    @Test func directWhenMarkerFalse() throws {
        let defaults = try emptyDefaults()
        defaults.set(false, forKey: InstallChannel.homebrewKey)
        #expect(InstallChannel.current(defaults: defaults) == .direct)
    }
}
