import Foundation

/// 单个订阅的用量快照，包含最新用量、加载状态和错误信息。
struct ProviderUsageSnapshot: Sendable {
    let usage: PlanUsage?
    let isLoading: Bool
    let error: ProviderError?
    let updatedAt: Date?
}
