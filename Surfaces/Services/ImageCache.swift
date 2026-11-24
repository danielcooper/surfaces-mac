import Foundation

/// The latest image of each screen on disk, so widgets and the wallpaper show
/// something straight away at login, before the first check.
struct ImageCache: Sendable {
    let directory: URL

    static let standard = ImageCache(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Surfaces/Cache", isDirectory: true)
    )

    private func file(_ screenID: String, _ ext: String) -> URL {
        let name = screenID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? screenID
        return directory.appendingPathComponent("\(name).\(ext)")
    }

    func imageURL(for screenID: String) -> URL { file(screenID, "png") }

    func load(_ screenID: String) -> (data: Data, etag: String?)? {
        guard let data = try? Data(contentsOf: file(screenID, "png")) else { return nil }
        let etag = try? String(contentsOf: file(screenID, "etag"), encoding: .utf8)
        return (data, etag)
    }

    func save(_ screenID: String, data: Data, etag: String?) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(screenID, "png"), options: .atomic)
            if let etag { try etag.write(to: file(screenID, "etag"), atomically: true, encoding: .utf8) }
        } catch {
            Log.sync.error("Caching \(screenID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(_ screenID: String) {
        try? FileManager.default.removeItem(at: file(screenID, "png"))
        try? FileManager.default.removeItem(at: file(screenID, "etag"))
    }
}
