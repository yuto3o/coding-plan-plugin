import Foundation

/// 单个配额维度（本周/功能/频限/余额等）
struct Quota: Codable, Sendable {
    let limit: String
    let used: String
    let remaining: String
    let resetTime: Date?

    init(limit: String, used: String? = nil, remaining: String? = nil, resetTime: Date? = nil) {
        self.limit = limit
        self.used = used ?? "-"
        self.remaining = remaining ?? "-"
        self.resetTime = resetTime
    }

    init(value: Int64, unit: String = "") {
        self.limit = "-"
        self.used = "-"
        self.remaining = Self.format(value: value) + (unit.isEmpty ? "" : " \(unit)")
        self.resetTime = nil
    }

    var limitValue: Int { Int(limit) ?? 0 }
    var usedValue: Int { Int(used) ?? 0 }
    var remainingValue: Int { Int(remaining) ?? 0 }

    var usedPercent: Double {
        guard limitValue > 0 else { return 0 }
        return Double(usedValue) / Double(limitValue)
    }

    static func format(value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        if abs(value) >= 1_000_000 {
            formatter.multiplier = 0.000_001
            formatter.positiveSuffix = "M"
            formatter.negativeSuffix = "M"
        } else if abs(value) >= 1_000 {
            formatter.multiplier = 0.001
            formatter.positiveSuffix = "K"
            formatter.negativeSuffix = "K"
        }
        return formatter.string(from: NSNumber(value: Double(value))) ?? String(value)
    }

    enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime = "resetTime"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try container.decodeIfPresent(String.self, forKey: .limit) ?? "-"
        used = try container.decodeIfPresent(String.self, forKey: .used) ?? "-"
        remaining = try container.decodeIfPresent(String.self, forKey: .remaining) ?? "-"
        resetTime = try container.decodeIfPresent(Date.self, forKey: .resetTime)
    }
}

/// 频限窗口描述
struct RateLimitWindow: Codable, Sendable {
    let duration: Int
    let timeUnit: String

    init(duration: Int = 300, timeUnit: String = "TIME_UNIT_MINUTE") {
        self.duration = duration
        self.timeUnit = timeUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intDuration = try? container.decode(Int.self, forKey: .duration) {
            self.duration = intDuration
        } else if let stringDuration = try? container.decode(String.self, forKey: .duration),
                  let parsed = Int(stringDuration) {
            self.duration = parsed
        } else {
            self.duration = 300
        }
        self.timeUnit = (try? container.decode(String.self, forKey: .timeUnit)) ?? "TIME_UNIT_MINUTE"
    }

    var localizedDescription: String {
        switch timeUnit {
        case "TIME_UNIT_MINUTE":
            if duration >= 60 && duration % 60 == 0 {
                return "\(duration / 60)h"
            }
            return "\(duration)m"
        case "TIME_UNIT_HOUR":
            return "\(duration)h"
        case "TIME_UNIT_DAY":
            return "\(duration)d"
        default:
            return "\(duration) \(timeUnit)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case duration, timeUnit
    }
}

/// 单条频限明细
struct RateLimit: Codable, Sendable, Identifiable {
    var id = UUID()
    let window: RateLimitWindow
    let detail: Quota

    init(window: RateLimitWindow = RateLimitWindow(), detail: Quota = Quota(limit: "-")) {
        self.window = window
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.window = (try? container.decode(RateLimitWindow.self, forKey: .window)) ?? RateLimitWindow()
        self.detail = (try? container.decode(Quota.self, forKey: .detail)) ?? Quota(limit: "-")
    }

    enum CodingKeys: String, CodingKey {
        case window, detail
    }
}

/// 某一 Feature 的用量聚合（Kimi 风格）
struct FeatureUsage: Codable, Sendable {
    let scope: String
    let detail: Quota
    let limits: [RateLimit]
}

/// 单模型用量
struct ModelUsage: Codable, Sendable, Identifiable {
    var id = UUID()
    let modelName: String
    let quotaUsed: Int64
    let promptTokens: Int64
    let completionTokens: Int64
    let requestCount: Int

    var totalTokens: Int64 { promptTokens + completionTokens }

    enum CodingKeys: String, CodingKey {
        case modelName, quotaUsed, promptTokens, completionTokens, requestCount
    }
}

/// 某一周期/维度的用量汇总
struct UsageBreakdown: Codable, Sendable, Identifiable {
    var id = UUID()
    let title: String
    let quotaUsed: Int64
    /// 该周期对应的总额度（充值型平台用）， nil 表示不适用。
    let limit: Int64?
    let promptTokens: Int64
    let completionTokens: Int64
    let requestCount: Int
    let modelUsages: [ModelUsage]

    var totalTokens: Int64 { promptTokens + completionTokens }
    var remaining: Int64 { max(0, (limit ?? 0) - quotaUsed) }

    init(
        title: String,
        quotaUsed: Int64,
        limit: Int64? = nil,
        promptTokens: Int64,
        completionTokens: Int64,
        requestCount: Int,
        modelUsages: [ModelUsage]
    ) {
        self.title = title
        self.quotaUsed = quotaUsed
        self.limit = limit
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.requestCount = requestCount
        self.modelUsages = modelUsages
    }

    enum CodingKeys: String, CodingKey {
        case title, quotaUsed, limit, promptTokens, completionTokens, requestCount, modelUsages
    }
}

/// Provider 返回的统一用量模型
struct PlanUsage: Codable, Sendable {
    let providerID: String
    let updatedAt: Date

    // Kimi 套餐型
    let featureUsages: [FeatureUsage]
    let totalQuota: Quota?

    // 充值型（New API 等）
    let balance: Quota?
    let totalUsage: UsageBreakdown?
    let periods: [UsageBreakdown]

    init(
        providerID: String,
        updatedAt: Date = Date(),
        featureUsages: [FeatureUsage] = [],
        totalQuota: Quota? = nil,
        balance: Quota? = nil,
        totalUsage: UsageBreakdown? = nil,
        periods: [UsageBreakdown] = []
    ) {
        self.providerID = providerID
        self.updatedAt = updatedAt
        self.featureUsages = featureUsages
        self.totalQuota = totalQuota
        self.balance = balance
        self.totalUsage = totalUsage
        self.periods = periods
    }

    /// 取首个 FEATURE_CODING 用量作为 Coding 维度
    var codingUsage: FeatureUsage? {
        featureUsages.first { $0.scope == "FEATURE_CODING" }
    }

    /// 是否有充值型数据
    var hasCreditData: Bool {
        balance != nil || totalUsage != nil || !periods.isEmpty
    }
}
