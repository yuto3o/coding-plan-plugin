import Foundation

struct KimiProvider: Provider {
    let id: String
    let name: String
    let consoleURL = URL(string: "https://www.kimi.com/code/console")!

    private let auth: KimiCodeAuthService
    private let api: KimiAPIClient

    init(id: String = "kimi", name: String = "Kimi Code") {
        self.id = id
        self.name = name
        // Kimi Code 全局只有一份 OAuth token，统一使用 shared 实例，
        // 避免不同卡片 id 创建独立的 auth service 导致无法命中 Keychain 中的统一凭证。
        self.auth = KimiCodeAuthService.shared
        self.api = KimiAPIClient(auth: auth)
    }

    var isAuthenticated: Bool {
        auth.isAuthenticated
    }

    func fetchUsage() async throws(ProviderError) -> PlanUsage {
        try await api.fetchUsage()
    }

    func saveAccessToken(_ token: String) {
        // Kimi Code 现在走 OAuth device-code flow，不再接受手动 access_token。
        // 保留默认实现空操作。
    }

    func clearAuthentication() {
        auth.clearAuthentication()
    }
}
