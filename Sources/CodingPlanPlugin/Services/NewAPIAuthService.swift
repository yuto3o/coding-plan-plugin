import Foundation

/// 管理 New API 类型服务的认证信息。
///
/// 把 access_token 与对应的 user_id（New-Api-User 鉴权需要两者配合）合并到统一
/// Keychain item 中；运行时全程复用内存缓存，避免反复读取 Keychain。
actor NewAPIAuthService {
    private let baseURL: String

    /// 全局单例缓存：同一 baseURL 复用同一个认证服务，确保 Keychain 只读一次。
    nonisolated(unsafe) private static var sharedCache: [String: NewAPIAuthService] = [:]
    nonisolated(unsafe) private static var cacheLock = NSLock()

    /// 内存缓存，避免频繁读取 Keychain。
    nonisolated(unsafe) private var cachedToken: String?
    nonisolated(unsafe) private var cachedUserID: String?
    nonisolated(unsafe) private var cachedIncrementalState: NewAPIIncrementalState?
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

        // 首次初始化时迁移旧格式到统一 Keychain item。
        let host = URL(string: baseURL)?.host ?? baseURL
        let legacyTokenAccount = "newapi.\(host).access_token"
        let legacyUserIDAccount = "newapi.\(host).user_id"
        KeychainStorage.shared.migrateLegacyNewAPIToken(
            account: legacyTokenAccount,
            baseURL: baseURL,
            userIDAccount: legacyUserIDAccount
        )
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

    nonisolated var incrementalState: NewAPIIncrementalState? {
        get {
            ensureLoaded()
            return cachedIncrementalState
        }
        set {
            cachedIncrementalState = newValue
            didLoad = true
            syncIncrementalStateToKeychain()
        }
    }

    nonisolated func clear() {
        cachedToken = nil
        cachedUserID = nil
        cachedIncrementalState = nil
        didLoad = true
        KeychainStorage.shared.removeNewAPICredentials(for: baseURL)
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
        let credentials = KeychainStorage.shared.newAPICredentials(for: baseURL)
        cachedToken = credentials?.token
        cachedUserID = credentials?.userID
        cachedIncrementalState = credentials?.incrementalState
        didLoad = true
    }

    /// 只有当 token 和 userID 都具备时才写入 Keychain；否则只保留在内存缓存。
    /// 这允许调用方分两次设置 accessToken/userID，第二次设置时自动合并持久化。
    private nonisolated func syncToKeychain() {
        guard let token = cachedToken, !token.isEmpty,
              let userID = cachedUserID, !userID.isEmpty else {
            return
        }
        var credentials = KeychainStorage.shared.newAPICredentials(for: baseURL) ?? NewAPICredentials()
        credentials.token = token
        credentials.userID = userID
        if let cachedIncrementalState {
            credentials.incrementalState = cachedIncrementalState
        }
        KeychainStorage.shared.setNewAPICredentials(credentials, for: baseURL)
    }

    private nonisolated func syncIncrementalStateToKeychain() {
        guard let token = cachedToken, !token.isEmpty,
              let userID = cachedUserID, !userID.isEmpty else {
            return
        }
        var credentials = KeychainStorage.shared.newAPICredentials(for: baseURL) ?? NewAPICredentials()
        credentials.token = token
        credentials.userID = userID
        credentials.incrementalState = cachedIncrementalState
        KeychainStorage.shared.setNewAPICredentials(credentials, for: baseURL)
    }
}
