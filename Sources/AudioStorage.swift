import Foundation

class AudioStorage {
    private let audioDirectory: URL

    init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirURL = appSupportURL.appendingPathComponent("DeveloperChatbot")
        audioDirectory = appDirURL.appendingPathComponent("audio", isDirectory: true)

        do {
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        } catch {
            print("AudioStorage: Failed to create audio directory: \(error)")
        }
    }

    func save(messageId: String, data: Data) throws -> String {
        let filename = "\(messageId).wav"
        let fileURL = audioDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return filename
    }

    func load(filename: String) -> Data? {
        let fileURL = audioDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    func delete(filename: String) {
        let fileURL = audioDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
}