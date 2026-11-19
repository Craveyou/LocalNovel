import AppleShared
import Foundation

struct DocumentRemoteState: Codable, Equatable, Sendable {
    let bookHash: String
    let fileSize: Int64
    let locator: DocumentLocator
    let progress: Double
    let readAtMs: Int64
    let version: String
    let device: SyncDevice
    func validated(key: SyncBookKey, format: String) throws -> Self {
        guard bookHash == key.bookHash, fileSize == key.fileSize, locator.format == format,
              (0...253_402_300_799_999).contains(readAtMs), progress.isFinite,
              abs(progress - locator.progress) <= 0.000001, !version.isEmpty,
              !device.deviceName.isEmpty, device.deviceName.utf16.count <= 80,
              ["ios","android","macos"].contains(device.platform) else { throw SyncAPIError.invalidResponse }
        return self
    }
}
struct DocumentPullResponse: Decodable, Sendable { let items: [DocumentRemoteState] }
struct DocumentSyncRequest: Encodable, Sendable {
    struct Item: Encodable, Sendable { let bookHash: String; let fileSize: Int64; let locator: DocumentLocator; let readAtMs: Int64 }
    let items: [Item]
}
struct DocumentSyncResponse: Decodable, Sendable {
    struct Result: Decodable, Sendable { let state: DocumentRemoteState }
    let results: [Result]
}
