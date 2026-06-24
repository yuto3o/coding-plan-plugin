# 订阅卡片式面板实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `UsagePanelView` 顶部的订阅 Picker 改为纵向平铺的订阅卡片列表，每张卡片展示该订阅的完整用量摘要，并支持选中、编辑、删除和拖拽排序。

**Architecture:** 在 `ProviderManager` 中引入 `[String: ProviderUsageSnapshot]` 快照缓存，为每个订阅并发拉取用量；`UsagePanelView` 改为渲染 `SubscriptionCardList`，每个 `SubscriptionCard` 独立展示名称、用量摘要和状态；拖拽排序直接修改 `configurations` 顺序并持久化。

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, SwiftPM

## Global Constraints

- 面板宽度固定 400pt。
- 1–3 张卡片时面板随内容自动增高；超过 3 张或达到屏幕高度后启用垂直滚动。
- 每张卡片的加载、错误、用量数据相互独立。
- 删除订阅前需要用户确认。
- 所有新增 UI 文本必须走 `LocalizedStrings` 中英文本地化。

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/CodingPlanPlugin/Models/ProviderUsageSnapshot.swift` | 新增：单个订阅的用量快照模型。 |
| `Sources/CodingPlanPlugin/Services/ProviderManager.swift` | 修改：新增 `usageSnapshots`，实现 `move(from:to:)`、刷新单个/全部快照。 |
| `Sources/CodingPlanPlugin/Views/SubscriptionCard.swift` | 新增：单张订阅卡片 UI，包含名称、用量摘要、操作按钮、状态。 |
| `Sources/CodingPlanPlugin/Views/SubscriptionCardList.swift` | 新增：卡片列表容器，处理布局、滚动、拖拽排序。 |
| `Sources/CodingPlanPlugin/Views/UsagePanelView.swift` | 修改：移除 Picker，改为卡片列表；调整 Header/Footer。 |
| `Sources/CodingPlanPlugin/Services/LocalizedStrings.swift` | 修改：新增删除确认等文案。 |

---

### Task 1: 定义 ProviderUsageSnapshot 模型

**Files:**
- Create: `Sources/CodingPlanPlugin/Models/ProviderUsageSnapshot.swift`

**Interfaces:**
- Produces: `struct ProviderUsageSnapshot: Sendable` with properties `usage: PlanUsage?`, `isLoading: Bool`, `error: ProviderError?`, `updatedAt: Date?`.

- [ ] **Step 1: 创建快照模型文件**

```swift
import Foundation

/// 单个订阅的用量快照，包含最新用量、加载状态和错误信息。
struct ProviderUsageSnapshot: Sendable {
    let usage: PlanUsage?
    let isLoading: Bool
    let error: ProviderError?
    let updatedAt: Date?
}
```

- [ ] **Step 2: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 3: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Models/ProviderUsageSnapshot.swift
git commit -m "feat: add ProviderUsageSnapshot model"
```

---

### Task 2: ProviderManager 增加快照缓存与移动方法

**Files:**
- Modify: `Sources/CodingPlanPlugin/Services/ProviderManager.swift`

**Interfaces:**
- Consumes: `ProviderUsageSnapshot` from Task 1.
- Produces: `@Published var usageSnapshots: [String: ProviderUsageSnapshot]`, `func refreshSnapshot(for id: String) async`, `func refreshAllSnapshots() async`, `func move(from source: IndexSet, to destination: Int)`.

- [ ] **Step 1: 在 ProviderManager 顶部新增快照属性**

在 `@Published var selectedID: String?` 下方添加：

```swift
@Published var usageSnapshots: [String: ProviderUsageSnapshot] = [:]
```

- [ ] **Step 2: 实现 refreshSnapshot(for:) 方法**

在 `clearToken(for:)` 之后添加：

```swift
func refreshSnapshot(for id: String) async {
    guard let config = configurations.first(where: { $0.id == id }),
          let provider = Self.makeProvider(from: config) else {
        return
    }

    await MainActor.run {
        usageSnapshots[id] = ProviderUsageSnapshot(
            usage: usageSnapshots[id]?.usage,
            isLoading: true,
            error: nil,
            updatedAt: usageSnapshots[id]?.updatedAt
        )
    }

    do {
        let usage = try await provider.fetchUsage()
        await MainActor.run {
            usageSnapshots[id] = ProviderUsageSnapshot(
                usage: usage,
                isLoading: false,
                error: nil,
                updatedAt: Date()
            )
        }
    } catch {
        await MainActor.run {
            usageSnapshots[id] = ProviderUsageSnapshot(
                usage: usageSnapshots[id]?.usage,
                isLoading: false,
                error: error as? ProviderError ?? .unknown,
                updatedAt: usageSnapshots[id]?.updatedAt
            )
        }
    }
}
```

- [ ] **Step 3: 实现 refreshAllSnapshots() 方法**

紧接着添加：

```swift
func refreshAllSnapshots() async {
    await withTaskGroup(of: Void.self) { group in
        for config in configurations {
            group.addTask {
                await self.refreshSnapshot(for: config.id)
            }
        }
    }
}
```

- [ ] **Step 4: 实现 move(from:to:) 方法**

紧接着添加：

```swift
func move(from source: IndexSet, to destination: Int) {
    var configs = configurations
    configs.move(fromOffsets: source, toOffset: destination)
    configurations = configs
    save()
}
```

- [ ] **Step 5: 修改 remove(id:) 清理快照**

在 `remove(id:)` 中 `save()` 之前添加：

```swift
usageSnapshots.removeValue(forKey: id)
```

- [ ] **Step 6: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 7: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Services/ProviderManager.swift
git commit -m "feat: add usage snapshot cache and move support"
```

---

### Task 3: 新增订阅卡片 UI

**Files:**
- Create: `Sources/CodingPlanPlugin/Views/SubscriptionCard.swift`

**Interfaces:**
- Consumes: `ProviderConfiguration`, `ProviderUsageSnapshot?`, `isSelected: Bool`, 闭包 `onSelect`, `onEdit`, `onDelete`, `onRetry`。
- Produces: `struct SubscriptionCard: View`。

- [ ] **Step 1: 创建 SubscriptionCard.swift**

```swift
import SwiftUI

struct SubscriptionCard: View {
    let config: ProviderConfiguration
    let snapshot: ProviderUsageSnapshot?
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var languageManager: LanguageManager

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(config.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            content
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            if snapshot.isLoading && snapshot.usage == nil {
                loadingPlaceholder
            } else if let error = snapshot.error {
                errorPlaceholder(error)
            } else if let usage = snapshot.usage {
                usageContent(usage)
            } else {
                notSignedInPlaceholder
            }
        } else {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(height: 60)
    }

    @ViewBuilder
    private func errorPlaceholder(_ error: ProviderError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.description)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Button(L.refresh) {
                onRetry()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var notSignedInPlaceholder: some View {
        HStack {
            Text(L.notSignedIn)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private func usageContent(_ usage: PlanUsage) -> some View {
        if usage.featureUsages.isEmpty, usage.balance != nil, !usage.periods.isEmpty {
            creditUsageContent(usage)
        } else if let total = usage.totalQuota {
            quotaRow(quota: total)
        } else {
            notSignedInPlaceholder
        }
    }

    @ViewBuilder
    private func creditUsageContent(_ usage: PlanUsage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let total = usage.totalUsage {
                totalQuotaColumn(total: total, monthlyUsed: usage.periods.first?.quotaUsed ?? 0)
            }

            if usage.periods.count > 1 {
                weeklyRingColumn(breakdown: usage.periods[1])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func totalQuotaColumn(total: UsageBreakdown, monthlyUsed: Int64) -> some View {
        let used = total.quotaUsed
        let limit = total.limit
        let remaining = max(0, limit - used)
        let remainingPercent = max(0, min(1, Double(remaining) / Double(max(1, limit))))
        let ringColor = barColor(for: remainingPercent)

        HStack(spacing: 6) {
            CircularProgressView(percent: remainingPercent, color: ringColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(L.totalQuota)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(formatQuota(remaining)) / \(formatQuota(limit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("\(L.monthlyUsed) \(formatQuota(monthlyUsed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func weeklyRingColumn(breakdown: UsageBreakdown) -> some View {
        let colors: [Color] = [.red, .yellow, .green, .gray]
        let total = max(1, breakdown.modelUsages.reduce(0) { $0 + $1.quotaUsed })
        let segments = breakdown.modelUsages.enumerated().map { index, model in
            RingSegment(
                name: model.modelName,
                value: Double(model.quotaUsed) / Double(total),
                color: colors[min(index, colors.count - 1)]
            )
        }

        HStack(spacing: 6) {
            MultiSegmentRingView(segments: segments)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.weeklyTotal)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)

                ForEach(segments.prefix(3)) { segment in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 5, height: 5)
                        Text("\(segment.name) · \(formatQuota(Int64(segment.value * Double(total))))")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quotaRow(quota: Quota) -> some View {
        let remainingPercent = max(0, min(1, 1.0 - quota.usedPercent))
        HStack(spacing: 8) {
            CircularProgressView(percent: remainingPercent, color: barColor(for: remainingPercent))
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.totalQuota)
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("\(quota.remaining) / \(quota.limit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func barColor(for remainingPercent: Double) -> Color {
        switch remainingPercent {
        case 0.4...1.0: return .green
        case 0.2..<0.4: return .yellow
        default: return .red
        }
    }

    private func formatQuota(_ value: Int64) -> String {
        let doubleValue = Double(value)
        let absValue = abs(doubleValue)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", doubleValue / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "%.1fK", doubleValue / 1_000)
        } else {
            return String(value)
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!（若发现 `CircularProgressView` 等组件不可见，确认后续 Task 会将其提取到独立文件或保持原位置）

- [ ] **Step 3: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Views/SubscriptionCard.swift
git commit -m "feat: add SubscriptionCard view"
```

---

### Task 4: 新增订阅卡片列表容器

**Files:**
- Create: `Sources/CodingPlanPlugin/Views/SubscriptionCardList.swift`

**Interfaces:**
- Consumes: `ProviderManager`（通过 `@EnvironmentObject` 或传参）、`onEdit: (ProviderConfiguration) -> Void`。
- Produces: `struct SubscriptionCardList: View`。

- [ ] **Step 1: 创建 SubscriptionCardList.swift**

```swift
import SwiftUI

struct SubscriptionCardList: View {
    @EnvironmentObject private var manager: ProviderManager
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var configToDelete: ProviderConfiguration? = nil

    let onEdit: (ProviderConfiguration) -> Void

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        let cards = cardContent
            .frame(maxWidth: .infinity, alignment: .leading)

        if manager.configurations.count > 3 {
            ScrollView {
                cards
            }
            .frame(maxHeight: 420)
        } else {
            cards
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 8) {
            ForEach(manager.configurations) { config in
                SubscriptionCard(
                    config: config,
                    snapshot: manager.usageSnapshots[config.id],
                    isSelected: manager.selectedID == config.id,
                    onSelect: {
                        manager.selectedID = config.id
                    },
                    onEdit: {
                        onEdit(config)
                    },
                    onDelete: {
                        configToDelete = config
                    },
                    onRetry: {
                        Task {
                            await manager.refreshSnapshot(for: config.id)
                        }
                    }
                )
                .draggable(config.id) {
                    Text(config.name)
                        .font(.caption)
                        .padding(6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
                .dropDestination(for: String.self) { items, location in
                    guard let draggedID = items.first,
                          let sourceIndex = manager.configurations.firstIndex(where: { $0.id == draggedID }),
                          let targetIndex = manager.configurations.firstIndex(where: { $0.id == config.id }),
                          sourceIndex != targetIndex else {
                        return false
                    }
                    var indexSet = IndexSet(integer: sourceIndex)
                    let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                    manager.move(from: indexSet, to: destination)
                    return true
                }
            }
        }
        .alert(L.deleteSubscriptionTitle ?? "Delete Subscription", isPresented: Binding(
            get: { configToDelete != nil },
            set: { if !$0 { configToDelete = nil } }
        )) {
            Button(L.cancel, role: .cancel) {
                configToDelete = nil
            }
            Button(L.delete, role: .destructive) {
                if let config = configToDelete {
                    manager.remove(id: config.id)
                }
                configToDelete = nil
            }
        } message: {
            Text(L.deleteSubscriptionMessage)
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!（`L.deleteSubscriptionTitle` / `L.deleteSubscriptionMessage` / `L.delete` 会在 Task 6 添加）

- [ ] **Step 3: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Views/SubscriptionCardList.swift
git commit -m "feat: add SubscriptionCardList with drag-to-reorder"
```

---

### Task 5: 重构 UsagePanelView 为卡片式布局

**Files:**
- Modify: `Sources/CodingPlanPlugin/Views/UsagePanelView.swift`

**Interfaces:**
- Consumes: `SubscriptionCardList` from Task 4。
- Produces: 新的 `headerView`（无 Picker，有 `+` 按钮）、`cardListView`、简化的 `footerView`。

- [ ] **Step 1: 移除旧的 usageContent/breakdownSection 等主内容代码**

保留 Header 结构但替换 Picker 为 `+` 按钮，移除 `usageContent`、中间展示 section 等代码。保留 `loginPlaceholder`、`emptyPlaceholder`、`footerView` 和 `refresh()` 逻辑。

- [ ] **Step 2: 实现新的 headerView**

```swift
@ViewBuilder
private var headerView: some View {
    HStack(spacing: 8) {
        Button {
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)

        Spacer()

        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    languageManager.current = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if languageManager.current == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)

        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)

        if isLoading {
            ProgressView()
                .controlSize(.small)
        }
    }
}
```

- [ ] **Step 3: 实现卡片列表主体**

在 `body` 中把原来的 `usageContent` 区域替换为：

```swift
SubscriptionCardList { config in
    editingConfig = config
}
.environmentObject(manager)
```

并新增 `@State private var editingConfig: ProviderConfiguration? = nil` 和 `@State private var showAddSheet = false`。

- [ ] **Step 4: 添加添加/编辑 sheet**

在 `body` 的 `.sheet` 部分添加：

```swift
.sheet(isPresented: $showAddSheet) {
    ProviderEditView(config: nil) { newConfig in
        manager.add(newConfig)
        showAddSheet = false
        Task {
            await manager.refreshSnapshot(for: newConfig.id)
        }
    }
    .frame(minWidth: 400, minHeight: 260)
    .environmentObject(languageManager)
}
.sheet(item: $editingConfig) { config in
    ProviderEditView(config: config) { updated in
        manager.update(updated)
        editingConfig = nil
        Task {
            await manager.refreshSnapshot(for: updated.id)
        }
    }
    .frame(minWidth: 400, minHeight: 260)
    .environmentObject(languageManager)
}
```

- [ ] **Step 5: 调整 body 和刷新逻辑**

在 `.task` 中调用：

```swift
.task {
    await manager.refreshAllSnapshots()
}
.onReceive(timer) { _ in
    Task {
        await manager.refreshAllSnapshots()
    }
}
```

移除 `usage` 相关的 `@State` 和 `refresh()` 中的单 provider 用量获取逻辑；保留 `isLoading` 用于顶部刷新指示。

- [ ] **Step 6: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 7: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Views/UsagePanelView.swift
git commit -m "feat: refactor UsagePanelView to card-based layout"
```

---

### Task 6: 新增本地化文案

**Files:**
- Modify: `Sources/CodingPlanPlugin/Services/LocalizedStrings.swift`

**Interfaces:**
- Produces: `delete`, `deleteSubscriptionTitle`, `deleteSubscriptionMessage`。

- [ ] **Step 1: 添加删除相关文案**

在 Common 区域添加：

```swift
var delete: String { localize(zh: "删除", en: "Delete") }
```

在 Provider Settings 区域添加：

```swift
var deleteSubscriptionTitle: String { localize(zh: "删除订阅", en: "Delete Subscription") }
var deleteSubscriptionMessage: String {
    localize(
        zh: "确定要删除这个订阅吗？此操作不会清空服务端数据。",
        en: "Are you sure you want to delete this subscription? This will not remove data from the server."
    )
}
```

- [ ] **Step 2: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 3: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Services/LocalizedStrings.swift
git commit -m "feat: add delete subscription localization strings"
```

---

### Task 7: 统一可复用视图组件

**Files:**
- Modify: `Sources/CodingPlanPlugin/Views/UsagePanelView.swift`
- Modify: `Sources/CodingPlanPlugin/Views/SubscriptionCard.swift`

**Interfaces:**
- Produces: 将 `CircularProgressView`、`MultiSegmentRingView`、`RingSegment`、`RingArc` 提取到 `Sources/CodingPlanPlugin/Views/Shared/RingViews.swift`。

- [ ] **Step 1: 创建 Shared/RingViews.swift**

把 `UsagePanelView.swift` 底部的 `CircularProgressView`、`RingSegment`、`RingArc`、`MultiSegmentRingView` 移动到 `Sources/CodingPlanPlugin/Views/Shared/RingViews.swift`。

- [ ] **Step 2: 更新引用**

从 `UsagePanelView.swift` 中删除这些视图定义，确保 `SubscriptionCard.swift` 能直接使用。

- [ ] **Step 3: 构建验证**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 4: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git add Sources/CodingPlanPlugin/Views/Shared/RingViews.swift Sources/CodingPlanPlugin/Views/UsagePanelView.swift Sources/CodingPlanPlugin/Views/SubscriptionCard.swift
git commit -m "refactor: extract ring views to shared file"
```

---

### Task 8: 集成测试与验证

**Files:**
- Modify: 无（仅运行验证）

- [ ] **Step 1: 完整构建**

Run: `cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 2: 启动应用检查 UI**

Run: `.build/debug/CodingPlanPlugin`
Expected: 主面板显示订阅卡片列表，点击卡片可切换选中，拖拽可排序，点击垃圾桶弹出确认后可删除。

- [ ] **Step 3: Commit**

```bash
cd /Users/yangyu/Documents/github/coding-plan-plugin-for-macos
git commit --allow-empty -m "test: verify subscription card layout"
```

---

## Spec Coverage Check

| Spec Requirement | Task |
|------------------|------|
| 平铺卡片，移除 Picker | Task 5 |
| 左上角 `+` 按钮 | Task 5 |
| 卡片展示完整用量摘要 | Task 3 |
| 选中状态高亮 | Task 3 |
| 删除订阅 | Task 4 + Task 6 |
| 拖拽排序 | Task 2 + Task 4 |
| 1–3 张动态高度，超过滚动 | Task 4 |
| 独立状态 | Task 2 + Task 3 |

## Placeholder Scan

无 TBD、TODO、"implement later"、未定义的类型或函数引用。

## Type Consistency

- `ProviderUsageSnapshot` 在 Task 1 定义，Task 2 和 Task 3 中使用。
- `manager.move(from:to:)` 在 Task 2 定义，Task 4 调用。
- `manager.refreshSnapshot(for:)` 在 Task 2 定义，Task 3 和 Task 5 调用。
- `L.delete` / `L.deleteSubscriptionTitle` / `L.deleteSubscriptionMessage` 在 Task 6 定义，Task 4 使用。
