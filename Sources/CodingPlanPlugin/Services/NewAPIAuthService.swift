import Foundation

/// 管理 New API 类型服务（cctq.ai / ikuncode.cc 等）的认证信息。
/// 保存 access_token 与对应的 user_id（New-Api-User 鉴权需要两者配合）。
/// 把两个值合并为单个 Keychain item；并在首次需要时统一加载，运行期间全程复用内存缓存。
actor NewAPIAuthService {
    private let baseURL: String
    private let credentialsAccount: String
    private let legacyTokenAccount: String
    private let legacyUserIDAccount: String

    /// 全局单例缓存：同一 baseURL 复用同一个认证服务，确保 Keychain 只读一次。
    nonisolated(unsafe) private static var sharedCache: [String: NewAPIAuthService] = [:]
    nonisolated(unsafe) private static var cacheLock = NSLock()

    /// 内存缓存，避免频繁读取 Keychain。
    nonisolated(unsafe) private var cachedToken: String?
    nonisolated(unsafe) private var cachedUserID: String?
    nonisolated(unsafe) private var didLoad = false
    /// 保证多个并发调用者不会同时去读取 Keychain，避免重复弹窗。
    nonisolated(unsafe) private var loadLock = NSLock()

    static func service(for baseURL: String) -> NewAPIAuthService {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = sharedCache[baseURL] {
            return existing
        }
        let service = NewAPIAuthService(baseURL: baseURL)
        sharedCache[baseURL] = service
        return service
    }

    init(baseURL: String) {
        self.baseURL = baseURL
        let host = URL(string: baseURL)?.host ?? baseURL
        self.credentialsAccount = "newapi.\(host).credentials"
        self.legacyTokenAccount = "newapi.\(host).access_token"
        self.legacyUserIDAccount = "newapi.\(host).user_id"
    }

    // MARK: - Public accessors

    nonisolated var accessToken: String? {
        get {
            ensureLoaded()
            return cachedToken
        }
        set {
            cachedToken = newValue
            didLoad = true
            syncToKeychain()
        }
    }

    nonisolated var userID: String? {
        get {
            ensureLoaded()
            return cachedUserID
        }
        set {
            cachedUserID = newValue
            didLoad = true
            syncToKeychain()
        }
    }

    nonisolated var isAuthenticated: Bool {
        accessToken != nil && userID != nil
    }

    nonisolated func clear() {
        cachedToken = nil
        cachedUserID = nil
        didLoad = true
        try? KeychainStorage.shared.delete(account: credentialsAccount)
        try? KeychainStorage.shared.delete(account: legacyTokenAccount)
        try? KeychainStorage.shared.delete(account: legacyUserIDAccount)
    }

    // MARK: - Internal helpers

    /// 确保已从 Keychain 加载过一次。任一 getter 都会触发全量加载，
    /// 加载完成后两个字段都可用缓存，本次运行不再访问 Keychain。
    private nonisolated func ensureLoaded() {
        if didLoad {
            return
        }
        loadLock.lock()
        defer { loadLock.unlock() }
        if didLoad {
            return
        }
        let loaded = loadCredentials()
        cachedToken = loaded?.token
        cachedUserID = loaded?.userID
        didLoad = true
    }

    private nonisolated func loadCredentials() -> (token: String, userID: String)? {
        // 1. 尝试新格式（单个 Keychain item）。
        if let combined = try? KeychainStorage.shared.get(account: credentialsAccount) {
            return parse(combined)
        }

        // 2. 兼容旧格式：分别读取 token 和 user_id，并迁移到新格式。
        guard let token = try? KeychainStorage.shared.get(account: legacyTokenAccount),
              let userID = try? KeychainStorage.shared.get(account: legacyUserIDAccount) else {
            return nil
        }

        let migrated = serialize(token: token, userID: userID)
        try? KeychainStorage.shared.set(migrated, account: credentialsAccount)
        try? KeychainStorage.shared.delete(account: legacyTokenAccount)
        try? KeychainStorage.shared.delete(account: legacyUserIDAccount)
        return (token, userID)
    }

    /// 只有当 token 和 userID 都具备时才写入 Keychain；否则只保留在内存缓存。
    /// 这允许调用方分两次设置 accessToken/userID，第二次设置时自动合并持久化。
    private nonisolated func syncToKeychain() {
        guard let token = cachedToken, !token.isEmpty,
              let userID = cachedUserID, !userID.isEmpty else {
            return
        }
        let combined = serialize(token: token, userID: userID)
        try? KeychainStorage.shared.set(combined, account: credentialsAccount)
        // 迁移完成后清理旧格式，避免残留。
        try? KeychainStorage.shared.delete(account: legacyTokenAccount)
        try? KeychainStorage.shared.delete(account: legacyUserIDAccount)
    }

    // MARK: - Serialization

    /// 使用 JSON 序列化，避免分隔符与内容冲突。
    private nonisolated func serialize(token: String, userID: String) -> String {
        let dict: [String: String] = ["t": token, "u": userID]
        guard let data = try? JSONEncoder().encode(dict),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private nonisolated func parse(_ combined: String) -> (token: String, userID: String)? {
        guard let data = combined.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let token = dict["t"], !token.isEmpty,
              let userID = dict["u"], !userID.isEmpty else {
            return nil
        }
        return (token, userID)
    }
}
