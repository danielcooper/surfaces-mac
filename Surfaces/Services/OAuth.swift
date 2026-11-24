import CryptoKit
import Foundation
import Security

/// The values Surfaces for Mac uses with the Surfaces authorization server.
enum OAuthConfig {
    static let callbackScheme = "coops.surfaces"
    static let redirectURI = "coops.surfaces:/oauth/callback"
    static let scope = "screens:read"

    /// `https://host[:port]` with no trailing slash: the issuer.
    static func origin(_ server: URL) -> String {
        var parts = URLComponents()
        parts.scheme = server.scheme
        parts.host = server.host
        parts.port = server.port
        return parts.string ?? server.absoluteString
    }

    /// The Mac app's Client ID Metadata Document, published by the server.
    static func clientID(_ server: URL) -> String { origin(server) + "/clients/mac" }
    /// The screens API: the audience of the app's tokens.
    static func resource(_ server: URL) -> String { origin(server) + "/api" }
}

enum PKCE {
    static func randomString(bytes count: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "no system randomness")
        return base64URL(Data(bytes))
    }

    /// RFC 7636 S256: BASE64URL(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AuthError: LocalizedError, Equatable {
    case denied(String)
    case stateMismatch
    case issuerMismatch
    case missingCode
    case server(String)
    case signedOut

    var errorDescription: String? {
        switch self {
        case .denied(let why): "Sign-in was cancelled or denied (\(why))."
        case .stateMismatch: "The sign-in response didn't match this request. Try again."
        case .issuerMismatch: "The sign-in response came from a different server. Try again."
        case .missingCode: "The sign-in response had no authorization code."
        case .server(let message): message
        case .signedOut: "You're signed out of Surfaces."
        }
    }
}

/// One authorization-code request with PKCE (S256) and a state value.
struct AuthorizationRequest: Sendable {
    let server: URL
    let verifier: String
    let state: String

    init(server: URL, verifier: String = PKCE.randomString(), state: String = PKCE.randomString(bytes: 16)) {
        self.server = server
        self.verifier = verifier
        self.state = state
    }

    var url: URL {
        var c = URLComponents(string: OAuthConfig.origin(server) + "/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthConfig.clientID(server)),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: OAuthConfig.scope),
            URLQueryItem(name: "resource", value: OAuthConfig.resource(server)),
        ]
        return c.url!
    }

    /// The authorization code from the redirect, after checking state and issuer (RFC 9207).
    func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let iss = value("iss"), iss != OAuthConfig.origin(server) { throw AuthError.issuerMismatch }
        guard value("state") == state else { throw AuthError.stateMismatch }
        if let error = value("error") { throw AuthError.denied(value("error_description") ?? error) }
        guard let code = value("code"), !code.isEmpty else { throw AuthError.missingCode }
        return code
    }
}

/// The token endpoint's response.
struct TokenResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

struct OAuthErrorResponse: Decodable, Sendable {
    let error: String
    let error_description: String?
}
