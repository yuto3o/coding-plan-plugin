import SwiftUI

struct SubscriptionCard: View {
    let config: ProviderConfiguration
    let snapshot: ProviderUsageSnapshot?
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAuthenticate: () -> Void
    let onStartKimiLogin: () -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var languageManager: LanguageManager

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        Button(action: onSelect) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(isSelected: isSelected))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            if snapshot.isLoading && snapshot.usage == nil {
                loadingPlaceholder
            } else if case .notAuthenticated = snapshot.error {
                notSignedInPlaceholder
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
            if config.type == .kimi {
                Button(L.login) {
                    onStartKimiLogin()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            } else {
                Button(L.login) {
                    onAuthenticate()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private func usageContent(_ usage: PlanUsage) -> some View {
        if usage.featureUsages.isEmpty, usage.balance != nil, !usage.periods.isEmpty {
            creditUsageContent(usage)
        } else if !usage.featureUsages.isEmpty {
            featureUsageContent(usage)
        } else if let total = usage.totalQuota {
            quotaRow(quota: total)
        } else {
            notSignedInPlaceholder
        }
    }

    @ViewBuilder
    private func featureUsageContent(_ usage: PlanUsage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let weeklyFeature = usage.featureUsages.first {
                quotaColumn(
                    title: L.weeklyLimit,
                    quota: weeklyFeature.detail
                )
            }

            if let firstFeature = usage.featureUsages.first,
               let hourlyLimit = firstFeature.limits.first {
                quotaColumn(
                    title: L.hourlyLimit,
                    quota: hourlyLimit.detail
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func quotaColumn(title: String, quota: Quota) -> some View {
        let remainingPercent = max(0, min(1, 1.0 - quota.usedPercent))

        HStack(spacing: 6) {
            CircularProgressView(percent: remainingPercent, color: barColor(for: remainingPercent))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
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
    private func creditUsageContent(_ usage: PlanUsage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let total = usage.totalUsage {
                totalQuotaColumn(total: total, monthlyUsed: usage.periods.first?.quotaUsed ?? 0)
            }

            if let weekly = usage.periods.dropFirst().first {
                weeklyRingColumn(breakdown: weekly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func totalQuotaColumn(total: UsageBreakdown, monthlyUsed: Int64) -> some View {
        let used = total.quotaUsed
        let limit = total.limit ?? max(1, used)
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
            return formatCompact(doubleValue / 1_000_000, suffix: "M")
        } else if absValue >= 1_000 {
            return formatCompact(doubleValue / 1_000, suffix: "K")
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
}

struct CardButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}
