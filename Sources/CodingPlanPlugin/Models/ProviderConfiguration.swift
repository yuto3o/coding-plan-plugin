import Foundation

enum ProviderType: String, Codable, CaseIterable, Sendable {
    case kimi = "kimi"
    case newAPI = "newapi"

    var displayName: String {
        switch self {
        case .kimi: return "Kimi Code"
        case .newAPI: return "New API"
        }
    }
}

/// 单个 Provider 配置，持久化到 UserDefaults。
struct ProviderConfiguration: Codable, Identifiable, Sendable {
    let id: String
    var type: ProviderType
    var name: String
    var baseURL: String?       // New API 必填
    var consolePath: String?   // New API 可选，默认 /console

    init(id: String = UUID().uuidString, type: ProviderType, name: String, baseURL: String? = nil, consolePath: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.baseURL = baseURL
        self.consolePath = consolePath
    }

    /// 内置默认配置
    static let defaults: [ProviderConfiguration] = [
        ProviderConfiguration(type: .kimi, name: "Kimi Code"),
        ProviderConfiguration(type: .newAPI, name: "CCTQ", baseURL: "https://www.cctq.ai"),
        ProviderConfiguration(type: .newAPI, name: "IkunCode", baseURL: "https://api.ikuncode.cc")
    ]
}
