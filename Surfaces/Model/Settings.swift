import CoreGraphics
import Foundation

/// How an image fills the space it's given.
enum ImageFit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fit, fill

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fit: "Fit (whole image)"
        case .fill: "Fill (crop to size)"
        }
    }
}

/// A desktop widget: one screen's image in a borderless window of any size.
struct WidgetConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var screenID: String
    /// Window frame in global screen coordinates (points, bottom-left origin).
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var cornerRadius: Double
    var fit: ImageFit
    var opacity: Double
    var shadow: Bool

    static let minimumSize = CGSize(width: 80, height: 60)

    init(
        id: UUID = UUID(), screenID: String, frame: CGRect, cornerRadius: Double = 14,
        fit: ImageFit = .fit, opacity: Double = 1, shadow: Bool = true
    ) {
        self.id = id
        self.screenID = screenID
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
        self.cornerRadius = cornerRadius
        self.fit = fit
        self.opacity = opacity
        self.shadow = shadow
    }

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = max(newValue.width, Self.minimumSize.width)
            height = max(newValue.height, Self.minimumSize.height)
        }
    }

    // Tolerates missing fields, so settings saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        screenID = try c.decode(String.self, forKey: .screenID)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 100
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 100
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 400
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 240
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 14
        fit = try c.decodeIfPresent(ImageFit.self, forKey: .fit) ?? .fit
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? true
    }
}

/// Which screen, if any, is the desktop picture.
struct WallpaperConfig: Codable, Equatable, Sendable {
    /// nil when the wallpaper is off.
    var screenID: String?
    /// The display's name, or nil for every display.
    var displayName: String?
    var fit: ImageFit
    /// Desktop pictures from before Surfaces changed them, by display name; restored when turned off.
    var originals: [String: URL]

    init(screenID: String? = nil, displayName: String? = nil, fit: ImageFit = .fill, originals: [String: URL] = [:]) {
        self.screenID = screenID
        self.displayName = displayName
        self.fit = fit
        self.originals = originals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenID = try c.decodeIfPresent(String.self, forKey: .screenID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        fit = try c.decodeIfPresent(ImageFit.self, forKey: .fit) ?? .fill
        originals = try c.decodeIfPresent([String: URL].self, forKey: .originals) ?? [:]
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let defaultServer = URL(string: "https://surfaces.coops.dev")!
    static let refreshChoices: [Double] = [30, 60, 300, 900]
    private static let key = "settings"

    var serverURL: URL
    /// How often to check the screens in use for a new image, in seconds.
    var refreshSeconds: Double
    var widgets: [WidgetConfig]
    var wallpaper: WallpaperConfig

    init(serverURL: URL = defaultServer, refreshSeconds: Double = 60, widgets: [WidgetConfig] = [], wallpaper: WallpaperConfig = WallpaperConfig()) {
        self.serverURL = serverURL
        self.refreshSeconds = refreshSeconds
        self.widgets = widgets
        self.wallpaper = wallpaper
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try c.decodeIfPresent(URL.self, forKey: .serverURL) ?? Self.defaultServer
        refreshSeconds = try c.decodeIfPresent(Double.self, forKey: .refreshSeconds) ?? 60
        widgets = (try? c.decodeIfPresent([WidgetConfig].self, forKey: .widgets)) ?? []
        wallpaper = (try? c.decodeIfPresent(WallpaperConfig.self, forKey: .wallpaper)) ?? WallpaperConfig()
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
