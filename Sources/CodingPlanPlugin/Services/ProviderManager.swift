import Foundation

/// 管理所有 Provider 配置与实例。
@MainActor
final class ProviderManager: ObservableObject {
    static let shared = ProviderManager()
    private static let configKey = "coding-plan-plugin.providers"

    @Published private(set) var configurations: [ProviderConfiguration]
    @Published var selectedID: String?
    @Published var usageSnapshots: [String: ProviderUsageSnapshot] = [:]

    private init() {
        self.configurations = Self.loadConfigurations()
        self.selectedID = configurations.first?.id
    }

    var currentProvider: (any Provider)? {
        guard let selectedID else { return nil }
        return provider(for: selectedID)
    }

    var currentConfiguration: ProviderConfiguration? {
        guard let selectedID else { return nil }
        return configurations.first { $0.id == selectedID }
    }

    func provider(for id: String) -> (any Provider)? {
        guard let config = configurations.first(where: { $0.id == id }) else { return nil }
        return Self.makeProvider(from: config)
    }

    func select(id: String) {
        guard configurations.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func add(_ config: ProviderConfiguration) {
        configurations.append(config)
        save()
        if selectedID == nil {
            selectedID = config.id
        }
    }

    func update(_ config: ProviderConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == config.id }) else { return }
        configurations[index] = config
        save()
    }

    func remove(id: String) {
        // 先记录配置并清理 token，避免移除后无法定位
        let config = configurations.first { $0.id == id }
        configurations.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = configurations.first?.id
        }
        if let config {
            clearToken(for: config)
        }
        usageSnapshots.removeValue(forKey: id)
        save()
    }

    func resetToDefaults() {
        configurations = ProviderConfiguration.defaults
        selectedID = configurations.first?.id
        save()
    }

    // MARK: - Token helpers

    func saveToken(_ token: String, for configID: String) {
        guard let config = configurations.first(where: { $0.id == configID }) else { return }
        let account = Self.tokenAccount(for: config)
        try? KeychainStorage.shared.set(token, account: account)
    }

    func token(for configID: String) -> String? {
        guard let config = configurations.first(where: { $0.id == configID }) else { return nil }
        let account = Self.tokenAccount(for: config)
        return try? KeychainStorage.shared.get(account: account)
    }

    func clearToken(for config: ProviderConfiguration) {
        let account = Self.tokenAccount(for: config)
        try? KeychainStorage.shared.delete(account: account)

        // NewAPI 新版把 token + userID 合并存到单个 account，删除时一起清理。
        if config.type == .newAPI {
            let host = URL(string: config.baseURL ?? "")?.host ?? config.baseURL ?? "unknown"
            let credentialsAccount = "newapi.\(host).credentials"
            try? KeychainStorage.shared.delete(account: credentialsAccount)
        }
    }

    // MARK: - Usage snapshots

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

    func refreshAllSnapshots() async {
        await withTaskGroup(of: Void.self) { group in
            for config in configurations {
                group.addTask {
                    await self.refreshSnapshot(for: config.id)
                }
            }
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        var configs = configurations
        configs.move(fromOffsets: source, toOffset: destination)
        configurations = configs
        save()
    }

    // MARK: - Private

    private func save() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    private static func loadConfigurations() -> [ProviderConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: Self.configKey),
              let configs = try? JSONDecoder().decode([ProviderConfiguration].self, from: data),
              !configs.isEmpty else {
            return ProviderConfiguration.defaults
        }
        return configs
    }

    private static func makeProvider(from config: ProviderConfiguration) -> (any Provider)? {
        switch config.type {
        case .kimi:
            return KimiProvider(id: config.id, name: config.name)
        case .newAPI:
            guard let baseURL = config.baseURL, !baseURL.isEmpty else { return nil }
            return NewAPIProvider(
                id: config.id,
                name: config.name,
                baseURL: baseURL,
                consolePath: config.consolePath ?? "/console"
            )
        }
    }

    private static func tokenAccount(for config: ProviderConfiguration) -> String {
        switch config.type {
        case .kimi:
            return "kimi.access_token"
        case .newAPI:
            let host = URL(string: config.baseURL ?? "")?.host ?? config.baseURL ?? "unknown"
            return "newapi.\(host).access_token"
        }
    }
}
