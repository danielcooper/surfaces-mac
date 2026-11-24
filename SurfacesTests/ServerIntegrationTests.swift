import Foundation
import Testing
@testable import Surfaces

/// Runs against a real Surfaces server when one is given, e.g.:
///
///   TEST_RUNNER_SURFACES_TEST_SERVER=http://localhost:8794 \
///   TEST_RUNNER_SURFACES_TEST_REFRESH_TOKEN=sfr_… \
///   TEST_RUNNER_SURFACES_TEST_SCREEN=wall  xcodebuild … test
///
/// The refresh token must come from the Mac client (`/clients/mac`). Skipped otherwise.
struct ServerIntegrationTests {
    static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["SURFACES_TEST_SERVER"] != nil))
    func talksToARealServer() async throws {
        let server = try #require(URL(string: Self.env["SURFACES_TEST_SERVER"] ?? ""))
        let refreshToken = try #require(Self.env["SURFACES_TEST_REFRESH_TOKEN"])
        let screenID = try #require(Self.env["SURFACES_TEST_SCREEN"])
        let client = SurfacesClient(server: server)
        Keychain.set(refreshToken, for: client.keychainAccount)
        defer { Keychain.delete(client.keychainAccount) }

        // Refreshes (rotating the refresh token) and lists the screens.
        let screens = try await client.screens()
        #expect(screens.contains { $0.id == screenID })
        #expect(Keychain.get(client.keychainAccount) != refreshToken, "the refresh token rotated")

        guard case .image(let data, let etag) = try await client.image(screenID: screenID, etag: nil) else {
            Issue.record("expected an image"); return
        }
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let etagValue = try #require(etag)
        guard case .unchanged = try await client.image(screenID: screenID, etag: etagValue) else {
            Issue.record("expected 304 Not Modified"); return
        }
        guard case .missing = try await client.image(screenID: "no-such-screen", etag: nil) else {
            Issue.record("expected 404"); return
        }

        // Signing out revokes the session on the server.
        let stored = try #require(Keychain.get(client.keychainAccount))
        await client.signOut()
        #expect(Keychain.get(client.keychainAccount) == nil)
        let replay = SurfacesClient(server: server)
        Keychain.set(stored, for: replay.keychainAccount)
        await #expect(throws: AuthError.signedOut) { try await replay.screens() }
        #expect(Keychain.get(replay.keychainAccount) == nil, "a rejected refresh token is forgotten")
    }
}
