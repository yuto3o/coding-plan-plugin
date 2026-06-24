import Foundation
import SwiftUI

/// 全局应用状态，用于驱动菜单栏标题等跨视图行为。
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var lastUsage: PlanUsage?
    @Published var lastError: ProviderError?

    private init() {}

    /// 菜单栏图标旁显示的简短标题。
    /// - 未登录或出错：空
    /// - 用量 <= 50%：显示百分比（如 "32%"）
    /// - 用量 > 50%：显示 ⚠️ 百分比（如 "⚠️ 87%"）
    var menuBarTitle: String {
        guard ProviderManager.shared.currentProvider?.isAuthenticated == true,
              lastError == nil else {
            return ""
        }

        let percent: Int?
        if let coding = lastUsage?.codingUsage?.detail, coding.limitValue > 0 {
            percent = Int(coding.usedPercent * 100)
        } else if let total = lastUsage?.totalUsage {
            // 充值型：已用额度 / 总额度
            let balance = lastUsage?.balance
            let limitText = balance?.limit ?? "-"
            let limitValue = Int64(limitText.replacingOccurrences(of: ",", with: "")) ?? 0
            if limitValue > 0 {
                percent = Int(Double(total.quotaUsed) / Double(limitValue) * 100)
            } else {
                percent = nil
            }
        } else {
            percent = nil
        }

        guard let percent else { return "" }
        if percent >= 90 {
            return "⚠️ \(percent)%"
        } else if percent >= 50 {
            return "\(percent)%"
        } else {
            return ""
        }
    }
}
