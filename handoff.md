# Coding Plan Plugin for macOS — Handoff

## 1. 目标

开发一个常驻 macOS 右上角菜单栏（Menu Bar）的小插件：

- 点击图标后弹出用量面板。
- 首期支持 **Kimi Code Console**：`https://www.kimi.com/code/console`。
- 扩展支持基于 New API（one-api / new-api）的充值型 Provider：
  - **cctq.ai**：`https://www.cctq.ai/console`
  - **ikuncode.cc**：`https://api.ikuncode.cc/console`
- 展示的关键信息：
  - 套餐型：本周用量（百分比 / 已用 / 总量 / 剩余）、频限明细（Rate Limit，5 小时窗口）、重置/刷新时间、最后更新时间
  - 充值型：账户余额、本周/本月（自然月）使用额度与 Token 数量、按模型拆分的用量明细
- 架构上要预留扩展接口，后续可接入其他 Coding Plan（如 Cursor、GitHub Copilot、OpenAI、Claude 等）。

## 2. 当前已确定的实现路径

### 2.1 Kimi 用量数据来源（已反查确认）

Kimi Code CLI 通过 **Coding API** 暴露用量接口，插件直接复用该接口，无需再走网页 `/apiv2`。

```
GET https://api.kimi.com/coding/v1/usages
Authorization: Bearer <kimi-code oauth access_token>
Accept: application/json
```

认证方式（已实验确认）：

- 使用 **Kimi Code OAuth** 颁发的 `access_token`（scope=`kimi-code`）。
- 插件**独立管理 token**，存储在自己的 Keychain item（account: `kimi-code.oauth_token`）中，不依赖 Kimi Code CLI。
- 登录流程为 OAuth **device-code flow**：
  1. `POST https://auth.kimi.com/api/oauth/device_authorization`（`client_id=17e5f671-d194-4dfb-9706-5516cb48c098`）
  2. 打开默认浏览器到返回的 `verification_uri_complete`
  3. 用户确认授权后，轮询 `POST https://auth.kimi.com/api/oauth/token`（`grant_type=urn:ietf:params:oauth:grant-type:device_code`）
  4. 获取 `access_token` / `refresh_token`，保存到插件自己的 Keychain
- token 过期时用 `grant_type=refresh_token` 自动刷新。
- 插件不会自动读取或写入 `~/.kimi/credentials/kimi-code.json`，与 Kimi Code CLI 解耦。

响应结构（实际响应）：

```json
{
  "user": { "userId": "...", "region": "REGION_CN", "membership": { "level": "LEVEL_INTERMEDIATE" } },
  "usage": {
    "limit": "100",
    "used": "12",
    "remaining": "88",
    "resetTime": "2026-06-26T00:53:16.631306Z"
  },
  "limits": [
    {
      "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
      "detail": {
        "limit": "100",
        "used": "25",
        "remaining": "75",
        "resetTime": "2026-06-24T06:53:16.631306Z"
      }
    }
  ],
  "parallel": { "limit": "20" },
  "totalQuota": { "limit": "100", "remaining": "99" },
  "authentication": { "method": "METHOD_ACCESS_TOKEN", "scope": "FEATURE_CODING" },
  "subType": "TYPE_PURCHASE"
}
```

> 注：`usage` 为 Coding 功能维度本周用量；`limits` 为 5 小时频限；`totalQuota` 为账户级总配额。

### 2.2 与旧方案的对比

- 旧方案：通过 WKWebView 登录网页控制台，从 `localStorage['access_token']` 提取 user-center token，调用 `/apiv2`。实现复杂且无法与 Kimi Code CLI 共享登录态。
- 新方案：复用 Kimi Code CLI 的 OAuth token，调用 `/coding/v1/usages`。无需内嵌 WebView，也无需用户手动复制 token。

> 旧方案相关前端资源（`/apiv2`）已废弃，仅保留用于参考。

### 2.3 New API（cctq.ai / ikuncode.cc）用量数据来源

两个平台均基于 [one-api](https://github.com/songquanpeng/one-api) / [new-api](https://github.com/Calcium-Ion/new-api) 前端框架，接口可复用。

#### 认证

- 用户在控制台生成 **access token**（通常位于「令牌」或「个人设置」页面）。
- 插件将该 token 存入 Keychain（account: `newapi.<host>.access_token`）。
- 请求时在 `Authorization` header 中携带：`Authorization: Bearer <access_token>`。

#### 关键端点

| 端点 | 用途 |
|------|------|
| `GET /api/user/self` | 获取用户余额、总用量、请求次数 |
| `GET /api/user/dashboard` | 获取近 7 天按模型聚合的用量 |

#### `/api/user/self` 响应结构（参考 one-api 源码）

```json
{
  "success": true,
  "data": {
    "id": 1,
    "username": "user",
    "quota": 100000000,
    "used_quota": 12345678,
    "request_count": 42
  }
}
```

- `quota` 为账户剩余额度（单位：1 token = 1 额度，注意 new-api 常见倍率为 1000000 = $1）。
- `used_quota` 为历史总已用额度。

#### `/api/user/dashboard` 响应结构

```json
{
  "success": true,
  "data": [
    {
      "day": "2026-06-23",
      "model_name": "gpt-4o",
      "request_count": 10,
      "quota": 5678,
      "prompt_tokens": 800,
      "completion_tokens": 434
    }
  ]
}
```

- `day` 为 `YYYY-MM-DD` 格式的日期字符串（由后端按 `created_at` Unix 时间戳聚合生成）。
- `model_name` 为模型名（如 `gpt-4o`、`claude-3-5-sonnet`）。
- `quota` / `prompt_tokens` / `completion_tokens` / `request_count` 为该模型在该天的汇总。

#### 本地聚合策略

插件收到近 7 天明细后，按以下维度聚合为 `PlanUsage`：

1. **本周**：从上周日到昨天（或今天）的自然周。
2. **本月**：当月 1 日到今天（含）的自然月。
3. **按模型**：在同一周期内再按 `ModelName` 拆分。

例如：`periods[0]` 为「本周」，其 `modelUsages` 数组列出该周内各模型的额度、Token 数、请求数。

### 2.4 本地 Kimi Code CLI 环境（参考）

用户机器上已有 Kimi Code CLI 配置，但插件**不依赖**它：

- 配置目录：`~/.kimi/`
- 关键文件：
  - `~/.kimi/config.toml` —— provider 配置。
  - `~/.kimi/kimi.json` —— 用户/会话相关 JSON。
  - `~/.kimi/credentials/kimi-code.json` —— Kimi Code CLI 自己的 OAuth token。
- 旧版目录：`~/.kimi-code/`。

> 重要：插件使用同样的 Coding API OAuth token（scope=`kimi-code`）调用 `/coding/v1/usages`，但 token 由插件自己独立存储在 Keychain。未来可提供一个手动的「从 CLI 导入」按钮，但不会自动耦合。

## 3. 关键未决问题（已更新）

1. **认证方式** ✅ 已确定（已切换为 Kimi Code OAuth，且独立管理 token）
   - 旧结论：`/apiv2` 不接受 Kimi Code CLI 的 OAuth token（返回 401）。
   - 新结论：Kimi Code CLI 通过 `/coding/v1/usages` 获取用量，该接口**接受** OAuth token（scope=`kimi-code`）。插件采用同样的 OAuth token，但独立存储在 Keychain，不依赖 CLI。
   - 登录方式：插件内实现 OAuth device-code flow，打开默认浏览器授权，获取 token 后保存到 Keychain（account: `kimi-code.oauth_token`）。
   - Token 刷新：`POST https://auth.kimi.com/api/oauth/token`（`grant_type=refresh_token`）。App 已实现在 401 时自动刷新并重试。
   - 已验证的响应结构见下表（字段名以实际响应为准）：

     ```json
     {
       "usage": { "limit": "100", "used": "12", "remaining": "88", "resetTime": "..." },
       "limits": [
         {
           "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
           "detail": { "limit": "100", "used": "25", "remaining": "75", "resetTime": "..." }
         }
       ],
       "totalQuota": { "limit": "100", "remaining": "99" }
     }
     ```

2. **数据刷新策略**
   - 建议每 5 分钟轮询一次 + 点击立即刷新。
3. **多 Provider 抽象** ✅ 已完成
   - 定义 `Provider` 协议：`fetchUsage() -> PlanUsage`，包含认证、打开控制台、保存/清除 token 等能力。
   - 新增 `ProviderConfiguration` 与 `ProviderManager`，支持用户添加、编辑、删除、恢复默认订阅。
   - Kimi 作为首个实现；新增可复用的 `NewAPIProvider` 基类，并派生 `CCTQProvider` 与 `IkunCodeProvider`。
4. **订阅管理** ✅ 已完成
   - 默认订阅：Kimi、cctq.ai、ikuncode.cc。
   - 用户可通过设置面板管理多个订阅，包括切换当前 Provider。
4. **技术栈**
   - 推荐 SwiftUI `MenuBarExtra`（macOS 13+）或 AppKit `NSStatusItem` + NSPopover。

## 4. 后续计划

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 0 | 确定认证方案并通过 `curl` 验证能拿到真实用量数据 | ✅ 已完成 |
| Phase 1 | 创建 Xcode 项目 / Swift Package，搭建 MenuBarExtra 骨架 | ✅ 已完成 |
| Phase 2 | 实现 Kimi Provider：网络请求、JSON 解析、错误处理 | ✅ 已完成 |
| Phase 3 | UI 面板：进度条、重置倒计时、刷新按钮、打开控制台 | ✅ 已完成 |
| Phase 3.5 | 完善当前版本：登录/登出、token 自动刷新、UI 美化、错误重试 | ✅ 已完成 |
| Phase 4 | 支持多 Provider 配置与切换 | ✅ 已完成 |
| Phase 5 | 打包为 `.app` / 签名 / 分发 | 🚧 待开始 |

## 5. 可复用的命令与脚本

### 验证 Kimi /coding/v1/usages

从 Kimi Code CLI 凭证文件中读取 token 并调用用量接口：

```bash
ACCESS_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.kimi/credentials/kimi-code.json'))['access_token'])")
curl -sL -X GET 'https://api.kimi.com/coding/v1/usages' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Accept: application/json' \
  -w '\nHTTP %{http_code}\n'
```

### 验证 Kimi OAuth device authorization

```bash
curl -sL -X POST 'https://auth.kimi.com/api/oauth/device_authorization' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -d 'client_id=17e5f671-d194-4dfb-9706-5516cb48c098' \
  -w '\nHTTP %{http_code}\n'
```

### 刷新 Kimi OAuth token

替换 `<REFRESH_TOKEN>`：

```bash
curl -sL -X POST 'https://auth.kimi.com/api/oauth/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -d 'client_id=17e5f671-d194-4dfb-9706-5516cb48c098&grant_type=refresh_token&refresh_token=<REFRESH_TOKEN>' \
  -w '\nHTTP %{http_code}\n'
```

### New API（cctq.ai / ikuncode.cc）验证

替换 `<HOST>` 为 `www.cctq.ai` 或 `api.ikuncode.cc`，替换 `<TOKEN>` 为控制台生成的 access token：

```bash
curl -sL -X GET "https://<HOST>/api/user/self" \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Accept: application/json' \
  -w '\nHTTP %{http_code}\n'

curl -sL -X GET "https://<HOST>/api/user/dashboard" \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Accept: application/json' \
  -w '\nHTTP %{http_code}\n'
```

## 6. 经验与注意事项

- Kimi 用量接口优先使用 `/coding/v1/usages`，认证走 **Kimi Code OAuth**（scope=`kimi-code`）。插件独立管理 token，与 Kimi Code CLI 解耦。
- OAuth client_id 为 `17e5f671-d194-4dfb-9706-5516cb48c098`，OAuth host 为 `https://auth.kimi.com`，device-code flow 与 refresh 端点均位于该 host。
- 旧方案（`/apiv2` + user-center `localStorage`）已废弃，相关前端资源仅供参考。
- 菜单栏插件需要 `com.apple.security.network.client`（出站网络） entitlement；不再需要 WebKit 权限。
- 不要在前端或共享仓库里暴露用户的 access_token；Kimi OAuth token 保存在插件自己的 Keychain item（account: `kimi-code.oauth_token`），New API token 仍由 Keychain 管理。
- Kimi access_token 有效期约 15 分钟，refresh_token 约 30 天；App 已接入 `POST /api/oauth/token`（`grant_type=refresh_token`）自动刷新，并在网络抖动时自动重试 3 次。
- New API Provider 通过抽象基类复用 `NewAPIClient`，子类仅配置 `baseURL`、`consoleURL`、`displayName` 即可新增一个平台。
- New API 的 `dashboard` 接口仅返回近 7 天数据，因此「本周」与「本月」周期需要在客户端按 Unix 时间戳重新聚合；`Quota` 字段单位为平台额度（常见倍率 1,000,000 = $1）。
- Provider 配置持久化在 UserDefaults（`providerConfigurations`），敏感 token 仍由 Keychain 管理；恢复默认订阅会保留用户自定义 token（如已存在对应 ID）。
- 退出插件按钮调用 `NSApplication.shared.terminate(nil)`，适用于 MenuBarExtra 应用。

## 7. 资源清单

- 项目目录：`/Users/yangyu/Documents/github/coding-plan-plugin-for-macos`
- Kimi Code Console：`https://www.kimi.com/code/console`
- Kimi Coding API：`https://api.kimi.com/coding/v1`
- Kimi OAuth host：`https://auth.kimi.com`
- Kimi Code CLI 源码：`https://github.com/MoonshotAI/kimi-code`
- cctq.ai 控制台：`https://www.cctq.ai/console`
- ikuncode.cc 控制台：`https://api.ikuncode.cc/console`
- one-api 源码参考：`https://raw.githubusercontent.com/songquanpeng/one-api/main/controller/user.go`
- 本地 CLI 配置：`~/.kimi/config.toml`
- 本地 OAuth token（插件自身不使用，仅 CLI 参考）：`~/.kimi/credentials/kimi-code.json`
- 本 handoff 文件：`handoff.md`
