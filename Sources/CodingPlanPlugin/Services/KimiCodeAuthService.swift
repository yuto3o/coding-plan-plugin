import Foundation

/// 独立管理 Kimi Code OAuth token。
///
/// 与 Kimi Code CLI 完全解耦：token 存储在插件统一 Keychain item 中。
/// 支持多账号：每个 ProviderConfiguration id 对应独立的内存缓存实例。
actor KimiCodeAuthService {
    static let shared = KimiCodeAuthService(id: "kimi")

    private static let clientId = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private static let oauthHost = "https://auth.kimi.com"

    let id: String

    private let session: URLSession
    private let decoder: JSONDecoder

    private var inMemoryToken: OAuthToken?

    init(id: String = "kimi") {
        self.id = id
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()

        // 首次初始化时，尝试把旧独立 Keychain item 迁移到统一存储。
        let legacyAccount = id == "kimi" ? "kimi-code.oauth_token" : "kimi-code.\(id).oauth_token"
        KeychainStorage.shared.migrateLegacyKimiToken(account: legacyAccount)
    }

    // MARK: - Public

    nonisolated var isAuthenticated: Bool {
        guard let token = KeychainStorage.shared.kimiToken() else { return false }
        return !token.accessToken.isEmpty
    }

    func accessToken() async throws(ProviderError) -> String {
        if let inMemoryToken, !inMemoryToken.isExpired(withBuffer: 60) {
            return inMemoryToken.accessToken
        }

        var token = KeychainStorage.shared.kimiToken()
        token?.normalize()

        guard let validToken = token else {
            throw .notAuthenticated
        }

        if validToken.isExpired(withBuffer: 60) {
            let refreshed = try await refreshAccessToken(validToken)
            KeychainStorage.shared.setKimiToken(refreshed)
            inMemoryToken = refreshed
            return refreshed.accessToken
        }

        inMemoryToken = validToken
        return validToken.accessToken
    }

    /// 启动 OAuth device-code flow。
    /// - Returns: 浏览器中需要打开的授权信息。
    func startDeviceLogin() async throws(ProviderError) -> DeviceAuthorization {
        let url = URL(string: "\(Self.oauthHost)/api/oauth/device_authorization")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "client_id=\(Self.clientId)".data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
            throw .api(code: "device_auth_failed", message: message)
        }

        do {
            return try decoder.decode(DeviceAuthorization.self, from: data)
        } catch {
            throw .decoding(error)
        }
    }

    /// 轮询 device token，直到用户授权或超时。
    func pollDeviceToken(deviceCode: String, deadline: Date) async throws(ProviderError) -> OAuthToken {
        let url = URL(string: "\(Self.oauthHost)/api/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = "client_id=\(Self.clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        while Date() < deadline {
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw .network(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw .unknown
            }

            if httpResponse.statusCode == 200 {
                do {
                    var token = try decoder.decode(OAuthToken.self, from: data)
                    token.normalize()
                    KeychainStorage.shared.setKimiToken(token)
                    inMemoryToken = token
                    return token
                } catch {
                    throw .decoding(error)
                }
            }

            let errorPayload: OAuthErrorResponse?
            do {
                errorPayload = try decoder.decode(OAuthErrorResponse.self, from: data)
            } catch {
                errorPayload = nil
            }

            let errorCode = errorPayload?.error ?? "unknown"
            switch errorCode {
            case "authorization_pending":
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                continue
            case "slow_down":
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                continue
            case "expired_token":
                throw .api(code: "device_expired", message: "授权已过期，请重试")
            case "access_denied":
                throw .api(code: "device_denied", message: "用户拒绝了授权")
            default:
                throw .api(code: errorCode, message: errorPayload?.errorDescription)
            }
        }

        throw .api(code: "device_timeout", message: "授权超时，请重试")
    }

    nonisolated func clearAuthentication() {
        KeychainStorage.shared.setKimiToken(nil)
    }

    private func refreshAccessToken(_ refreshToken: OAuthToken) async throws(ProviderError) -> OAuthToken {
        let url = URL(string: "\(Self.oauthHost)/api/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(Self.clientId)&grant_type=refresh_token&refresh_token=\(refreshToken.refreshToken)"
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw .unknown
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw .notAuthenticated
        }

        if httpResponse.statusCode != 200 {
            let message = String(data: data, encoding: .utf8)
            throw .api(code: "HTTP_\(httpResponse.statusCode)", message: message)
        }

        do {
            var token = try decoder.decode(OAuthToken.self, from: data)
            token.normalize()
            // 部分服务端刷新时不返回新的 refresh_token，保留旧的以保证后续仍可刷新。
            if token.refreshToken.isEmpty {
                token.refreshToken = refreshToken.refreshToken
            }
            return token
        } catch {
            throw .decoding(error)
        }
    }

    /// 强制刷新 access token，用于 API 返回 401 时主动重试一次。
    func forceRefresh() async throws(ProviderError) -> String {
        guard let token = KeychainStorage.shared.kimiToken() else {
            throw .notAuthenticated
        }
        let refreshed = try await refreshAccessToken(token)
        KeychainStorage.shared.setKimiToken(refreshed)
        inMemoryToken = refreshed
        return refreshed.accessToken
    }
}

// MARK: - Models

struct OAuthToken: Codable, Sendable {
    let accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval?
    let expiresIn: TimeInterval?
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }

    mutating func normalize(issuedAt: TimeInterval = Date().timeIntervalSince1970) {
        // 服务端有时只返回 expires_in，需要根据签发时间计算 expires_at。
        if expiresAt == nil, let expiresIn, expiresIn > 0 {
            expiresAt = issuedAt + expiresIn
        }
    }

    func isExpired(withBuffer bufferSeconds: TimeInterval) -> Bool {
        guard let expiresAt else { return false }
        return Date().timeIntervalSince1970 + bufferSeconds >= expiresAt
    }
}

struct DeviceAuthorization: Codable, Sendable, Identifiable {
    var id: String { deviceCode }

    let userCode: String
    let deviceCode: String
    let verificationUri: String
    let verificationUriComplete: String
    let expiresIn: TimeInterval?
    let interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct OAuthErrorResponse: Codable, Sendable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
