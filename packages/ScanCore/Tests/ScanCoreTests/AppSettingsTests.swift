import Foundation
import Testing
@testable import ScanCore

struct AppSettingsTests {
    @Test func defaultsMatchSpec() {
        let settings = AppSettings.default
        #expect(settings.model == .sonnet5)
        #expect(settings.model.rawValue == "claude-sonnet-5")
        #expect(settings.autoFileThreshold == 0.75)
        #expect(settings.source == .feeder)
        #expect(settings.dpi == 300)
        #expect(settings.colorMode == .color)
        #expect(settings.duplex)
        #expect(settings.stagingPath == nil)
        #expect(settings.vaultPath == nil)
    }

    @Test func modelImageLimits() {
        #expect(ClaudeModel.sonnet5.maxImageLongEdge == 2576)
        #expect(ClaudeModel.opus5.maxImageLongEdge == 2576)
        #expect(ClaudeModel.haiku45.maxImageLongEdge == 1568)
    }

    @Test func clampsEffectiveThreshold() {
        var settings = AppSettings.default
        settings.autoFileThreshold = 0.2
        #expect(settings.effectiveThreshold == 0.5)
        settings.autoFileThreshold = 1.4
        #expect(settings.effectiveThreshold == 1.0)
    }

    @Test func effectiveThresholdFailsSafeOnNonFiniteValues() {
        var settings = AppSettings.default
        settings.autoFileThreshold = .nan
        #expect(settings.effectiveThreshold == 1.0)
        settings.autoFileThreshold = .infinity
        #expect(settings.effectiveThreshold == 1.0)
    }

    @Test func repositoryRoundTripsAndFallsBackToDefaults() throws {
        let store = InMemoryKeyValueStore()
        let repository = SettingsRepository(store: store)
        #expect(repository.load() == .default)

        var settings = AppSettings.default
        settings.vaultPath = "/Users/me/Vault"
        settings.model = .opus5
        try repository.save(settings)
        #expect(repository.load() == settings)

        store.set(Data("not json".utf8), forKey: SettingsRepository.storageKey)
        #expect(repository.load() == .default)
    }

    @Test func repositoryPersistsNonFiniteThresholdWithoutThrowing() throws {
        let store = InMemoryKeyValueStore()
        let repository = SettingsRepository(store: store)
        var settings = AppSettings.default
        settings.autoFileThreshold = .nan
        try repository.save(settings)
        let loaded = repository.load()
        #expect(loaded.autoFileThreshold.isNaN)
        #expect(loaded.effectiveThreshold == 1.0)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        store.set(Data("x".utf8), forKey: "k")
        #expect(store.data(forKey: "k") == Data("x".utf8))
        store.set(nil, forKey: "k")
        #expect(store.data(forKey: "k") == nil)
    }
}
