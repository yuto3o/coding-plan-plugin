import SwiftUI

struct UsagePanelView: View {
    @StateObject private var manager = ProviderManager.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager

    @State private var isLoading = false
    @State private var showAddSheet = false
    @State private var editingConfig: ProviderConfiguration? = nil
    @State private var authenticatingConfig: ProviderConfiguration? = nil
    @State private var deviceAuth: DeviceAuthorization?
    @State private var loginTask: Task<Void, Never>?
    @State private var accessTokenInput = ""
    @State private var userIDInput = ""

    private var L: LocalizedStrings { languageManager.current.strings }

    private let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var anyOverlayShowing: Bool {
        showAddSheet || editingConfig != nil || authenticatingConfig != nil || deviceAuth != nil
    }

    var body: some View {
        ZStack {
            mainContent
                .disabled(anyOverlayShowing)
                .opacity(anyOverlayShowing ? 0.5 : 1.0)

            if showAddSheet {
                addSubscriptionOverlay
            }

            if let config = editingConfig {
                editSubscriptionOverlay(for: config)
            }

            if let config = authenticatingConfig {
                authenticationOverlay(for: config)
            }

            if let auth = deviceAuth {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 400)
        .onReceive(timer) { _ in
            Task {
                await refreshExisting()
            }
        }
        .onAppear {
            Task {
                await refresh()
            }
        }
        .onChange(of: manager.selectedID) { _ in
            syncAppStateForCurrent()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
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
            },
            onStartKimiLogin: { config in
                loginTask?.cancel()
                loginTask = Task { await startKimiLogin(providerID: config.id) }
            },
            onRetry: { config in
                Task {
                    await manager.refreshSnapshot(for: config.id)
                    syncAppState(for: config.id)
                }
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

            if let provider = manager.currentProvider, provider.isAuthenticated,
               let configID = manager.currentConfiguration?.id {
                Button {
                    provider.clearAuthentication()
                    Task {
                        await manager.refreshSnapshot(for: configID)
                        syncAppState(for: configID)
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

    private func syncAppState(for configID: String) {
        guard let snapshot = manager.usageSnapshots[configID] else {
            if manager.currentConfiguration?.id == configID {
                appState.lastUsage = nil
                appState.lastError = nil
            }
            return
        }
        if manager.currentConfiguration?.id == configID {
            appState.lastUsage = snapshot.usage
            appState.lastError = snapshot.error
        }
    }

    @ViewBuilder
    private var addSubscriptionOverlay: some View {
        ProviderEditView(
            config: nil,
            onSave: { newConfig in
                manager.add(newConfig)
                showAddSheet = false
                Task {
                    await manager.refreshSnapshot(for: newConfig.id)
                }
            },
            onCancel: {
                showAddSheet = false
            }
        )
        .environmentObject(languageManager)
    }

    @ViewBuilder
    private func editSubscriptionOverlay(for config: ProviderConfiguration) -> some View {
        ProviderEditView(
            config: config,
            onSave: { updated in
                manager.update(updated)
                editingConfig = nil
                Task {
                    await manager.refreshSnapshot(for: updated.id)
                }
            },
            onCancel: {
                editingConfig = nil
            }
        )
        .environmentObject(languageManager)
    }

    @ViewBuilder
    private func authenticationOverlay(for config: ProviderConfiguration) -> some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text(config.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)

                if config.type == .newAPI {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L.newAPILoginHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.pasteAccessToken)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("", text: $accessTokenInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.userID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("", text: $userIDInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack {
                        Button(L.cancel) {
                            authenticatingConfig = nil
                            accessTokenInput = ""
                            userIDInput = ""
                        }
                        .buttonStyle(.bordered)

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
                                syncAppState(for: config.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            accessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || userIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    .padding(.top, 4)
                } else {
                    Text(L.kimLoginHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack {
                        Button(L.cancel) {
                            authenticatingConfig = nil
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(L.login) {
                            authenticatingConfig = nil
                            loginTask?.cancel()
                            loginTask = Task { await startKimiLogin(providerID: config.id) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await manager.refreshAllSnapshots()
        syncAppStateForCurrent()
    }

    private func refreshExisting() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await manager.refreshExistingSnapshots()
        syncAppStateForCurrent()
    }

    private func syncAppStateForCurrent() {
        guard let configID = manager.currentConfiguration?.id else {
            appState.lastUsage = nil
            appState.lastError = nil
            return
        }
        syncAppState(for: configID)
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
            await manager.refreshSnapshot(for: providerID)
            syncAppState(for: providerID)
            appState.lastError = error
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

