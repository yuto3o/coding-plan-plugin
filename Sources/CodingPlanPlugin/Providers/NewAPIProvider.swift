import Foundation

/// New API（one-api / new-api 衍生）Provider 通用实现。
/// 任意自定义 Base URL 的 New API 平台均可复用此类型。
struct NewAPIProvider: Provider {
    let id: String
    let name: String
    let consoleURL: URL
    let baseURL: String

    private let api: NewAPIClient
    private let auth: NewAPIAuthService

    init(id: String, name: String, baseURL: String, consolePath: String = "/console") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.consoleURL = URL(string: baseURL + consolePath)!
        self.auth = NewAPIAuthService.service(for: baseURL)
        self.api = NewAPIClient(baseURL: baseURL, auth: auth)
    }

    var isAuthenticated: Bool {
        auth.isAuthenticated
    }

    func fetchUsage() async throws(ProviderError) -> PlanUsage {
        let state = auth.incrementalState
        let (usage, newState) = try await api.fetchUsage(incrementalState: state)
        auth.incrementalState = newState
        return usage
    }

    func saveAccessToken(_ token: String, userID: String?) {
        auth.accessToken = token
        auth.userID = userID
    }

    func clearAuthentication() {
        auth.clear()
    }
}
