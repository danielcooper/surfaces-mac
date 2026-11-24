import Foundation

/// Talks to one Surfaces server: signs in, keeps tokens fresh, and reads screens.
///
/// The refresh token lives in the Keychain; access tokens only in memory. Refresh
/// tokens rotate on every use and the server revokes everything if one is used
/// twice, so refreshes are serialised through a single task.
actor SurfacesClient {
    enum ImageResult: Sendable {
        case unchanged
        case image(Data, etag: String?)
        case missing
    }

    let server: URL
    private let session: URLSession
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var refreshing: Task<String, Error>?

    init(server: URL) {
        self.server = server
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    nonisolated var keychainAccount: String { "refresh-token:" + OAuthConfig.origin(server) }
    nonisolated var hasStoredSession: Bool { Keychain.get(keychainAccount) != nil }

    // MARK: Signing in and out

    func completeSignIn(code: String, request: AuthorizationRequest) async throws {
        let tokens = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": OAuthConfig.clientID(server),
            "code_verifier": request.verifier,
            "redirect_uri": OAuthConfig.redirectURI,
            "resource": OAuthConfig.resource(server),
        ])
        store(tokens)
        Log.auth.info("Signed in to \(OAuthConfig.origin(self.server), privacy: .public)")
    }

    func signOut() async {
        if let refresh = Keychain.get(keychainAccount) {
            var request = URLRequest(url: endpoint("/revoke"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": refresh, "client_id": OAuthConfig.clientID(server)])
            _ = try? await session.data(for: request)
        }
        Keychain.delete(keychainAccount)
        accessToken = nil
        accessExpiry = .distantPast
    }

    // MARK: API

    func screens() async throws -> [RemoteScreen] {
        let (data, response) = try await authorized(URLRequest(url: endpoint("/api/screens")))
        guard response.statusCode == 200 else { throw AuthError.server("Listing screens failed (HTTP \(response.statusCode))") }
        return try JSONDecoder().decode(ScreenList.self, from: data).screens
    }

    func image(screenID: String, etag: String?) async throws -> ImageResult {
        let id = screenID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? screenID
        var request = URLRequest(url: endpoint("/api/screens/\(id)/image.png"))
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await authorized(request)
        switch response.statusCode {
        case 200: return .image(data, etag: response.value(forHTTPHeaderField: "ETag"))
        case 304: return .unchanged
        case 404: return .missing
        default: throw AuthError.server("Fetching “\(screenID)” failed (HTTP \(response.statusCode))")
        }
    }

    // MARK: Tokens

    private func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await send(request)
        if response.statusCode == 401 {
            // The access token was revoked or expired early: refresh once and retry.
            accessToken = nil
            request.setValue("Bearer \(try await refresh())", forHTTPHeaderField: "Authorization")
            (data, response) = try await send(request)
            if response.statusCode == 401 { throw AuthError.signedOut }
        }
        return (data, response)
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessExpiry > Date() { return accessToken }
        return try await refresh()
    }

    private func refresh() async throws -> String {
        if let refreshing { return try await refreshing.value }
        let task = Task { try await self.performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = Keychain.get(keychainAccount) else { throw AuthError.signedOut }
        do {
            let tokens = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": OAuthConfig.clientID(server),
                "resource": OAuthConfig.resource(server),
            ])
            store(tokens)
            return tokens.access_token
        } catch AuthError.server(let message) where message.hasPrefix("invalid_grant") {
            Log.auth.notice("Refresh token rejected; signing out")
            Keychain.delete(keychainAccount)
            throw AuthError.signedOut
        }
    }

    private func store(_ tokens: TokenResponse) {
        accessToken = tokens.access_token
        accessExpiry = Date().addingTimeInterval((tokens.expires_in ?? 3600) - 60)
        if let refresh = tokens.refresh_token { Keychain.set(refresh, for: keychainAccount) }
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint("/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await send(request)
        if response.statusCode == 200 { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        if let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            throw AuthError.server("\(error.error): \(error.error_description ?? "")")
        }
        throw AuthError.server("The token request failed (HTTP \(response.statusCode))")
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: OAuthConfig.origin(server) + path)!
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}
