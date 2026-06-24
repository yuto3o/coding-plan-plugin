# Coding Plan Plugin for macOS

常驻 macOS 右上角菜单栏的 Coding Plan 用量小插件。

## 功能

- 点击菜单栏图标弹出用量面板
- 支持多种 Coding Plan Provider：
  - **Kimi Code**（套餐型）
  - **cctq.ai**（New API / 充值型）
  - **ikuncode.cc**（New API / 充值型）
- 展示：
  - 账户余额或套餐配额（进度条 / 已用 / 总量 / 剩余）
  - 本周 / 本月（自然月）使用额度与 Token 数量
  - 按模型拆分用量明细
  - 频限明细（Kimi 5 小时窗口）
  - 最后更新时间
- 每 5 分钟自动刷新
- token 过期时自动刷新并重试（Kimi / New API）
- 网络抖动时自动重试 3 次
- 菜单栏图标旁显示用量预警（>50% 显示百分比，>90% 显示 ⚠️）
- 一键打开对应 Provider 控制台
- 订阅管理：添加、编辑、删除、恢复默认
- 退出插件按钮

## 技术栈

- Swift 6 + SwiftUI
- `MenuBarExtra`（macOS 13+）
- Kimi Code OAuth device-code flow（默认浏览器授权）
- Keychain 安全存储 Kimi / New API token
- `/coding/v1/usages` 用量接口（Kimi）
- New API（one-api / new-api）通用适配

## 项目结构

```
Sources/CodingPlanPlugin/
├── CodingPlanPluginApp.swift        # @main MenuBarExtra 入口
├── Models/
│   └── PlanUsage.swift              # 统一用量模型（套餐型 + 充值型）
├── Providers/
│   ├── Provider.swift               # Provider 协议
│   ├── ProviderManager.swift        # 订阅配置管理
│   ├── KimiProvider.swift           # Kimi 实现
│   ├── NewAPIProvider.swift         # New API 可复用基类
│   ├── CCTQProvider.swift           # cctq.ai
│   └── IkunCodeProvider.swift       # ikuncode.cc
├── Network/
│   ├── KimiAPIClient.swift          # /coding/v1/usages 请求
│   └── NewAPIClient.swift           # /api/user/self + /api/user/dashboard
├── Services/
│   ├── KimiCodeAuthService.swift    # Kimi Code OAuth 登录态 / device-code flow
│   ├── NewAPIAuthService.swift      # New API token 存取
│   ├── KeychainStorage.swift        # Keychain 存取
│   └── ProviderConfiguration.swift  # 订阅配置持久化
└── Views/
    ├── UsagePanelView.swift         # 用量面板 UI
    ├── ProviderSettingsView.swift   # 订阅管理 UI
    └── DeviceLoginView.swift        # Kimi device-code 登录视图
```

## 构建

```bash
swift build
```

## 运行

```bash
swift run
```

首次运行点击菜单栏图标后：

- **Kimi**：点击「登录」会打开默认浏览器进入 Kimi Code OAuth device-code flow，授权成功后即可展示用量。插件独立管理 token，与 Kimi Code CLI 互不干扰。
- **New API 平台（cctq.ai / ikuncode.cc）**：在控制台生成 access token 后，点击「管理订阅」→「添加订阅」，粘贴 token 即可。

> 注意：当前为 Swift Package 可执行目标，直接 `swift run` 会以进程方式启动菜单栏插件。后续 Phase 5 会打包为正式 `.app`。

## 认证说明

### Kimi

插件使用 **Kimi Code OAuth** 方式获取用量，且**独立管理 token**，与 Kimi Code CLI 解耦：

- Kimi OAuth token 存储在插件自己的 Keychain item 中（account: `kimi-code.oauth_token`）。
- 若未登录，插件内实现 device-code flow：
  1. 请求 `https://auth.kimi.com/api/oauth/device_authorization`
  2. 打开默认浏览器到返回的 `verification_uri_complete`
  3. 用户确认授权后，轮询 `https://auth.kimi.com/api/oauth/token`
  4. 获取 `access_token` / `refresh_token` 并保存到 Keychain
- token 过期时用 `grant_type=refresh_token` 自动刷新。
- 用量接口为 `GET https://api.kimi.com/coding/v1/usages`，使用 OAuth `access_token` 即可返回套餐与频限数据。

> 插件不会读取或写入 `~/.kimi/credentials/kimi-code.json`。如果你已在 Kimi Code CLI 登录，仍需要在插件内重新授权一次（后续可考虑添加手动「从 CLI 导入」按钮）。

### New API 平台（cctq.ai / ikuncode.cc）

这两个平台均基于 [one-api](https://github.com/songquanpeng/one-api) / [new-api](https://github.com/Calcium-Ion/new-api) 前端框架，接口复用：

- 用户登录控制台后，在「令牌」或「个人设置」中生成 access token
- 插件将该 token 存入 Keychain（account: `newapi.<host>.access_token`）
- 调用 `/api/user/self` 获取余额与总用量
- 调用 `/api/user/dashboard` 获取近 7 天按模型聚合的用量，再汇总为本周 / 本月数据

## 订阅管理



点击面板底部的「管理订阅」进入设置界面，可以：

- 切换当前 Provider
- 添加新的 New API 订阅（名称、Host、Token）
- 编辑或删除已有订阅
- 恢复默认订阅配置

默认订阅包含：Kimi、cctq.ai、ikuncode.cc。

## 阶段

见 [`handoff.md`](handoff.md)。
