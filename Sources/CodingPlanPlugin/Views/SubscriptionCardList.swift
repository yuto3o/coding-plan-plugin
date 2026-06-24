import SwiftUI

struct SubscriptionCardList: View {
    @EnvironmentObject private var manager: ProviderManager
    @EnvironmentObject private var languageManager: LanguageManager

    let onEdit: (ProviderConfiguration) -> Void
    let onAuthenticate: (ProviderConfiguration) -> Void
    let onStartKimiLogin: (ProviderConfiguration) -> Void
    let onRetry: (ProviderConfiguration) -> Void

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
                        manager.remove(id: config.id)
                    },
                    onAuthenticate: {
                        onAuthenticate(config)
                    },
                    onStartKimiLogin: {
                        onStartKimiLogin(config)
                    },
                    onRetry: {
                        onRetry(config)
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
                    let indexSet = IndexSet(integer: sourceIndex)
                    let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                    manager.move(from: indexSet, to: destination)
                    return true
                }
            }
        }
    }
}
