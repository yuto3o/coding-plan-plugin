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

