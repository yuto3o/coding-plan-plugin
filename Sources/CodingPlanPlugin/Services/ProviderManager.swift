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
        // 清空所有 Keychain 凭证，避免下次启动时再次自动恢复。
        KeychainStorage.shared.clearAll()
        configurations = ProviderConfiguration.defaults
        selectedID = configurations.first?.id
        usageSnapshots.removeAll()
        save()
    }

    // MARK: - Token helpers

    func clearToken(for config: ProviderConfiguration) {
        switch config.type {
        case .kimi:
            KimiCodeAuthService(id: config.id).clearAuthentication()
        case .newAPI:
            guard let baseURL = config.baseURL, !baseURL.isEmpty else { return }
            NewAPIAuthService.service(for: baseURL).clear()
        }
    }

    // MARK: - Usage snapshots

    func refreshSnapshot(for id: String) async {
        guard let config = configurations.first(where: { $0.id == id }),
              let provider = Self.makeProvider(from: config) else {
            return
        }

        usageSnapshots[id] = ProviderUsageSnapshot(
            usage: usageSnapshots[id]?.usage,
            isLoading: true,
            error: nil,
            updatedAt: usageSnapshots[id]?.updatedAt
        )

        do {
            let usage = try await provider.fetchUsage()
            guard configurations.contains(where: { $0.id == id }) else { return }
            usageSnapshots[id] = ProviderUsageSnapshot(
                usage: usage,
                isLoading: false,
                error: nil,
                updatedAt: Date()
            )
        } catch {
            if case .notAuthenticated = error {
                provider.clearAuthentication()
            }
            guard configurations.contains(where: { $0.id == id }) else { return }
            usageSnapshots[id] = ProviderUsageSnapshot(
                usage: usageSnapshots[id]?.usage,
                isLoading: false,
                error: error,
                updatedAt: usageSnapshots[id]?.updatedAt
            )
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

    func refreshExistingSnapshots() async {
        let existingIDs = Array(usageSnapshots.keys)
        await withTaskGroup(of: Void.self) { group in
            for id in existingIDs {
                group.addTask {
                    await self.refreshSnapshot(for: id)
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
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let configs = try? JSONDecoder().decode([ProviderConfiguration].self, from: data) {
            // 用户已手动管理过订阅列表（即使是空数组也尊重），不再自动恢复。
            return configs
        }

        // 首次启动且 UserDefaults 没有记录时，尝试从统一 Keychain 恢复历史订阅。
        return configurationsFromKeychain()
    }

    private static func configurationsFromKeychain() -> [ProviderConfiguration] {
        let storage = KeychainStorage.shared
        var configs: [ProviderConfiguration] = []

        if storage.kimiToken() != nil {
            configs.append(ProviderConfiguration(type: .kimi, name: "Kimi Code"))
        }

        for baseURL in storage.allNewAPIBaseURLs() {
            let host = URL(string: baseURL)?.host ?? baseURL
            configs.append(ProviderConfiguration(type: .newAPI, name: host, baseURL: baseURL))
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

}
