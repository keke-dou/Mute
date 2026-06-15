import Foundation
import SwiftData

@Model
final class Track {
    var name: String
    @Attribute(.externalStorage) var audioData: Data?
    var folderId: String?

    init(name: String, audioData: Data? = nil, folderId: String? = nil) {
        self.name = name
        self.audioData = audioData
        self.folderId = folderId
    }
}