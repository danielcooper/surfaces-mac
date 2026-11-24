import AppKit
import AuthenticationServices
import Observation
import ServiceManagement
import SwiftUI

/// The app's state: settings, sign-in, the screens on the server and their latest
/// images. It polls the screens in use and keeps the widgets and wallpaper current.
@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.serverURL != oldValue.serverURL { switchServer() }
            if settings.refreshSeconds != oldValue.refreshSeconds { startPolling() }
            applyDesktop(previous: oldValue)
        }
    }

    private(set) var signedIn: Bool
    private(set) var screens: [RemoteScreen] = []
    private(set) var images: [String: NSImage] = [:]
    private(set) var lastUpdated: Date?
    private(set) var problem: String?
    private(set) var signingIn = false

    /// While on, widgets float above other windows and can be moved and resized.
    var arranging = false {
        didSet { widgets.sync() }
    }

    private(set) var client: SurfacesClient
    @ObservationIgnored private var etags: [String: String] = [:]
    @ObservationIgnored private let cache = ImageCache.standard
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored let widgets = WidgetManager()
    @ObservationIgnored let wallpaper = WallpaperManager()

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        let client = SurfacesClient(server: settings.serverURL)
        self.client = client
        signedIn = client.hasStoredSession
        loadCachedImages()
        widgets.model = self
        widgets.sync()
        wallpaper.apply(settings.wallpaper, imageURL: wallpaperImageURL)
        observeSystem()
        startPolling()
    }

    // MARK: Signing in

    func signIn(using session: WebAuthenticationSession) async {
        signingIn = true
        defer { signingIn = false }
        let request = AuthorizationRequest(server: settings.serverURL)
        do {
            let callback = try await session.authenticate(
                using: request.url,
                callbackURLScheme: OAuthConfig.callbackScheme,
                preferredBrowserSession: .shared
            )
            let code = try request.code(from: callback)
            try await client.completeSignIn(code: code, request: request)
            signedIn = true
            problem = nil
            await refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            Log.auth.info("Sign-in cancelled")
        } catch {
            problem = error.localizedDescription
            Log.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() async {
        await client.signOut()
        signedIn = false
        screens = []
    }

    private func switchServer() {
        client = SurfacesClient(server: settings.serverURL)
        signedIn = client.hasStoredSession
        screens = []
        startPolling()
    }

    // MARK: Refreshing

    /// The screens shown by a widget or the wallpaper.
    var screensInUse: Set<String> {
        var ids = Set(settings.widgets.map(\.screenID))
        if let id = settings.wallpaper.screenID { ids.insert(id) }
        return ids
    }

    func screen(_ id: String) -> RemoteScreen? { screens.first { $0.id == id } }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.settings.refreshSeconds ?? 60
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// Lists the screens, then fetches new images for the ones in use (ETags make
    /// unchanged images cheap: the server answers 304).
    func refresh() async {
        guard signedIn else { return }
        do {
            screens = try await client.screens()
            for id in screensInUse {
                switch try await client.image(screenID: id, etag: etags[id]) {
                case .unchanged:
                    break
                case .image(let data, let etag):
                    cache.save(id, data: data, etag: etag)
                    etags[id] = etag
                    images[id] = NSImage(data: data)
                    if id == settings.wallpaper.screenID {
                        wallpaper.apply(settings.wallpaper, imageURL: wallpaperImageURL, changed: true)
                    }
                case .missing:
                    images[id] = nil
                    etags[id] = nil
                }
            }
            lastUpdated = Date()
            problem = nil
            widgets.imagesChanged()
        } catch AuthError.signedOut {
            signedIn = false
            problem = AuthError.signedOut.errorDescription
        } catch {
            problem = error.localizedDescription
            Log.sync.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCachedImages() {
        for id in screensInUse {
            if let cached = cache.load(id) {
                images[id] = NSImage(data: cached.data)
                etags[id] = cached.etag
            }
        }
    }

    // MARK: Widgets

    func addWidget(for screen: RemoteScreen) {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(420.0, visible.width / 2)
        let height = (width / screen.aspectRatio).rounded()
        let offset = Double(settings.widgets.count % 6) * 28
        let frame = CGRect(x: visible.maxX - width - 40 - offset, y: visible.maxY - height - 40 - offset, width: width, height: height)
        settings.widgets.append(WidgetConfig(screenID: screen.id, frame: frame))
        Task { await refresh() }
    }

    func updateWidget(_ widget: WidgetConfig) {
        guard let i = settings.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        settings.widgets[i] = widget
    }

    func removeWidget(_ id: UUID) {
        settings.widgets.removeAll { $0.id == id }
    }

    /// Called when a widget window is moved or resized by hand.
    func widgetFrameChanged(_ id: UUID, frame: CGRect) {
        guard let i = settings.widgets.firstIndex(where: { $0.id == id }), settings.widgets[i].frame != frame else { return }
        settings.widgets[i].frame = frame
    }

    // MARK: Wallpaper

    var wallpaperImageURL: URL? {
        guard let id = settings.wallpaper.screenID else { return nil }
        let url = cache.imageURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func setWallpaper(screenID: String?) {
        var config = settings.wallpaper
        if config.screenID == nil, screenID != nil {
            config.originals = wallpaper.currentPictures()
        }
        config.screenID = screenID
        settings.wallpaper = config
        if screenID != nil { Task { await refresh() } }
    }

    private func applyDesktop(previous: AppSettings) {
        widgets.sync()
        if settings.wallpaper != previous.wallpaper {
            if settings.wallpaper.screenID == nil, previous.wallpaper.screenID != nil {
                wallpaper.restore(previous.wallpaper.originals)
            } else {
                wallpaper.apply(settings.wallpaper, imageURL: wallpaperImageURL, changed: true)
            }
        }
    }

    // MARK: System

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                problem = "Couldn't change Launch at Login: \(error.localizedDescription)"
            }
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        // Wallpapers are per Space on recent macOS: apply to each Space as it becomes active.
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.wallpaper.apply(self.settings.wallpaper, imageURL: self.wallpaperImageURL) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.startPolling() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.widgets.sync()
                self.wallpaper.apply(self.settings.wallpaper, imageURL: self.wallpaperImageURL)
            }
        })
    }
}
