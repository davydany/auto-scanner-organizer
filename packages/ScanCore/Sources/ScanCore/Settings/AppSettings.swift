import Foundation
import Synchronization

public enum ClaudeModel: String, Codable, Sendable, CaseIterable {
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"
    case haiku45 = "claude-haiku-4-5"

    /// Longest image edge in pixels the model accepts (spec §8.1).
    public var maxImageLongEdge: Int {
        self == .haiku45 ? 1568 : 2576
    }
}

public enum ScanSource: String, Codable, Sendable, CaseIterable {
    case feeder, flatbed
}

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case color, grayscale
    case blackAndWhite = "black-and-white"
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var stagingPath: String?
    public var vaultPath: String?
    public var model: ClaudeModel
    public var autoFileThreshold: Double
    public var defaultScannerName: String?
    public var source: ScanSource
    public var dpi: Int
    public var colorMode: ColorMode
    public var duplex: Bool

    public init(stagingPath: String? = nil, vaultPath: String? = nil, model: ClaudeModel = .sonnet5,
                autoFileThreshold: Double = 0.75, defaultScannerName: String? = nil, source: ScanSource = .feeder,
                dpi: Int = 300, colorMode: ColorMode = .color, duplex: Bool = true) {
        self.stagingPath = stagingPath
        self.vaultPath = vaultPath
        self.model = model
        self.autoFileThreshold = autoFileThreshold
        self.defaultScannerName = defaultScannerName
        self.source = source
        self.dpi = dpi
        self.colorMode = colorMode
        self.duplex = duplex
    }

    public static let `default` = AppSettings()

    public var effectiveThreshold: Double {
        autoFileThreshold.isFinite
            ? min(max(autoFileThreshold, FilingDecider.thresholdRange.lowerBound), FilingDecider.thresholdRange.upperBound)
            : FilingDecider.thresholdRange.upperBound
    }
}

public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private let storage = Mutex<[String: Data]>([:])

    public init() {}

    public func data(forKey key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        storage.withLock { $0[key] = data }
    }
}

public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

public struct SettingsRepository: Sendable {
    public static let storageKey = "AppSettings.v1"

    private let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public func load() -> AppSettings {
        guard let data = store.data(forKey: Self.storageKey),
              let settings = try? ScanCoreJSON.decoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        store.set(try ScanCoreJSON.encoder().encode(settings), forKey: Self.storageKey)
    }
}
