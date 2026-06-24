# 订阅卡片式面板设计

**目标：** 将 `UsagePanelView` 顶部的订阅 Picker 改为纵向平铺的订阅卡片列表，每张卡片展示该订阅的完整用量摘要，并支持选中、编辑、删除和拖拽排序。

**日期：** 2026-06-24

---

## 背景

当前主面板通过顶部 Picker 切换不同订阅，选中后在下方面板展示该订阅的用量详情。随着订阅数量增加，Picker 不够直观，用户希望直接看到所有订阅的用量概况。

## 需求

1. **平铺卡片**：移除顶部 Picker，主区域改为从上到下平铺订阅卡片。
2. **添加入口**：左上角放置 `+` 按钮，用于添加新订阅。
3. **卡片内容**：每张卡片展示订阅名称、总配额进度条、本月已用、本周模型分布等完整用量摘要。
4. **选中状态**：点击卡片切换当前选中的 provider，并用高亮边框/背景标识。
5. **删除订阅**：卡片支持删除操作（右上角垃圾桶按钮）。
6. **拖拽排序**：支持拖拽卡片改变展示顺序，顺序持久化。
7. **动态高度**：1–3 张卡片时面板随内容自动增高；超过 3 张或达到屏幕高度后启用垂直滚动。
8. **独立状态**：每张卡片的加载、错误、用量数据相互独立。

## 架构

```
UsagePanelView
├── Header（+ 按钮、语言切换、设置、刷新进度）
├── SubscriptionCardList
│   └── SubscriptionCard（每个订阅一张）
│       ├── 名称 + 编辑/删除按钮
│       ├── 用量摘要视图
│       └── 加载/错误/未登录提示
└── Footer（刷新、登出、控制台、退出）
```

## 数据模型

新增 `ProviderUsageSnapshot`：

```swift
struct ProviderUsageSnapshot: Sendable {
    let usage: PlanUsage?
    let isLoading: Bool
    let error: ProviderError?
    let updatedAt: Date?
}
```

`ProviderManager` 新增：

```swift
@Published var usageSnapshots: [String: ProviderUsageSnapshot] = [:]
```

key 为 `ProviderConfiguration.id`。

## 数据流

1. `UsagePanelView` 启动时，遍历 `manager.configurations`，为每个 provider 创建 `Task` 并发调用 `fetchUsage()`。
2. 每个 `Task` 完成后将结果写入 `manager.usageSnapshots[config.id]`。
3. 定时器（5 分钟）触发时，仅刷新当前已有快照的订阅，保持并发。
4. 添加、删除、编辑订阅后，更新配置列表并刷新对应快照。
5. 选中卡片只改变 `manager.selectedID`，不触发新的网络请求。

## 组件设计

### SubscriptionCardList

- 使用 `VStack` 包裹卡片。
- 1–3 张卡片时不限制高度，随内容自然扩展。
- 超过 3 张或需要时在外层加 `ScrollView`。
- 处理拖拽放置逻辑，调用 `manager.move(from:to:)` 更新顺序。

### SubscriptionCard

- 固定高度约 120–140pt。
- 卡片内容区点击设置 `manager.selectedID = config.id`。
- 右上角常驻编辑和删除按钮（或使用 hover 显示）。
- 用量摘要复用现有 `CircularProgressView`、`MultiSegmentRingView` 和格式化函数。
- 未登录状态显示登录入口按钮。

## 交互细节

| 操作 | 行为 |
|------|------|
| 点击卡片内容区 | 选中该订阅 |
| 点击 `+` | 打开 `ProviderEditView` 添加订阅 |
| 点击铅笔 | 打开 `ProviderEditView` 编辑订阅 |
| 点击垃圾桶 | 弹出确认 Alert，确认后删除 |
| 拖拽卡片 | 改变订阅展示顺序，保存到 UserDefaults |
| 定时刷新 | 并发刷新所有订阅快照 |

## 错误处理

- 每张卡片独立显示自己的错误状态，不阻断其他卡片。
- 网络错误在卡片内以小字红色提示，并提供重试按钮。
- 未登录状态在卡片内显示"未登录"并提供登录入口。

## 边界情况

- 订阅列表为空：显示空状态提示和 `+` 按钮引导添加。
- 某个 provider 获取失败：其他卡片正常显示。
- 删除最后一个订阅：显示空状态。
- 拖拽到无效位置：忽略。

## 待实现计划

本设计通过后将使用 `writing-plans` skill 生成详细实现计划。
