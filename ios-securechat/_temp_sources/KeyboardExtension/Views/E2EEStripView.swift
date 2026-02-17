import UIKit

/// The E2EE control strip displayed above the keyboard.
/// Provides encrypt/decrypt buttons, contact selector, and mode switching.
/// Equivalent to Android's E2EEStripView with its 6 switchable views.
///
/// Views:
///   0 - Main: Encrypt, Decrypt, Contact selector, Chat, Help, Encoding toggle
///   1 - Add Contact: First name, Last name, Add button
///   2 - Contact List: Scrollable contacts with select/remove/verify
///   3 - Messages: Chat history with selected contact
///   4 - Help: FAQ and version info
///   5 - Verify: Fingerprint code display
class E2EEStripView: UIView {

    weak var delegate: E2EEStripDelegate?

    // MARK: - State

    private var currentView: Int = 0
    private var selectedContact: Contact?
    private var currentEncodingMode: EncodingMode = .raw

    // MARK: - Main View Controls

    private let encryptButton = UIButton(type: .system)
    private let decryptButton = UIButton(type: .system)
    private let contactButton = UIButton(type: .system)
    private let chatButton = UIButton(type: .system)
    private let encodingToggle = UIButton(type: .system)
    private let pasteDecryptButton = UIButton(type: .system)

    // MARK: - Stack

    private let mainStack = UIStackView()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMainView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMainView()
    }

    // MARK: - Setup

    private func setupMainView() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        // Configure buttons
        encryptButton.setTitle("Encrypt", for: .normal)
        encryptButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        encryptButton.addTarget(self, action: #selector(encryptTapped), for: .touchUpInside)

        decryptButton.setTitle("Decrypt", for: .normal)
        decryptButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        decryptButton.isEnabled = false
        decryptButton.addTarget(self, action: #selector(decryptTapped), for: .touchUpInside)

        pasteDecryptButton.setTitle("Paste+Decrypt", for: .normal)
        pasteDecryptButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        pasteDecryptButton.addTarget(self, action: #selector(pasteAndDecryptTapped), for: .touchUpInside)

        contactButton.setTitle("Contacts", for: .normal)
        contactButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        contactButton.addTarget(self, action: #selector(contactsTapped), for: .touchUpInside)

        chatButton.setTitle("Chat", for: .normal)
        chatButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)

        encodingToggle.setTitle("RAW", for: .normal)
        encodingToggle.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        encodingToggle.addTarget(self, action: #selector(toggleEncoding), for: .touchUpInside)

        // Layout
        mainStack.axis = .horizontal
        mainStack.distribution = .fillEqually
        mainStack.spacing = 4
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(encryptButton)
        mainStack.addArrangedSubview(decryptButton)
        mainStack.addArrangedSubview(pasteDecryptButton)
        mainStack.addArrangedSubview(contactButton)
        mainStack.addArrangedSubview(chatButton)
        mainStack.addArrangedSubview(encodingToggle)

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        updateContactLabel()
    }

    // MARK: - Actions

    @objc private func encryptTapped() {
        // TODO: Get text from input field, encrypt with selected contact, copy to clipboard
        guard let contact = selectedContact else {
            showTemporaryMessage("Select a contact first")
            return
        }

        // For now, read from a text buffer or input approach
        // The user types text, then taps Encrypt
        // The encrypted envelope is copied to clipboard for pasting into any messenger
        Logger.log("Encrypt tapped for contact: \(contact.displayName)")

        // TODO: Integrate with SignalProtocolManager.shared.encrypt(...)
        // let envelope = SignalProtocolManager.shared.encrypt(message: text, for: contact)
        // let encoded = currentEncodingMode.encoder.encode(envelope)
        // UIPasteboard.general.string = encoded
    }

    @objc private func decryptTapped() {
        Logger.log("Decrypt tapped")
        // TODO: Decrypt the current clipboard content
    }

    @objc private func pasteAndDecryptTapped() {
        // iOS-specific: explicit paste + decrypt (no clipboard listener available)
        guard let clipboardText = UIPasteboard.general.string else {
            showTemporaryMessage("Clipboard is empty")
            return
        }

        Logger.log("Paste & Decrypt tapped, clipboard length: \(clipboardText.count)")

        do {
            let envelope = try currentEncodingMode.encoder.decode(clipboardText)
            guard let messageType = MessageType.from(envelope) else {
                showTemporaryMessage("Unknown message format")
                return
            }

            switch messageType {
            case .preKeyResponseMessage:
                // This is an invite — extract sender info
                Logger.log("PreKeyResponse (invite) detected")
                // TODO: Show UI to add contact from this invite
                showTemporaryMessage("Invite received")

            case .signalMessage, .updatedPreKeyResponseAndSignalMessage:
                // Decrypt the message
                guard let contact = findContact(for: envelope) else {
                    showTemporaryMessage("Unknown sender")
                    return
                }
                let plaintext = try SignalProtocolManager.shared.decrypt(
                    envelope: envelope, from: contact
                )
                delegate?.insertText(plaintext)

                // Clear clipboard after decryption
                UIPasteboard.general.string = ""
            }
        } catch {
            Logger.error("Decryption failed: \(error)")
            showTemporaryMessage("Decryption failed")
        }
    }

    @objc private func contactsTapped() {
        Logger.log("Contacts tapped")
        // TODO: Switch to contacts view (view 2)
    }

    @objc private func chatTapped() {
        Logger.log("Chat tapped")
        // TODO: Switch to messages view (view 3)
    }

    @objc private func toggleEncoding() {
        let allModes = EncodingMode.allCases
        guard let currentIndex = allModes.firstIndex(of: currentEncodingMode) else { return }
        let nextIndex = (currentIndex + 1) % allModes.count
        currentEncodingMode = allModes[nextIndex]
        encodingToggle.setTitle(currentEncodingMode.rawValue.uppercased(), for: .normal)
        Logger.log("Encoding mode: \(currentEncodingMode.rawValue)")
    }

    // MARK: - Helpers

    private func findContact(for envelope: MessageEnvelope) -> Contact? {
        return SignalProtocolManager.shared.contacts.first {
            $0.signalProtocolAddressName == envelope.signalProtocolAddressName
                && $0.deviceId == envelope.deviceId
        }
    }

    private func updateContactLabel() {
        if let contact = selectedContact {
            contactButton.setTitle(contact.firstName, for: .normal)
        } else {
            contactButton.setTitle("Contacts", for: .normal)
        }
    }

    private func showTemporaryMessage(_ message: String) {
        // Brief visual feedback on the strip
        let originalTitle = encryptButton.title(for: .normal)
        encryptButton.setTitle(message, for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.encryptButton.setTitle(originalTitle, for: .normal)
        }
    }

    // MARK: - Public

    func selectContact(_ contact: Contact) {
        selectedContact = contact
        updateContactLabel()
        decryptButton.isEnabled = true
    }
}
