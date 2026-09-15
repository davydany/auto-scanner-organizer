import Foundation

public struct FileAttributes: Sendable, Equatable {
    public var size: Int
    public var modifiedAt: Date

    public init(size: Int, modifiedAt: Date) {
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// Kept separate from `FileSystem` so existing file-system test doubles don't need to change.
public protocol FileAttributesReading: Sendable {
    func attributes(at url: URL) throws -> FileAttributes
}

extension LocalFileSystem: FileAttributesReading {
    public func attributes(at url: URL) throws -> FileAttributes {
        let values = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = (values[.size] as? NSNumber)?.intValue ?? 0
        let modifiedAt = values[.modificationDate] as? Date ?? .distantPast
        return FileAttributes(size: size, modifiedAt: modifiedAt)
    }
}
