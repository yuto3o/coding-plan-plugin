import Foundation
import os.log

/// New API（one-api / new-api 衍生）通用客户端
actor NewAPIClient {
    private static let logger = Logger(subsystem: "com.codingplan.plugin", category: "NewAPIClient")
    private let baseURL: URL
    private let auth: NewAPIAuthService
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: String, auth: NewAPIAuthService) {
        guard let url = URL(string: baseURL) else {
            fatalError("Invalid New API base URL: \(baseURL)")
        }
        self.baseURL = url
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Responses

    struct UserSelfResponse: Decodable, Sendable {
        let success: Bool
        let message: String?
        let data: User?

        struct User: Decodable, Sendable {
            let id: Int?
            let username: String?
            let displayName: String?
            let group: String?
            let quota: Int64?
            let usedQuota: Int64?
            let requestCount: Int?

            enum CodingKeys: String, CodingKey {
                case id, username
                case displayName = "display_name"
                case group
                case quota
                case usedQuota = "used_quota"
                case requestCount = "request_count"
            }
        }
    }


    /// /api/data/self 返回的配额明细（按小时/模型聚合）。
    struct QuotaDataResponse: Decodable, Sendable {
        let success: Bool
        let message: String?
        let data: [QuotaDataItem]?

        struct QuotaDataItem: Decodable, Sendable {
            let createdAt: Int64
            let modelName: String?
            let quota: Int64?
            let tokenUsed: Int64?
            let count: Int?

            enum CodingKeys: String, CodingKey {
                case createdAt = "created_at"
                case modelName = "model_name"
                case quota
                case tokenUsed = "token_used"
                case count
            }
        }
    }

    /// /api/log/self 返回的消费日志明细（fallback 数据源）。
    struct LogResponse: Decodable, Sendable {
        let success: Bool
        let message: String?
        let data: LogPageData?

        struct LogPageData: Decodable, Sendable {
            let items: [LogItem]?
            let total: Int?

            enum CodingKeys: String, CodingKey {
                case items, total
            }
        }

        struct LogItem: Decodable, Sendable {
            let createdAt: Int64
            let modelName: String?
            let quota: Int64?
            let promptTokens: Int64?
            let completionTokens: Int64?

            enum CodingKeys: String, CodingKey {
                case createdAt = "created_at"
                case modelName = "model_name"
                case quota
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
    }

    struct TokenListResponse: Decodable, Sendable {
        let success: Bool
        let message: String?
        let data: TokenListData?

        struct TokenListData: Decodable, Sendable {
            let items: [Token]?
            let total: Int?

            enum CodingKeys: String, CodingKey {
                case items, total
            }
        }

        struct Token: Decodable, Sendable {
            let id: Int?
            let name: String?
            let usedQuota: Int64?
            let remainQuota: Int64?
            let unlimitedQuota: Bool?
            let requestCount: Int?

            enum CodingKeys: String, CodingKey {
                case id, name
                case usedQuota = "used_quota"
                case remainQuota = "remain_quota"
                case unlimitedQuota = "unlimited_quota"
                case requestCount = "request_count"
            }
        }
    }

    // MARK: - API

    func fetchUsage() async throws(ProviderError) -> PlanUsage {
        guard let token = auth.accessToken, let userID = auth.userID else {
            throw .notAuthenticated
        }

        let selfResult = await fetchUserSelf(token: token, userID: userID)
        guard case .success(let user) = selfResult else {
            if case .failure(let error) = selfResult {
                throw error
            }
            throw .unknown
        }

        // /api/data/self 有延迟，可能缺少最近几天的数据；
        // /api/log/self 是实时消费日志。两者都拿，分别用于本月/本周聚合。
        let quotaDataResult = await fetchQuotaData(token: token, userID: userID)
        let quotaItems: [QuotaDataResponse.QuotaDataItem]
        switch quotaDataResult {
        case .success(let items):
            quotaItems = items
        case .failure:
            quotaItems = []
        }

        let logResult = await fetchUserLogs(token: token, userID: userID)
        let logItems: [LogResponse.LogItem]
        switch logResult {
        case .success(let items):
            logItems = items
        case .failure:
            logItems = []
        }

        let tokenListResult = await fetchTokenList(token: token, userID: userID)
        let tokens: [TokenListResponse.Token]
        switch tokenListResult {
        case .success(let items):
            tokens = items
        case .failure:
            tokens = []
        }

        return buildPlanUsage(
            user: user,
            quotaItems: quotaItems,
            logItems: logItems,
            tokens: tokens
        )
    }

    // MARK: - Private

    private func fetchUserSelf(token: String, userID: String) async -> Result<UserSelfResponse.User, ProviderError> {
        let result: UserSelfResponse
        do {
            result = try await request(path: "/api/user/self", method: "GET", token: token, userID: userID)
        } catch {
            return .failure(error)
        }

        guard result.success == true, let user = result.data else {
            return .failure(.api(code: "api_error", message: result.message ?? "获取用户信息失败"))
        }
        return .success(user)
    }

    private func fetchQuotaData(token: String, userID: String) async -> Result<[QuotaDataResponse.QuotaDataItem], ProviderError> {
        // 服务端 quota_data.created_at 以 UTC 存储，因此时间范围也用 UTC 计算。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        let startTimestamp = Int64(monthStart.timeIntervalSince1970)
        let endTimestamp = Int64(nextMonthStart.timeIntervalSince1970)

        let path = "/api/data/self?start_timestamp=\(startTimestamp)&end_timestamp=\(endTimestamp)"
        let result: QuotaDataResponse
        do {
            result = try await request(path: path, method: "GET", token: token, userID: userID)
        } catch {
            return .failure(error)
        }

        guard result.success == true else {
            return .failure(.api(code: "api_error", message: result.message ?? "获取用量统计失败"))
        }
        return .success(result.data ?? [])
    }

    private func fetchUserLogs(token: String, userID: String) async -> Result<[LogResponse.LogItem], ProviderError> {
        // 服务端 logs.created_at 以 UTC 存储，时间范围用 UTC 计算。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        let startTimestamp = Int64(monthStart.timeIntervalSince1970)
        let endTimestamp = Int64(nextMonthStart.timeIntervalSince1970)

        var allItems: [LogResponse.LogItem] = []
        var page = 1
        let pageSize = 100

        while true {
            let path = "/api/log/self?type=2&start_timestamp=\(startTimestamp)&end_timestamp=\(endTimestamp)&p=\(page)&page_size=\(pageSize)"
            let result: LogResponse
            do {
                result = try await request(path: path, method: "GET", token: token, userID: userID)
            } catch {
                return .failure(error)
            }

            guard result.success == true else {
                return .failure(.api(code: "api_error", message: result.message ?? "获取消费日志失败"))
            }

            let items = result.data?.items ?? []
            allItems.append(contentsOf: items)

            let total = result.data?.total ?? 0
            if allItems.count >= total || items.isEmpty {
                break
            }
            page += 1

            // 安全上限，防止异常循环
            if page > 50 {
                break
            }
        }

        return .success(allItems)
    }

    private func fetchTokenList(token: String, userID: String) async -> Result<[TokenListResponse.Token], ProviderError> {
        let result: TokenListResponse
        do {
            result = try await request(path: "/api/token/?p=1&size=100", method: "GET", token: token, userID: userID)
        } catch {
            return .failure(error)
        }

        guard result.success == true else {
            return .failure(.api(code: "api_error", message: result.message ?? "获取 Token 列表失败"))
        }
        return .success(result.data?.items ?? [])
    }

    private func makeURL(path: String) -> URL {
        // path 可能包含 query string（如 /api/data/self?x=1），
        // appendingPathComponent 会把 ? 编码成 %3F，导致服务端 404。
        // 这里直接做字符串拼接，保留 query string 原样。
        let baseString = baseURL.absoluteString
        let hasTrailingSlash = baseString.hasSuffix("/")
        let hasLeadingSlash = path.hasPrefix("/")

        let fullString: String
        if hasTrailingSlash && hasLeadingSlash {
            fullString = baseString + String(path.dropFirst())
        } else if !hasTrailingSlash && !hasLeadingSlash {
            fullString = baseString + "/" + path
        } else {
            fullString = baseString + path
        }

        return URL(string: fullString) ?? baseURL.appendingPathComponent(path)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        token: String,
        userID: String,
        body: Encodable? = nil
    ) async throws(ProviderError) -> T {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userID, forHTTPHeaderField: "New-Api-User")

        Self.logger.info("NewAPIClient Request: \(url.absoluteString, privacy: .public)")

        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw .decoding(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("Network error for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Invalid response for \(url.absoluteString, privacy: .public)")
            throw .unknown
        }

        let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
        Self.logger.info("NewAPIClient Response \(httpResponse.statusCode, privacy: .public) for \(url.absoluteString, privacy: .public): \(preview, privacy: .public)")

        if httpResponse.statusCode == 401 {
            throw .notAuthenticated
        }

        if httpResponse.statusCode >= 400 {
            throw .api(code: "HTTP_\(httpResponse.statusCode)", message: preview)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .decoding(
                NSError(
                    domain: "NewAPIClient",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription)\n\nResponse preview:\n\(preview)"
                    ]
                )
            )
        }
    }

    private func buildPlanUsage(
        user: UserSelfResponse.User,
        quotaItems: [QuotaDataResponse.QuotaDataItem],
        logItems: [LogResponse.LogItem],
        tokens: [TokenListResponse.Token]
    ) -> PlanUsage {
        let quota = user.quota ?? 0
        let usedQuota = user.usedQuota ?? 0
        let totalQuota = quota + usedQuota

        // /api/log/self 是实时数据；/api/data/self 有延迟。把日志转成统一格式备用。
        let logQuotaItems = logItems.map {
            QuotaDataResponse.QuotaDataItem(
                createdAt: $0.createdAt,
                modelName: $0.modelName,
                quota: $0.quota,
                tokenUsed: ($0.promptTokens ?? 0) + ($0.completionTokens ?? 0),
                count: 1
            )
        }

        // 按模型聚合（优先使用 /api/data/self 全量数据）
        var modelMap: [String: ModelUsage] = [:]
        for item in quotaItems {
            let modelName = item.modelName ?? "Unknown"
            let existing = modelMap[modelName]
            let tokenUsed = item.tokenUsed ?? 0
            modelMap[modelName] = ModelUsage(
                modelName: modelName,
                quotaUsed: (existing?.quotaUsed ?? 0) + (item.quota ?? 0),
                promptTokens: 0,
                completionTokens: (existing?.completionTokens ?? 0) + tokenUsed,
                requestCount: (existing?.requestCount ?? 0) + (item.count ?? 0)
            )
        }
        let allModelUsages = modelMap.values.sorted { $0.quotaUsed > $1.quotaUsed }

        // 服务端 quota_data.created_at / logs.created_at 以 UTC 存储，过滤周期也用 UTC。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()

        Self.logger.info("NewAPIClient Data sources: quotaItems=\(quotaItems.count, privacy: .public), logItems=\(logItems.count, privacy: .public)")

        // 自然月聚合：使用实时消费日志 /api/log/self
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let rawMonthly = aggregate(title: "本月用量（自然月）", quotaItems: logQuotaItems, from: monthStart, to: nextMonthStart)
        let monthlyUsed = rawMonthly.quotaUsed

        let monthly = UsageBreakdown(
            title: rawMonthly.title,
            quotaUsed: monthlyUsed,
            limit: totalQuota,
            promptTokens: rawMonthly.promptTokens,
            completionTokens: rawMonthly.completionTokens,
            requestCount: rawMonthly.requestCount,
            modelUsages: rawMonthly.modelUsages
        )

        // 余额：保留兼容旧布局
        let balanceQuota = Quota(
            limit: formatQuota(totalQuota),
            used: formatQuota(usedQuota),
            remaining: formatQuota(quota)
        )

        // 本周聚合（自然周，周一为起点）：从自然月日志中过滤
        let weekday = calendar.component(.weekday, from: now)
        let daysSinceMonday = (weekday + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: calendar.startOfDay(for: now))!
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let weekly = aggregate(title: "本周用量", quotaItems: logQuotaItems, from: weekStart, to: nextWeekStart)
        let weeklyTop3 = top3Breakdown(from: weekly)

        Self.logger.info("NewAPIClient Weekly aggregation: sourceCount=\(logQuotaItems.count, privacy: .public), filteredCount=\(weekly.modelUsages.count, privacy: .public), quotaUsed=\(weekly.quotaUsed, privacy: .public)")

        // 累计总用量（保留在 totalUsage 中，便于扩展展示）
        let totalUsage = UsageBreakdown(
            title: "累计用量",
            quotaUsed: usedQuota,
            limit: totalQuota,
            promptTokens: allModelUsages.reduce(0) { $0 + $1.promptTokens },
            completionTokens: allModelUsages.reduce(0) { $0 + $1.completionTokens },
            requestCount: allModelUsages.reduce(0) { $0 + $1.requestCount },
            modelUsages: allModelUsages
        )

        var periods: [UsageBreakdown] = []
        periods.append(monthly)
        if !weeklyTop3.modelUsages.isEmpty || weeklyTop3.quotaUsed > 0 {
            periods.append(weeklyTop3)
        }

        return PlanUsage(
            providerID: baseURL.host ?? "newapi",
            updatedAt: Date(),
            balance: balanceQuota,
            totalUsage: totalUsage,
            periods: periods
        )
    }

    private func top3Breakdown(from breakdown: UsageBreakdown) -> UsageBreakdown {
        let sorted = breakdown.modelUsages.sorted { $0.quotaUsed > $1.quotaUsed }
        let top3 = Array(sorted.prefix(3))
        let rest = sorted.dropFirst(3)
        let other: ModelUsage? = rest.isEmpty ? nil : ModelUsage(
            modelName: "Other",
            quotaUsed: rest.reduce(0) { $0 + $1.quotaUsed },
            promptTokens: 0,
            completionTokens: 0,
            requestCount: rest.reduce(0) { $0 + $1.requestCount }
        )
        var models = top3
        if let other {
            models.append(other)
        }
        return UsageBreakdown(
            title: breakdown.title,
            quotaUsed: breakdown.quotaUsed,
            promptTokens: breakdown.promptTokens,
            completionTokens: breakdown.completionTokens,
            requestCount: breakdown.requestCount,
            modelUsages: models
        )
    }

    private func formatQuota(_ value: Int64) -> String {
        let doubleValue = Double(value)
        let absValue = abs(doubleValue)

        if absValue >= 1_000_000 {
            let m = doubleValue / 1_000_000
            return formatCompact(m, suffix: "M")
        } else if absValue >= 1_000 {
            let k = doubleValue / 1_000
            return formatCompact(k, suffix: "K")
        } else {
            return String(value)
        }
    }

    private func formatCompact(_ value: Double, suffix: String) -> String {
        if value == floor(value) {
            return String(format: "%.0f%@", value, suffix)
        } else {
            return String(format: "%.1f%@", value, suffix)
        }
    }

    private func aggregate(
        title: String,
        quotaItems: [QuotaDataResponse.QuotaDataItem],
        from: Date,
        to: Date,
        limit: Int64? = nil
    ) -> UsageBreakdown {
        let filtered = quotaItems.filter {
            let itemDate = Date(timeIntervalSince1970: TimeInterval($0.createdAt))
            return itemDate >= from && itemDate < to
        }

        var modelMap: [String: ModelUsage] = [:]
        for item in filtered {
            let modelName = item.modelName ?? "Unknown"
            let existing = modelMap[modelName]
            let tokenUsed = item.tokenUsed ?? 0
            modelMap[modelName] = ModelUsage(
                modelName: modelName,
                quotaUsed: (existing?.quotaUsed ?? 0) + (item.quota ?? 0),
                promptTokens: 0,
                completionTokens: (existing?.completionTokens ?? 0) + tokenUsed,
                requestCount: (existing?.requestCount ?? 0) + (item.count ?? 0)
            )
        }
        let models = modelMap.values.sorted { $0.quotaUsed > $1.quotaUsed }

        return UsageBreakdown(
            title: title,
            quotaUsed: filtered.reduce(0) { $0 + ($1.quota ?? 0) },
            limit: limit,
            promptTokens: 0,
            completionTokens: filtered.reduce(0) { $0 + ($1.tokenUsed ?? 0) },
            requestCount: filtered.reduce(0) { $0 + ($1.count ?? 0) },
            modelUsages: models
        )
    }
}
