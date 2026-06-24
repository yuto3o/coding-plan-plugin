import SwiftUI

struct UsagePanelView: View {
    @StateObject private var manager = ProviderManager.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager

    @State private var isLoading = false
    @State private var showSettings = false
    @State private var showAddSheet = false
    @State private var editingConfig: ProviderConfiguration? = nil
    @State private var authenticatingConfig: ProviderConfiguration? = nil
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
                if isLoading && manager.configurations.isEmpty {
                    loadingPlaceholder
                } else if manager.configurations.isEmpty {
                    emptyPlaceholder
                } else {
                    cardListView
                }
            }

            footerView
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(width: 400)
        .task {
            await manager.refreshAllSnapshots()
        }
        .onReceive(timer) { _ in
            Task {
                await manager.refreshExistingSnapshots()
            }
        }
        .sheet(isPresented: $showSettings) {
            ProviderSettingsView()
                .frame(minWidth: 520, minHeight: 400)
                .environmentObject(languageManager)
        }
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
        .sheet(item: $authenticatingConfig) { config in
            authenticationSheet(for: config)
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

    // MARK: - Card List

    @ViewBuilder
    private var cardListView: some View {
        SubscriptionCardList(
            onEdit: { config in
                editingConfig = config
            },
            onAuthenticate: { config in
                authenticatingConfig = config
            }
        )
        .environmentObject(manager)
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
                    if let configID = manager.currentConfiguration?.id {
                        Task {
                            await manager.refreshSnapshot(for: configID)
                            syncAppState()
                        }
                    }
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

    @ViewBuilder
    private func authenticationSheet(for config: ProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(config.name)
                .font(.headline)

            if config.type == .newAPI {
                VStack(spacing: 12) {
                    SecureField(L.pasteAccessToken, text: $accessTokenInput)
                        .textFieldStyle(.roundedBorder)

                    TextField(L.userID, text: $userIDInput)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button(L.cancel) {
                        authenticatingConfig = nil
                        accessTokenInput = ""
                        userIDInput = ""
                    }
                    Spacer()
                    Button(L.saveAndRefresh) {
                        let token = accessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let userID = userIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty, !userID.isEmpty,
                              let provider = manager.provider(for: config.id) else { return }
                        provider.saveAccessToken(token, userID: userID)
                        accessTokenInput = ""
                        userIDInput = ""
                        authenticatingConfig = nil
                        Task {
                            await manager.refreshSnapshot(for: config.id)
                            syncAppState()
                        }
                    }
                    .disabled(
                        accessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || userIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            } else {
                Text(L.kimLoginHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button(L.cancel) {
                        authenticatingConfig = nil
                    }
                    Spacer()
                    Button(L.login) {
                        authenticatingConfig = nil
                        loginTask?.cancel()
                        loginTask = Task { await startKimiLogin(providerID: config.id) }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360)
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await manager.refreshAllSnapshots()
        syncAppState()
    }

    private func syncAppState() {
        guard let configID = manager.currentConfiguration?.id,
              let snapshot = manager.usageSnapshots[configID] else {
            appState.lastUsage = nil
            appState.lastError = nil
            return
        }
        appState.lastUsage = snapshot.usage
        appState.lastError = snapshot.error
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

