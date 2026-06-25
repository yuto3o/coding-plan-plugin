import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
}

/// 统一 Keychain 凭证存储。
///
/// 所有 Provider（Kimi Code、New API 各站点）的认证数据合并存储在**单个 Keychain item**
///（account = ``KeychainStorage/unifiedAccount``）中，运行时全程使用内存缓存，避免反复读取
/// Keychain 导致多次权限弹窗。
///
/// 数据模型：
/// ```json
/// {
///   "kimi": {
///     "access_token": "...",
///     "refresh_token": "...",
///     "expires_at": 1234567890,
///     "expires_in": 3600,
///     "scope": "...",
///     "token_type": "..."
///   },
///   "newapi": {
///     "https://api.example.com": { "token": "...", "userID": "..." },
///     "https://api.example.org": { "token": "...", "userID": "..." }
///   }
/// }
/// ```
final class KeychainStorage: @unchecked Sendable {
    static let shared = KeychainStorage(service: "com.yangyu.CodingPlanPlugin")
    static let unifiedAccount = "plugin.credentials"

    let service: String

    /// 内存缓存，避免每次读取 Keychain。
    private var _cachedPayload: UnifiedCredentials?
    private var _didLoad = false
    private let _lock = NSLock()

    init(service: String) {
        self.service = service
    }

    // MARK: - Public accessors

    /// 读取 Kimi OAuth token。
    func kimiToken() -> OAuthToken? {
        withLock { payload().kimi }
    }

    /// 写入 Kimi OAuth token。
    func setKimiToken(_ token: OAuthToken?) {
        withLock {
            var payload = self.payload()
            payload.kimi = token
            savePayload(payload)
        }
    }

    /// 读取指定 baseURL 的 NewAPI 凭据。
    func newAPICredentials(for baseURL: String) -> NewAPICredentials? {
        withLock { payload().newAPI[baseURL] }
    }

    /// 写入指定 baseURL 的 NewAPI 凭据。
    func setNewAPICredentials(_ credentials: NewAPICredentials?, for baseURL: String) {
        withLock {
            var payload = self.payload()
            payload.newAPI[baseURL] = credentials
            savePayload(payload)
        }
    }

    /// 删除指定 baseURL 的 NewAPI 凭据。
    func removeNewAPICredentials(for baseURL: String) {
        withLock {
            var payload = self.payload()
            payload.newAPI.removeValue(forKey: baseURL)
            savePayload(payload)
        }
    }

    /// 返回所有已存储凭据的 NewAPI baseURL。
    func allNewAPIBaseURLs() -> [String] {
        withLock { Array(payload().newAPI.keys) }
    }

    /// 清除所有凭证（用于完全退出登录/重置）。
    func clearAll() {
        withLock {
            _cachedPayload = nil
            _didLoad = true
            try? delete(account: Self.unifiedAccount)
        }
    }

    // MARK: - Legacy migration

    /// 将旧格式的独立 Keychain item 迁移到统一格式。
    /// 迁移完成后删除旧 item，避免残留和重复弹窗。
    func migrateLegacyKimiToken(account: String) {
        withLock {
            guard let json = try? legacyGet(account: account),
                  let data = json.data(using: .utf8),
                  let token = try? JSONDecoder().decode(OAuthToken.self, from: data) else {
                return
            }
            var payload = self.payload()
            payload.kimi = token
            savePayload(payload)
            try? delete(account: account)
        }
    }

    func migrateLegacyNewAPIToken(account: String, baseURL: String, userIDAccount: String?) {
        withLock {
            guard let token = try? legacyGet(account: account), !token.isEmpty else { return }
            var payload = self.payload()
            var credentials = payload.newAPI[baseURL] ?? NewAPICredentials()
            credentials.token = token
            if let userIDAccount,
               let userID = try? legacyGet(account: userIDAccount), !userID.isEmpty {
                credentials.userID = userID
                try? delete(account: userIDAccount)
            }
            payload.newAPI[baseURL] = credentials
            savePayload(payload)
            try? delete(account: account)
        }
    }

    // MARK: - Internal helpers

    private func payload() -> UnifiedCredentials {
        if _didLoad, let cached = _cachedPayload {
            return cached
        }
        guard let json = try? legacyGet(account: Self.unifiedAccount),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(UnifiedCredentials.self, from: data) else {
            return UnifiedCredentials()
        }
        _cachedPayload = payload
        _didLoad = true
        return payload
    }

    private func savePayload(_ payload: UnifiedCredentials) {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        _cachedPayload = payload
        _didLoad = true
        try? legacySet(json, account: Self.unifiedAccount)
    }

    private func withLock<T>(_ action: () -> T) -> T {
        _lock.lock()
        defer { _lock.unlock() }
        return action()
    }

    // MARK: - Low-level Keychain primitives

    private func legacySet(_ value: String, account: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw .unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw .unexpectedStatus(status)
        }
    }

    private func legacyGet(account: String) throws(KeychainError) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw .itemNotFound
            }
            throw .unexpectedStatus(status)
        }

        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw .invalidData
        }
        return value
    }

    private func delete(account: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .unexpectedStatus(status)
        }
    }
}

// MARK: - Unified credential models

struct UnifiedCredentials: Codable, Sendable {
    var kimi: OAuthToken?
    var newAPI: [String: NewAPICredentials] = [:]

    enum CodingKeys: String, CodingKey {
        case kimi
        case newAPI = "newapi"
    }
}

struct NewAPICredentials: Codable, Sendable {
    var token: String = ""
    var userID: String = ""
    var incrementalState: NewAPIIncrementalState?

    var isValid: Bool {
        !token.isEmpty && !userID.isEmpty
    }
}

/// New API 用量刷新的增量状态。
///
/// 避免每次刷新都拉取整月/整周的日志明细：只从上一次 `lastFetchAt` 之后拉取新增记录，
/// 累加到已有统计中。当月/周切换时自动重置对应周期累计。
struct NewAPIIncrementalState: Codable, Sendable {
    /// 上次成功拉取日志的最后一条记录时间戳（UTC 秒）。
    var lastFetchAt: TimeInterval?

    /// 当前月度累计周期的起点（UTC 秒）。
    var monthlyPeriodStart: TimeInterval?
    /// 月度累计用量。
    var monthlyUsed: Int64 = 0

    /// 当前周累计周期的起点（UTC 秒）。
    var weeklyPeriodStart: TimeInterval?
    /// 周累计用量。
    var weeklyUsed: Int64 = 0

    /// 按模型累计的用量（本周）。
    var weeklyModelUsage: [String: Int64] = [:]
}
