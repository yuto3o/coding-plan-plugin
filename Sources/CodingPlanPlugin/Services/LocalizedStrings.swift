import Foundation

/// 集中管理所有 UI 文本的中英文本地化。
struct LocalizedStrings {
    let language: AppLanguage

    // MARK: - Common

    var refresh: String { localize(zh: "刷新", en: "Refresh") }
    var logout: String { localize(zh: "登出", en: "Logout") }
    var console: String { localize(zh: "控制台", en: "Console") }
    var quit: String { localize(zh: "退出", en: "Quit") }
    var save: String { localize(zh: "保存", en: "Save") }
    var cancel: String { localize(zh: "取消", en: "Cancel") }
    var done: String { localize(zh: "完成", en: "Done") }
    var add: String { localize(zh: "添加", en: "Add") }
    var login: String { localize(zh: "登录", en: "Login") }
    var actions: String { localize(zh: "操作", en: "Actions") }

    // MARK: - Usage Panel

    var fetchingUsage: String { localize(zh: "正在获取用量…", en: "Fetching usage…") }
    var fetchFailed: String { localize(zh: "获取失败", en: "Fetch Failed") }
    var notSignedIn: String { localize(zh: "尚未登录", en: "Not signed in to") }
    var newAPILoginHint: String {
        localize(
            zh: "粘贴控制台的 access token 和用户 ID。",
            en: "Paste the access token and user ID from the console."
        )
    }
    var pasteAccessToken: String { localize(zh: "access token", en: "access token") }
    var userID: String { localize(zh: "user ID", en: "user ID") }
    var saveAndRefresh: String { localize(zh: "登录", en: "Login") }
    var kimLoginHint: String {
        localize(
            zh: "点击「登录」在浏览器中完成 Kimi Code 授权。",
            en: "Click Login to authorize Kimi Code in your browser."
        )
    }
    var noUsageData: String { localize(zh: "暂无用量数据", en: "No usage data") }
    var accountBalance: String { localize(zh: "账户余额", en: "Account Balance") }
    var total: String { localize(zh: "总额", en: "Total") }
    var used: String { localize(zh: "已用", en: "Used") }
    var requests: String { localize(zh: "请求数", en: "Requests") }
    var inputTokens: String { localize(zh: "输入 Tokens", en: "Input Tokens") }
    var outputTokens: String { localize(zh: "输出 Tokens", en: "Output Tokens") }
    var byModel: String { localize(zh: "按模型", en: "By Model") }
    var totalQuota: String { localize(zh: "总配额", en: "Total Quota") }
    var monthlyUsed: String { localize(zh: "本月已用", en: "Monthly Used") }
    var updated: String { localize(zh: "更新于", en: "Updated") }
    var noProvider: String { localize(zh: "没有可用的 Provider", en: "No provider available") }
    var weeklyLimit: String { localize(zh: "周限额", en: "Weekly Limit") }
    var hourlyLimit: String { localize(zh: "5小时限额", en: "5h Limit") }

    // MARK: - Provider Settings

    var subscriptions: String { localize(zh: "订阅管理", en: "Subscriptions") }
    var addSubscription: String { localize(zh: "添加订阅", en: "Add Subscription") }
    var resetDefaults: String { localize(zh: "恢复默认", en: "Reset Defaults") }
    var addSubscriptionTitle: String { localize(zh: "添加订阅", en: "Add Subscription") }
    var editSubscriptionTitle: String { localize(zh: "编辑订阅", en: "Edit Subscription") }
    var deleteSubscriptionTitle: String { localize(zh: "删除订阅", en: "Delete Subscription") }
    var deleteSubscriptionMessage: String { localize(zh: "确定要删除这条订阅吗？此操作无法撤销。", en: "Are you sure you want to delete this subscription? This action cannot be undone.") }
    var delete: String { localize(zh: "删除", en: "Delete") }
    var displayName: String { localize(zh: "显示名称", en: "Display Name") }
    var type: String { localize(zh: "类型", en: "Type") }
    var baseURLPlaceholder: String {
        localize(zh: "Base URL，如 https://www.cctq.ai", en: "Base URL, e.g. https://www.cctq.ai")
    }
    var consolePathPlaceholder: String { localize(zh: "控制台路径（可选）", en: "Console Path (optional)") }

    // MARK: - Device Login

    var signInToKimi: String { localize(zh: "登录 Kimi Code", en: "Sign in to Kimi Code") }
    var deviceLoginHint: String {
        localize(
            zh: "请在打开的浏览器页面中确认授权。如未自动跳转，可复制下方验证码手动输入。",
            en: "Please confirm authorization in the browser page. If it didn't open automatically, copy the code below and paste it on the verification page."
        )
    }
    var verificationCode: String { localize(zh: "验证码", en: "Verification Code") }
    var openBrowser: String { localize(zh: "打开浏览器", en: "Open Browser") }

    // MARK: - Rate Limit Window

    func rateLimitWindow(_ description: String) -> String {
        localize(zh: "\(description) 频限", en: "\(description) Rate Limit")
    }

    // MARK: - Countdown

    var expired: String { localize(zh: "已到期", en: "Expired") }
    var reset: String { localize(zh: "重置", en: "Reset") }
    var remaining: String { localize(zh: "剩余", en: "Remaining") }
    var monthlyQuota: String { localize(zh: "本月额度", en: "Monthly Quota") }
    var weeklyTotal: String { localize(zh: "本周额度", en: "Weekly Quota") }

    // MARK: - Helper

    private func localize(zh: String, en: String) -> String {
        switch language {
        case .chinese: return zh
        case .english: return en
        }
    }
}

extension AppLanguage {
    var strings: LocalizedStrings {
        LocalizedStrings(language: self)
    }
}
