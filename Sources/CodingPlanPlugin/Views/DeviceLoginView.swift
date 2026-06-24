import SwiftUI

/// Kimi Code OAuth device-code flow login view.
struct DeviceLoginView: View {
    let userCode: String
    let verificationURL: String
    let onCancel: () -> Void

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    private var L: LocalizedStrings { languageManager.current.strings }

    var body: some View {
        VStack(spacing: 16) {
            Text(L.signInToKimi)
                .font(.headline)

            Text(L.deviceLoginHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text(L.verificationCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(userCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button(L.cancel) {
                    dismiss()
                    onCancel()
                }

                Button(L.openBrowser) {
                    if let url = URL(string: verificationURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            ProgressView()
                .controlSize(.small)
                .padding(.top, 8)
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let url = URL(string: verificationURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
