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

    func fetchUsage(incrementalState: NewAPIIncrementalState?) async throws(ProviderError) -> (PlanUsage, NewAPIIncrementalState) {
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

        // 增量更新：只从上一次成功拉取的时间点之后获取新日志，
        // 避免每次刷新都遍历整月/整周的日志分页。
        let (startTimestamp, endTimestamp, isIncremental) = logFetchRange(incrementalState: incrementalState)

        let logResult = await fetchUserLogs(
            token: token,
            userID: userID,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp
        )
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

        Self.logger.info("NewAPIClient Data sources: isIncremental=\(isIncremental, privacy: .public), newLogItems=\(logItems.count, privacy: .public)")

        return buildPlanUsage(
            user: user,
            logItems: logItems,
            tokens: tokens,
            incrementalState: incrementalState
        )
    }

    private func logFetchRange(incrementalState: NewAPIIncrementalState?) -> (start: Int64, end: Int64, isIncremental: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        let monthStartTS = monthStart.timeIntervalSince1970
        let nextMonthStartTS = Int64(nextMonthStart.timeIntervalSince1970)

        guard let state = incrementalState,
              state.monthlyPeriodStart == monthStartTS,
              let lastFetchAt = state.lastFetchAt else {
            return (Int64(monthStartTS), nextMonthStartTS, false)
        }

        // 增量：从上次最后一条记录的下一秒开始，避免重复统计。
        let incrementalStart = Int64(lastFetchAt) + 1
        return (incrementalStart, nextMonthStartTS, true)
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

    private func fetchUserLogs(token: String, userID: String, startTimestamp: Int64, endTimestamp: Int64) async -> Result<[LogResponse.LogItem], ProviderError> {
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

            // 安全上限，防止异常循环；增量模式下通常几页即可结束。
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
        logItems: [LogResponse.LogItem],
        tokens: [TokenListResponse.Token],
        incrementalState: NewAPIIncrementalState?
    ) -> (PlanUsage, NewAPIIncrementalState) {
        let quota = user.quota ?? 0
        let usedQuota = user.usedQuota ?? 0
        let totalQuota = quota + usedQuota

        // 服务端 logs.created_at 以 UTC 存储，周期边界用 UTC 计算。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let monthStartTS = monthStart.timeIntervalSince1970

        let weekday = calendar.component(.weekday, from: now)
        let daysSinceMonday = (weekday + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: calendar.startOfDay(for: now))!
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let weekStartTS = weekStart.timeIntervalSince1970

        // 继承或重置增量累计数据。
        var monthlyUsed: Int64 = 0
        var weeklyUsed: Int64 = 0
        var weeklyModelUsage: [String: Int64] = [:]
        var lastFetchAt: TimeInterval? = incrementalState?.lastFetchAt

        if let state = incrementalState, state.monthlyPeriodStart == monthStartTS {
            monthlyUsed = state.monthlyUsed
        }
        if let state = incrementalState, state.weeklyPeriodStart == weekStartTS {
            weeklyUsed = state.weeklyUsed
            weeklyModelUsage = state.weeklyModelUsage
        }

        // 累加本次新拉取的日志。
        for item in logItems {
            let itemQuota = item.quota ?? 0
            let itemDate = Date(timeIntervalSince1970: TimeInterval(item.createdAt))

            if itemDate >= monthStart && itemDate < nextMonthStart {
                monthlyUsed += itemQuota
            }
            if itemDate >= weekStart && itemDate < nextWeekStart {
                weeklyUsed += itemQuota
                let modelName = item.modelName ?? "Unknown"
                weeklyModelUsage[modelName, default: 0] += itemQuota
            }

            let ts = TimeInterval(item.createdAt)
            if ts > (lastFetchAt ?? 0) {
                lastFetchAt = ts
            }
        }

        // 按模型用量构造 ModelUsage 数组（本周 Top3 + Other）。
        let sortedModels = weeklyModelUsage
            .map { ModelUsage(modelName: $0.key, quotaUsed: $0.value, promptTokens: 0, completionTokens: 0, requestCount: 0) }
            .sorted { $0.quotaUsed > $1.quotaUsed }
        let top3 = Array(sortedModels.prefix(3))
        let rest = sortedModels.dropFirst(3)
        var weeklyModels = top3
        if !rest.isEmpty {
            let otherUsage = rest.reduce(0) { $0 + $1.quotaUsed }
            weeklyModels.append(ModelUsage(modelName: "Other", quotaUsed: otherUsage, promptTokens: 0, completionTokens: 0, requestCount: 0))
        }

        let monthly = UsageBreakdown(
            title: "本月用量（自然月）",
            quotaUsed: monthlyUsed,
            limit: totalQuota,
            promptTokens: 0,
            completionTokens: 0,
            requestCount: 0,
            modelUsages: []
        )

        let weekly = UsageBreakdown(
            title: "本周用量",
            quotaUsed: weeklyUsed,
            limit: totalQuota,
            promptTokens: 0,
            completionTokens: 0,
            requestCount: 0,
            modelUsages: weeklyModels
        )

        let balanceQuota = Quota(
            limit: formatQuota(totalQuota),
            used: formatQuota(usedQuota),
            remaining: formatQuota(quota)
        )

        // 累计总用量仍使用 /api/user/self 返回的 usedQuota，作为账户维度总量。
        let totalUsage = UsageBreakdown(
            title: "累计用量",
            quotaUsed: usedQuota,
            limit: totalQuota,
            promptTokens: 0,
            completionTokens: 0,
            requestCount: 0,
            modelUsages: sortedModels
        )

        var periods: [UsageBreakdown] = [monthly]
        if !weeklyModels.isEmpty || weeklyUsed > 0 {
            periods.append(weekly)
        }

        let planUsage = PlanUsage(
            providerID: baseURL.host ?? "newapi",
            updatedAt: Date(),
            balance: balanceQuota,
            totalUsage: totalUsage,
            periods: periods
        )

        let newState = NewAPIIncrementalState(
            lastFetchAt: lastFetchAt,
            monthlyPeriodStart: monthStartTS,
            monthlyUsed: monthlyUsed,
            weeklyPeriodStart: weekStartTS,
            weeklyUsed: weeklyUsed,
            weeklyModelUsage: weeklyModelUsage
        )

        return (planUsage, newState)
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

}
