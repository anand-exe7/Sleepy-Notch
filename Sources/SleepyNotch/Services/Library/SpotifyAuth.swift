import Foundation
import AppKit
import Network
import CryptoKit
import Security

/// Signing in to Spotify, so the card can like songs and add them to
/// playlists through Spotify's web API.
///
/// The standard "authorization code with PKCE" flow for apps with no server
/// of their own: the sign-in page opens in the browser, Spotify sends the
/// browser back to a one-shot listener on this Mac, and the code it brings
/// is traded for tokens. There's no client secret. The Client ID comes from
/// a free app the user makes at developer.spotify.com; the refresh token
/// lives in the Keychain, and nothing runs between sign-in and a button
/// press.
@MainActor
final class SpotifyAuth: ObservableObject {
    @Published private(set) var isConnected: Bool
    /// Progress or the last problem, for Settings.
    @Published private(set) var status: String?
    @Published private(set) var isConnecting = false

    nonisolated static let redirectPort: UInt16 = 8888
    static let redirectURI = "http://127.0.0.1:8888/callback"
    private static let scopes = [
        "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative",
        "playlist-modify-private", "playlist-modify-public",
    ].joined(separator: " ")

    private let clientID: () -> String
    private var accessToken: String?
    private var expiry = Date.distantPast

    init(clientID: @escaping () -> String) {
        self.clientID = clientID
        isConnected = Keychain.read() != nil
    }

    // MARK: - Signing in and out

    func connect() async {
        let id = clientID().trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else {
            status = "Paste your Spotify Client ID first."
            return
        }
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let verifier = Self.randomString(64)
            let state = Self.randomString(16)
            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: id),
                URLQueryItem(name: "scope", value: Self.scopes),
                URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            ]
            status = "Waiting for you to approve in the browser…"
            let waiting = Task { try await Self.waitForCode(state: state) }
            NSWorkspace.shared.open(components.url!)
            let code = try await waiting.value
            try await exchange(parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": id,
                "code_verifier": verifier,
            ])
            status = nil
        } catch let error as LibraryError {
            status = error.message
        } catch {
            status = error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete()
        accessToken = nil
        expiry = .distantPast
        isConnected = false
        status = nil
    }

    // MARK: - Tokens

    /// A valid access token, refreshed first if it has run out.
    func validToken() async throws -> String {
        if let accessToken, Date() < expiry { return accessToken }
        guard let refresh = Keychain.read() else { throw LibraryError.notSignedIn }
        try await exchange(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID().trimmingCharacters(in: .whitespaces),
        ])
        guard let accessToken else { throw LibraryError.notSignedIn }
        return accessToken
    }

    private func exchange(parameters: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else {
            // A refused refresh means the sign-in is no longer good.
            if parameters["grant_type"] == "refresh_token" { disconnect() }
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
            throw LibraryError(message: reason ?? "Spotify didn't accept the sign-in.")
        }
        accessToken = token
        expiry = Date().addingTimeInterval(((json["expires_in"] as? Double) ?? 3600) - 60)
        if let refresh = json["refresh_token"] as? String {
            Keychain.save(refresh)
        }
        isConnected = true
    }

    // MARK: - The one-shot listener

    /// Waits for the browser to come back to `redirectURI`, and returns the
    /// code in it. Gives up after three minutes.
    nonisolated private static func waitForCode(state: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.anandexe7.sleepy-notch.spotify-callback")
            let listener: NWListener
            do {
                listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: redirectPort)!)
            } catch {
                continuation.resume(throwing: LibraryError(message: "Port \(redirectPort) is in use."))
                return
            }
            let finished = Finished()
            func finish(_ result: Result<String, Error>) {
                guard finished.once() else { return }
                listener.cancel()
                continuation.resume(with: result)
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let request = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = request.components(separatedBy: " ").dropFirst().first ?? ""
                    let items = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
                    let code = items.first { $0.name == "code" }?.value
                    let returned = items.first { $0.name == "state" }?.value
                    let ok = code != nil && returned == state
                    let body = ok
                        ? "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><h2>Connected</h2><p>You can close this tab and go back to Sleepy Notch.</p></body></html>"
                        : "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><h2>Not connected</h2><p>Spotify didn't approve the sign-in.</p></body></html>"
                    let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: reply.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    // Browsers also ask for the page icon: ignore those.
                    guard path.hasPrefix("/callback") else { return }
                    if let code, ok {
                        finish(.success(code))
                    } else {
                        finish(.failure(LibraryError(message: "Spotify didn't approve the sign-in.")))
                    }
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 180) {
                finish(.failure(LibraryError(message: "Sign-in timed out.")))
            }
        }
    }

    private final class Finished: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func once() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    // MARK: - PKCE helpers

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Keychain

    private enum Keychain {
        private static let service = "com.anandexe7.sleepy-notch.spotify"
        private static let account = "refresh-token"

        private static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }

        static func read() -> String? {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func save(_ token: String) {
            delete()
            var q = query
            q[kSecValueData as String] = Data(token.utf8)
            SecItemAdd(q as CFDictionary, nil)
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }
}
