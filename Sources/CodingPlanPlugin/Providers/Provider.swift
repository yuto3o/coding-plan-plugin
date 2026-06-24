import Foundation
import AppKit

enum ProviderError: Error, CustomStringConvertible {
    case notAuthenticated
    case network(Error)
    case decoding(Error)
    case api(code: String, message: String?)
    case unknown

    var description: String {
        switch self {
        case .notAuthenticated:
            return "未登录，请先在设置中登录。"
        case .network(let error):
            return "网络错误：\(error.localizedDescription)"
        case .decoding(let error):
            return "解析失败：\(error.localizedDescription)"
        case .api(let code, let message):
            return "接口错误 [\(code)]：\(message ?? "无详细说明")"
        case .unknown:
            return "未知错误"
        }
    }
}

protocol Provider: Sendable {
    var id: String { get }
    var name: String { get }
    var consoleURL: URL { get }

    /// 是否已完成认证（例如已保存 access_token）
    var isAuthenticated: Bool { get }

    /// 拉取最新用量
    func fetchUsage() async throws(ProviderError) -> PlanUsage

    /// 打开控制台页面（用于登录或查看详情）
    func openConsole() async throws(ProviderError)

    /// 保存手动输入的 access token（主要给 New API 类型使用）。
    /// New API 还需要 userID 配合鉴权。
    /// 默认实现为空。
    func saveAccessToken(_ token: String, userID: String?)

    /// 清除当前保存的认证信息。
    /// 默认实现为空。
    func clearAuthentication()
}

extension Provider {
    func openConsole() async throws(ProviderError) {
        _ = await MainActor.run {
            NSWorkspace.shared.open(consoleURL)
        }
    }

    func saveAccessToken(_ token: String, userID: String?) {}
    func clearAuthentication() {}
}
