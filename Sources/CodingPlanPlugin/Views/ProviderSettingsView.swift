import SwiftUI

struct ProviderSettingsView: View {
    @StateObject private var manager = ProviderManager.shared
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false
    @State private var editingConfig: ProviderConfiguration? = nil

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L.subscriptions)
                    .font(.headline)
                Spacer()
                Button(L.done) {
                    dismiss()
                }
            }

            List {
                ForEach(manager.configurations) { config in
                    ProviderConfigRow(config: config) {
                        editingConfig = config
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let config = manager.configurations[index]
                        manager.remove(id: config.id)
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Button {
                    showAddSheet = true
                } label: {
                    Label(L.addSubscription, systemImage: "plus")
                }

                Spacer()

                Button {
                    manager.resetToDefaults()
                } label: {
                    Label(L.resetDefaults, systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            ProviderEditView(config: nil, onSave: { newConfig in
                manager.add(newConfig)
                showAddSheet = false
            })
            .frame(minWidth: 400, minHeight: 260)
            .environmentObject(languageManager)
        }
        .sheet(item: $editingConfig) { config in
            ProviderEditView(config: config, onSave: { updated in
                manager.update(updated)
                editingConfig = nil
            })
            .frame(minWidth: 400, minHeight: 260)
            .environmentObject(languageManager)
        }
    }
}

struct ProviderConfigRow: View {
    let config: ProviderConfiguration
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(config.type.displayName + (config.baseURL.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ProviderEditView: View {
    let config: ProviderConfiguration?
    let onSave: (ProviderConfiguration) -> Void

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: ProviderType = .newAPI
    @State private var baseURL = ""
    @State private var consolePath = "/console"

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(config == nil ? L.addSubscriptionTitle : L.editSubscriptionTitle)
                .font(.headline)

            Form {
                TextField(L.displayName, text: $name)

                Picker(L.type, selection: $type) {
                    ForEach(ProviderType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                if type == .newAPI {
                    TextField(L.baseURLPlaceholder, text: $baseURL)
                    TextField(L.consolePathPlaceholder, text: $consolePath)
                }
            }

            HStack {
                Button(L.cancel) {
                    dismiss()
                }
                Spacer()
                Button(L.save) {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else { return }

                    let newConfig = ProviderConfiguration(
                        id: config?.id ?? UUID().uuidString,
                        type: type,
                        name: trimmedName,
                        baseURL: type == .newAPI ? trimmedURL : nil,
                        consolePath: type == .newAPI ? (consolePath.isEmpty ? "/console" : consolePath) : nil
                    )
                    onSave(newConfig)
                }
                .disabled(type == .newAPI && baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
        .onAppear {
            if let config {
                name = config.name
                type = config.type
                baseURL = config.baseURL ?? ""
                consolePath = config.consolePath ?? "/console"
            }
        }
    }
}
