import SwiftUI

/// Main view of the containing app.
/// Guides the user through setup and provides access to settings.
struct ContentView: View {

    @State private var isKeyboardEnabled = false
    @State private var isFullAccessGranted = false
    @State private var protocolInitialized = false
    @State private var showTestResult = false
    @State private var testResult: E2EProtocolTest.TestResult?
    @State private var showResetConfirmation = false
    @State private var showFullResetConfirmation = false
    @State private var resetStatusMessage: String?

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

                // MARK: - Protocol Test
                Section {
                    Button("Run E2E Protocol Test") {
                        testResult = E2EProtocolTest.run()
                        showTestResult = true
                    }

                    if showTestResult, let result = testResult {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                Text(result.passed ? "ALL TESTS PASSED" : "TESTS FAILED")
                                    .fontWeight(.bold)
                                    .font(.caption)
                            }
                            ScrollView {
                                Text(result.log)
                                    .font(.system(size: 9, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                } header: {
                    Text("Testing")
                }

                // MARK: - Danger Zone
                Section {
                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }

                    Button("Full Factory Reset (Keychain + Storage)", role: .destructive) {
                        showFullResetConfirmation = true
                    }

                    if let msg = resetStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Reset All Data: deletes keys, contacts, messages and re-initializes.\nFull Factory Reset: also wipes the Keychain and encryption master key. Use this if you experience session or decryption errors after reinstalling.")
                }
                .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        try? SignalStoreManager.shared.wipeAll()
                        SignalProtocolManager.shared.initialize()
                        protocolInitialized = true
                        resetStatusMessage = "All data reset. New identity created."
                    }
                } message: {
                    Text("This will delete all encryption keys, contacts, and message history. A new identity will be generated. This cannot be undone.")
                }
                .alert("Full Factory Reset?", isPresented: $showFullResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Factory Reset", role: .destructive) {
                        // 1. Wipe all Signal Protocol data
                        try? SignalStoreManager.shared.wipeAll()
                        // 2. Wipe the encryption master key from Keychain
                        try? KeychainHelper.shared.delete(forKey: "storage.masterEncryptionKey")
                        // 3. Wipe entire Keychain for our service (catches any residual data)
                        try? KeychainHelper.shared.deleteAll()
                        // 4. Re-initialize with fresh identity and fresh encryption key
                        SignalProtocolManager.shared.initialize()
                        protocolInitialized = true
                        resetStatusMessage = "Factory reset complete. All data wiped, new identity created."
                    }
                } message: {
                    Text("This will completely wipe ALL data including the iOS Keychain entries and the storage encryption key. Use this if sessions are corrupted after a reinstall. This cannot be undone.")
                }

                // MARK: - About
                Section {
                    InfoRow(title: "Version", value: "9.1.0")
                    InfoRow(title: "License", value: "GPL-3.0")
                    InfoRow(title: "Developed by", value: "R00tedbrain")
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

        // Auto-run E2E test if launched with -RUN_E2E_TEST flag
        if ProcessInfo.processInfo.arguments.contains("-RUN_E2E_TEST") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                testResult = E2EProtocolTest.run()
                showTestResult = true
            }
        }

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
