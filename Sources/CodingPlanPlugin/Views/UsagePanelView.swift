import SwiftUI

struct UsagePanelView: View {
    @StateObject private var manager = ProviderManager.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager

    @State private var usage: PlanUsage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var deviceAuth: DeviceAuthorization?
    @State private var loginTask: Task<Void, Never>?
    @State private var accessTokenInput = ""
    @State private var userIDInput = ""

    private var L: LocalizedStrings { languageManager.current.strings }

    private let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView

            Group {
                if isLoading && usage == nil {
                    loadingPlaceholder
                } else if let errorMessage {
                    errorPlaceholder(errorMessage)
                } else if let usage {
                    usageContent(usage)
                } else if let provider = manager.currentProvider, !provider.isAuthenticated {
                    loginPlaceholder(provider: provider)
                } else {
                    emptyPlaceholder
                }
            }

            footerView
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(width: 400)
        .task {
            await refresh()
        }
        .onReceive(timer) { _ in
            Task { await refresh() }
        }
        .sheet(isPresented: $showSettings) {
            ProviderSettingsView()
                .frame(minWidth: 520, minHeight: 400)
                .environmentObject(languageManager)
        }
        .sheet(item: $deviceAuth) { auth in
            DeviceLoginView(
                userCode: auth.userCode,
                verificationURL: auth.verificationUriComplete,
                onCancel: {
                    loginTask?.cancel()
                    loginTask = nil
                    deviceAuth = nil
                }
            )
            .environmentObject(languageManager)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { manager.selectedID },
                set: { newValue in
                    manager.selectedID = newValue
                    usage = nil
                    errorMessage = nil
                    Task { await refresh() }
                }
            )) {
                ForEach(manager.configurations) { config in
                    Text(config.name).tag(Optional(config.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

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

    // MARK: - Placeholders

    @ViewBuilder
    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L.fetchingUsage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    @ViewBuilder
    private func errorPlaceholder(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.fetchFailed, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func loginPlaceholder(provider: any Provider) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if let config = manager.currentConfiguration {
                if config.type == .newAPI {
                    VStack(spacing: 12) {
                        SecureField(L.pasteAccessToken, text: $accessTokenInput)
                            .textFieldStyle(.roundedBorder)

                        TextField(L.userID, text: $userIDInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(L.saveAndRefresh) {
                        let token = accessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let userID = userIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty, !userID.isEmpty else { return }
                        provider.saveAccessToken(token, userID: userID)
                        accessTokenInput = ""
                        userIDInput = ""
                        Task { await refresh() }
                    }
                    .disabled(
                        accessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || userIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .padding(.top, 4)
                } else {
                    Text(L.kimLoginHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(L.login) {
                        let providerID = manager.selectedID ?? "kimi"
                        loginTask?.cancel()
                        loginTask = Task { await startKimiLogin(providerID: providerID) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(L.noUsageData)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(_ usage: PlanUsage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if usage.featureUsages.isEmpty, usage.balance != nil, !usage.periods.isEmpty {
                    creditUsageContent(usage)
                } else {
                    if let balance = usage.balance {
                        balanceSection(balance)
                    }

                    if let total = usage.totalUsage {
                        breakdownSection(total)
                    }

                    ForEach(usage.periods) { period in
                        breakdownSection(period)
                    }

                    if !usage.featureUsages.isEmpty {
                        ForEach(usage.featureUsages, id: \.scope) { feature in
                            featureSection(feature)
                        }
                    } else if let total = usage.totalQuota {
                        quotaRow(title: L.totalQuota, quota: total)
                    }
                }

                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("\(L.updated) \(usage.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxHeight: 360)
        .scrollIndicators(.hidden)
    }

    // MARK: - Sections

    @ViewBuilder
    private func balanceSection(_ quota: Quota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.accountBalance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(quota.remaining)")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            HStack {
                Text("\(L.total): \(quota.limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(L.used): \(quota.used)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func breakdownSection(_ breakdown: UsageBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(breakdown.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("Quota \(breakdown.quotaUsed) · \(breakdown.totalTokens) tokens")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                statItem(title: L.requests, value: "\(breakdown.requestCount)")
                statItem(title: L.inputTokens, value: "\(breakdown.promptTokens)")
                statItem(title: L.outputTokens, value: "\(breakdown.completionTokens)")
            }

            if !breakdown.modelUsages.isEmpty {
                DisclosureGroup(L.byModel) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(breakdown.modelUsages) { model in
                            HStack {
                                Text(model.modelName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(model.quotaUsed) · \(model.totalTokens) t")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func featureSection(_ feature: FeatureUsage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            quotaColumn(title: L.weeklyLimit, quota: feature.detail)

            if let firstLimit = feature.limits.first {
                quotaColumn(title: L.hourlyLimit, quota: firstLimit.detail)
            } else {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func quotaColumn(title: String, quota: Quota) -> some View {
        let remainingPercent = max(0, min(1, 1.0 - quota.usedPercent))

        HStack(spacing: 6) {
            CircularProgressView(
                percent: remainingPercent,
                color: barColor(for: remainingPercent)
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let resetTime = quota.resetTime {
                    CountdownLabel(target: resetTime, prefix: "\(L.reset): ", language: languageManager.current)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func quotaRow(title: String, quota: Quota) -> some View {
        let remainingPercent = max(0, min(1, 1.0 - quota.usedPercent))

        HStack(spacing: 8) {
            CircularProgressView(
                percent: remainingPercent,
                color: barColor(for: remainingPercent)
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let resetTime = quota.resetTime {
                    CountdownLabel(target: resetTime, prefix: "\(L.reset): ", language: languageManager.current)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()
        }
    }

    private func barColor(for remainingPercent: Double) -> Color {
        switch remainingPercent {
        case 0.4...1.0: return .green
        case 0.2..<0.4: return .yellow
        default: return .red
        }
    }

    // MARK: - Credit Style (New API)

    @ViewBuilder
    private func creditUsageContent(_ usage: PlanUsage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            newAPIMonthlyColumn(
                totalUsage: usage.totalUsage,
                monthlyUsed: usage.periods.first?.quotaUsed ?? 0
            )

            if usage.periods.count > 1 {
                newAPIWeeklyList(breakdown: usage.periods[1])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func newAPIMonthlyColumn(totalUsage: UsageBreakdown?, monthlyUsed: Int64) -> some View {
        let used = totalUsage?.quotaUsed ?? 0
        let limit = totalUsage?.limit ?? max(1, used)
        let remaining = max(0, limit - used)
        let remainingPercent = max(0, min(1, Double(remaining) / Double(max(1, limit))))
        let ringColor = barColor(for: remainingPercent)

        HStack(spacing: 8) {
            CircularProgressView(percent: remainingPercent, color: ringColor)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.totalQuota)
                    .font(.caption)
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
    private func newAPIWeeklyList(breakdown: UsageBreakdown) -> some View {
        let colors: [Color] = [.red, .yellow, .green, .gray]
        let total = max(1, breakdown.modelUsages.reduce(0) { $0 + $1.quotaUsed })
        let segments = breakdown.modelUsages.enumerated().map { index, model in
            RingSegment(
                name: model.modelName,
                value: Double(model.quotaUsed) / Double(total),
                color: colors[min(index, colors.count - 1)]
            )
        }

        HStack(spacing: 8) {
            MultiSegmentRingView(segments: segments)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(L.weeklyTotal)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 6, height: 6)

                        Text("\(segment.name) · \(formatQuota(Int64(segment.value * Double(total))))")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatQuota(_ value: Int64) -> String {
        let doubleValue = Double(value)
        let absValue = abs(doubleValue)

        if absValue >= 1_000_000 {
            let m = doubleValue / 1_000_000
            return formatCompact(m, suffix: "M")
        } else if absValue >= 1_000 {
            let k = doubleValue / 1_000
            return formatCompact(k, suffix: "K")
        } else {
            return String(value)
        }
    }

    private func formatCompact(_ value: Double, suffix: String) -> String {
        if value == floor(value) {
            return String(format: "%.0f%@", value, suffix)
        } else {
            return String(format: "%.1f%@", value, suffix)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 8) {
            Button {
                Task { await refresh() }
            } label: {
                Label(L.refresh, systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)

            Spacer()

            if let provider = manager.currentProvider, provider.isAuthenticated {
                Button {
                    provider.clearAuthentication()
                    usage = nil
                    errorMessage = nil
                    Task { await refresh() }
                } label: {
                    Label(L.logout, systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if let provider = manager.currentProvider {
                Button {
                    Task { try? await provider.openConsole() }
                } label: {
                    Label(L.console, systemImage: "arrow.up.forward.square")
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(L.quit, systemImage: "power")
            }
        }
        .labelStyle(.iconOnly)
        .help(L.actions)
    }

    // MARK: - Actions

    private func refresh() async {
        guard !isLoading else { return }
        guard let provider = manager.currentProvider else {
            errorMessage = L.noProvider
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard provider.isAuthenticated else {
            usage = nil
            return
        }

        do {
            let fetched = try await provider.fetchUsage()
            usage = fetched
            appState.lastUsage = fetched
            appState.lastError = nil
        } catch {
            errorMessage = error.description
            appState.lastError = error
            if case .notAuthenticated = error {
                provider.clearAuthentication()
            }
        }
    }

    private func startKimiLogin(providerID: String) async {
        let authService = KimiCodeAuthService(id: providerID)
        do {
            let auth = try await authService.startDeviceLogin()
            await MainActor.run {
                deviceAuth = auth
            }

            let deadline = Date().addingTimeInterval(auth.expiresIn ?? 900)
            _ = try await authService.pollDeviceToken(deviceCode: auth.deviceCode, deadline: deadline)

            await MainActor.run {
                deviceAuth = nil
                loginTask = nil
            }
            await refresh()
        } catch {
            await MainActor.run {
                deviceAuth = nil
                loginTask = nil
                errorMessage = error.description
            }
        }
    }
}

// MARK: - Countdown Label

struct CountdownLabel: View {
    let target: Date
    let prefix: String
    let language: AppLanguage

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var L: LocalizedStrings { language.strings }

    var body: some View {
        Text("\(prefix)\(remaining)")
            .onReceive(timer) { _ in
                now = Date()
            }
    }

    private var remaining: String {
        let diff = target.timeIntervalSince(now)
        guard diff > 0 else { return L.expired }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

// MARK: - Circular Progress

struct CircularProgressView: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2)
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: CGFloat(min(percent, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percent)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
        }
    }
}

// MARK: - Multi-Segment Ring

struct RingSegment: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

struct RingArc: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let color: Color
}

struct MultiSegmentRingView: View {
    let segments: [RingSegment]

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 4)
                .stroke(Color.gray.opacity(0.15), lineWidth: 6)

            ForEach(arcs()) { arc in
                Circle()
                    .inset(by: 4)
                    .trim(from: CGFloat(arc.start), to: CGFloat(arc.end))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: arc.end)
            }
        }
    }

    private func arcs() -> [RingArc] {
        let normalized = normalizedSegments()
        var start: Double = 0
        return normalized.map { segment in
            let end = start + segment.value
            let arc = RingArc(start: start, end: end, color: segment.color)
            start = end
            return arc
        }
    }

    private func normalizedSegments() -> [RingSegment] {
        let total = segments.reduce(0) { $0 + max(0, $1.value) }
        guard total > 0 else { return segments }
        return segments.map {
            RingSegment(name: $0.name, value: max(0, $0.value) / total, color: $0.color)
        }
    }
}
