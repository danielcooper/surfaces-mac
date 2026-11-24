import AppKit

/// Sets a screen's image as the desktop picture.
///
/// macOS caches desktop pictures by file path, so every new image is written to a
/// new file before it's set, and older copies are deleted. On recent macOS the
/// picture is per Space, so the app re-applies it whenever another Space becomes
/// active.
@MainActor
final class WallpaperManager {
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Surfaces/Wallpaper", isDirectory: true)
    private var current: URL?

    /// The desktop picture of each display now, by display name.
    func currentPictures() -> [String: URL] {
        var pictures: [String: URL] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) { pictures[screen.localizedName] = url }
        }
        return pictures
    }

    /// Shows `imageURL` on the configured displays. `changed` writes a fresh copy.
    func apply(_ config: WallpaperConfig, imageURL: URL?, changed: Bool = false) {
        guard config.screenID != nil, let imageURL else { return }
        if changed || current == nil || !FileManager.default.fileExists(atPath: current!.path) {
            current = writeCopy(of: imageURL)
        }
        guard let current else { return }
        for screen in targets(config) {
            do {
                try NSWorkspace.shared.setDesktopImageURL(current, for: screen, options: options(config.fit))
            } catch {
                Log.desktop.error("Setting the wallpaper failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts back the pictures from before Surfaces changed them.
    func restore(_ originals: [String: URL]) {
        for screen in NSScreen.screens {
            guard let url = originals[screen.localizedName], FileManager.default.fileExists(atPath: url.path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
        }
        try? FileManager.default.removeItem(at: directory)
        current = nil
    }

    static func displayNames() -> [String] { NSScreen.screens.map(\.localizedName) }

    private func targets(_ config: WallpaperConfig) -> [NSScreen] {
        guard let name = config.displayName else { return NSScreen.screens }
        return NSScreen.screens.filter { $0.localizedName == name }
    }

    private func options(_ fit: ImageFit) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        switch fit {
        case .fill:
            [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        case .fit:
            [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: false, .fillColor: NSColor.black]
        }
    }

    private func writeCopy(of source: URL) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent("surfaces-\(UUID().uuidString).png")
            try fm.copyItem(at: source, to: copy)
            for old in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where old != copy {
                try? fm.removeItem(at: old)
            }
            return copy
        } catch {
            Log.desktop.error("Writing the wallpaper failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
