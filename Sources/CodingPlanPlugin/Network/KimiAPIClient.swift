import Foundation

/// Kimi Code /coding/v1/usages 用量接口客户端。
/// 复用 Kimi Code CLI 的 OAuth token（scope=kimi-code），无需 user-center access_token。
actor KimiAPIClient {
    static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!
    static let maxRetries = 3
    static let retryDelay: UInt64 = 500_000_000 // 0.5s

    private let auth: KimiCodeAuthService
    private let session: URLSession
    private let decoder: JSONDecoder
    private var isFetching = false

    init(auth: KimiCodeAuthService = .shared) {
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = Self.makeDecoder()
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        return decoder
    }

    // MARK: - Response models

    struct UsagesResponse: Decodable, Sendable {
        let usage: Quota?
        let limits: [RateLimit]?
        let totalQuota: Quota?

        enum CodingKeys: String, CodingKey {
            case usage
            case limits
            case totalQuota = "totalQuota"
        }
    }

    struct ErrorResponse: Decodable, Sendable {
        let code: String
        let details: [ErrorDetail]?

        struct ErrorDetail: Decodable, Sendable {
            let type: String?
            let debug: ErrorDebug?

            struct ErrorDebug: Decodable, Sendable {
                let reason: String?
            }
        }
    }

    // MARK: - API

    func fetchUsage() async throws(ProviderError) -> PlanUsage {
        guard !isFetching else {
            throw .api(code: "request_in_flight", message: "已有请求正在进行")
        }

        isFetching = true
        defer { isFetching = false }

        do {
            let token = try await auth.accessToken()
            return try await performFetch(accessToken: token, allowRetry: true)
        } catch {
            throw error
        }
    }

    private func performFetch(accessToken: String, allowRetry: Bool) async throws(ProviderError) -> PlanUsage {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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
            // access_token 可能刚过期，尝试强制刷新一次并重试。
            guard allowRetry else {
                throw .notAuthenticated
            }
            let newToken = try await auth.forceRefresh()
            return try await performFetch(accessToken: newToken, allowRetry: false)
        }

        if httpResponse.statusCode >= 400 {
            let errorPayload: ErrorResponse?
            do {
                errorPayload = try decoder.decode(ErrorResponse.self, from: data)
            } catch {
                errorPayload = nil
            }
            let code = errorPayload?.code ?? "HTTP_\(httpResponse.statusCode)"
            let reason = errorPayload?.details?.first?.debug?.reason
            throw .api(code: code, message: reason)
        }

        do {
            let payload = try decoder.decode(UsagesResponse.self, from: data)
            let featureUsage = payload.usage.map {
                FeatureUsage(scope: "FEATURE_CODING", detail: $0, limits: payload.limits ?? [])
            }
            return PlanUsage(
                providerID: "kimi",
                updatedAt: Date(),
                featureUsages: featureUsage.map { [$0] } ?? [],
                totalQuota: payload.totalQuota
            )
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<binary>"
            let truncated = String(bodyPreview.prefix(800))
            throw .decoding(
                NSError(
                    domain: "KimiAPIClient",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription)\n\nResponse preview:\n\(truncated)"
                    ]
                )
            )
        }
    }
}
