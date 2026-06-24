import SwiftUI

struct ProviderEditView: View {
    let config: ProviderConfiguration?
    let onSave: (ProviderConfiguration) -> Void
    var onCancel: (() -> Void)? = nil

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: ProviderType = .newAPI
    @State private var baseURL = ""
    @State private var consolePath = "/console"

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text(config == nil ? L.addSubscriptionTitle : L.editSubscriptionTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 14) {
                    labeledField(title: L.displayName) {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    labeledField(title: L.type) {
                        Picker("", selection: $type) {
                            ForEach(ProviderType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if type == .newAPI {
                        labeledField(title: L.baseURLPlaceholder) {
                            TextField("https://", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: L.consolePathPlaceholder) {
                            TextField("/console", text: $consolePath)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                HStack {
                    Button(L.cancel) {
                        if let onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)

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
                    .buttonStyle(.borderedProminent)
                    .disabled(type == .newAPI && baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
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
        .onAppear {
            if let config {
                name = config.name
                type = config.type
                baseURL = config.baseURL ?? ""
                consolePath = config.consolePath ?? "/console"
            } else {
                name = ""
                type = .newAPI
                baseURL = ""
                consolePath = "/console"
            }
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
