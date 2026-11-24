import Foundation
import Testing
@testable import Surfaces

struct AuthTests {
    let server = URL(string: "https://surfaces.example.com/")!

    @Test func pkceMatchesRFC7636() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = PKCE.randomString()
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func buildsTheAuthorizationURL() throws {
        let request = AuthorizationRequest(server: server, verifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0), state: "s1")
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(request.url.absoluteString.hasPrefix("https://surfaces.example.com/authorize?"))
        #expect(value("client_id") == "https://surfaces.example.com/clients/mac")
        #expect(value("redirect_uri") == "coops.surfaces:/oauth/callback")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == PKCE.challenge(for: request.verifier))
        #expect(value("scope") == "screens:read")
        #expect(value("resource") == "https://surfaces.example.com/api")
        #expect(value("state") == "s1")
    }

    @Test func checksTheCallback() throws {
        let request = AuthorizationRequest(server: server, state: "abc")
        let ok = URL(string: "coops.surfaces:/oauth/callback?code=c0de&state=abc&iss=https%3A%2F%2Fsurfaces.example.com")!
        #expect(try request.code(from: ok) == "c0de")
        #expect(throws: AuthError.stateMismatch) {
            try request.code(from: URL(string: "coops.surfaces:/oauth/callback?code=c0de&state=other")!)
        }
        #expect(throws: AuthError.issuerMismatch) {
            try request.code(from: URL(string: "coops.surfaces:/oauth/callback?code=c0de&state=abc&iss=https%3A%2F%2Fevil.example")!)
        }
        #expect(throws: AuthError.denied("The user denied access")) {
            try request.code(from: URL(string: "coops.surfaces:/oauth/callback?error=access_denied&error_description=The%20user%20denied%20access&state=abc")!)
        }
        #expect(throws: AuthError.missingCode) {
            try request.code(from: URL(string: "coops.surfaces:/oauth/callback?state=abc")!)
        }
    }

    @Test func originDropsPathsAndKeepsPorts() {
        #expect(OAuthConfig.origin(URL(string: "https://surfaces.coops.dev/")!) == "https://surfaces.coops.dev")
        #expect(OAuthConfig.origin(URL(string: "http://localhost:8787/x")!) == "http://localhost:8787")
    }

    @Test func encodesTokenForms() {
        let body = String(data: SurfacesClient.form(["b": "a b&c", "a": "x/y:z"]), encoding: .utf8)
        #expect(body == "a=x%2Fy%3Az&b=a%20b%26c")
    }
}

struct SettingsTests {
    @Test func loadsWithMissingFields() throws {
        let json = #"{"widgets":[{"screenID":"wall","width":300}],"wallpaper":{"screenID":"desk"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.serverURL == AppSettings.defaultServer)
        #expect(settings.refreshSeconds == 60)
        #expect(settings.widgets.count == 1)
        #expect(settings.widgets[0].width == 300)
        #expect(settings.widgets[0].height == 240)
        #expect(settings.widgets[0].fit == .fit)
        #expect(settings.wallpaper.screenID == "desk")
        #expect(settings.wallpaper.fit == .fill)
    }

    @Test func roundTrips() throws {
        var settings = AppSettings()
        settings.widgets = [WidgetConfig(screenID: "a", frame: CGRect(x: 10, y: 20, width: 400, height: 240), cornerRadius: 8, fit: .fill, opacity: 0.8, shadow: false)]
        settings.wallpaper = WallpaperConfig(screenID: "b", displayName: "Built-in Retina Display", fit: .fit, originals: ["Built-in Retina Display": URL(fileURLWithPath: "/tmp/x.heic")])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func widgetsHaveAMinimumSize() {
        var widget = WidgetConfig(screenID: "a", frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        widget.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(widget.width == Double(WidgetConfig.minimumSize.width))
        #expect(widget.height == Double(WidgetConfig.minimumSize.height))
    }
}
