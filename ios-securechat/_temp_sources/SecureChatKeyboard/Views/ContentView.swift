import SwiftUI

/// Main view of the containing app.
/// Guides the user through setup and provides access to settings.
struct ContentView: View {

    @State private var isKeyboardEnabled = false
    @State private var isFullAccessGranted = false
    @State private var protocolInitialized = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Setup Section
                Section {
                    SetupStepRow(
                        step: 1,
                        title: "Enable Keyboard",
                        description: "Go to Settings > General > Keyboard > Keyboards > Add New Keyboard > SecureChat",
                        isCompleted: isKeyboardEnabled
                    )

                    SetupStepRow(
                        step: 2,
                        title: "Allow Full Access",
                        description: "Required for clipboard access (encrypt/decrypt). The keyboard never connects to the internet.",
                        isCompleted: isFullAccessGranted
                    )

                    SetupStepRow(
                        step: 3,
                        title: "Protocol Initialized",
                        description: "Signal Protocol keys are generated automatically on first use.",
                        isCompleted: protocolInitialized
                    )

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Setup")
                } footer: {
                    Text("This keyboard encrypts text locally before you send it through any messenger. It never connects to the internet.")
                }

                // MARK: - Security Info Section
                Section {
                    InfoRow(title: "Protocol", value: "Signal Protocol (X3DH + Double Ratchet)")
                    InfoRow(title: "Post-Quantum", value: "Kyber-1024 (PQXDH)")
                    InfoRow(title: "Key Rotation", value: "Every 2 days (automatic)")
                    InfoRow(title: "Key Storage", value: "iOS Keychain (Secure Enclave)")
                    InfoRow(title: "Network Access", value: "None (fully offline)")
                } header: {
                    Text("Security")
                }

                // MARK: - Account Section
                Section {
                    if let name = SignalProtocolManager.shared.accountName {
                        InfoRow(title: "Account UUID", value: String(name.prefix(8)) + "...")
                    }
                    InfoRow(
                        title: "Contacts",
                        value: "\(SignalProtocolManager.shared.contacts.count)"
                    )
                    InfoRow(
                        title: "Messages",
                        value: "\(SignalProtocolManager.shared.messages.count)"
                    )
                } header: {
                    Text("Account")
                }

                // MARK: - Danger Zone
                Section {
                    Button("Reset All Data", role: .destructive) {
                        try? SignalStoreManager.shared.wipeAll()
                        SignalProtocolManager.shared.initialize()
                        protocolInitialized = true
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("This will delete all encryption keys, contacts, and message history. This action cannot be undone.")
                }

                // MARK: - About
                Section {
                    InfoRow(title: "Version", value: "3.0.0")
                    InfoRow(title: "License", value: "GPL-3.0")
                    InfoRow(title: "Based on", value: "KryptEY by mellitopia & amnesica")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("SecureChat Keyboard")
            .onAppear {
                checkStatus()
            }
        }
    }

    private func checkStatus() {
        // Check if protocol is initialized
        SignalProtocolManager.shared.reloadAccount()
        protocolInitialized = SignalProtocolManager.shared.isInitialized

        // Note: There is no API to programmatically check if our keyboard extension
        // is enabled or has full access. The user must verify manually.
    }
}

// MARK: - Helper Views

struct SetupStepRow: View {
    let step: Int
    let title: String
    let description: String
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? .green : .secondary)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(step): \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    ContentView()
}
