import UIKit

// ---------------------------------------------------------------------------
// MARK: - Delegate
// ---------------------------------------------------------------------------

protocol E2EEStripDelegate: AnyObject {
    func insertText(_ text: String)
    func requestHeightChange(expanded: Bool)
}

// ---------------------------------------------------------------------------
// MARK: - FakeTextField (UILabel that behaves like a text field)
// ---------------------------------------------------------------------------

/// A UILabel styled to look like a UITextField.
/// Keyboard extensions cannot use real UITextFields for internal input
/// because they steal firstResponder from the host app's textDocumentProxy.
/// Instead, this label receives characters from KeyboardView via manual methods.
private class FakeTextField: UIView {

    private let textLabel = UILabel()
    private let placeholderLabel = UILabel()
    private let cursor = UIView()
    private var cursorTimer: Timer?

    /// The placeholder text shown when empty.
    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    /// The current text content.
    var text: String = "" {
        didSet {
            textLabel.text = text
            placeholderLabel.isHidden = !text.isEmpty
            accessibilityValue = text.isEmpty ? placeholder : text
        }
    }

    /// Whether this field is "active" (receiving key input).
    var isActive: Bool = false {
        didSet {
            cursor.isHidden = !isActive
            if isActive {
                layer.borderColor = UIColor.systemBlue.cgColor
                startCursorBlink()
                accessibilityTraits = [.staticText, .selected]
            } else {
                layer.borderColor = UIColor.systemGray4.cgColor
                stopCursorBlink()
                accessibilityTraits = .staticText
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.systemGray5
        layer.cornerRadius = 6
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemGray4.cgColor
        clipsToBounds = true

        // Accessibility: behave like a text field
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "Secret message input"
        accessibilityHint = "Tap to start typing your encrypted message"

        // Placeholder
        placeholderLabel.text = "Type your secret message here"
        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)

        // Text
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .label
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isAccessibilityElement = false
        addSubview(textLabel)

        // Cursor (blinking bar)
        cursor.backgroundColor = .systemBlue
        cursor.isHidden = true
        cursor.translatesAutoresizingMaskIntoConstraints = false
        cursor.isAccessibilityElement = false
        addSubview(cursor)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.trailingAnchor.constraint(equalTo: cursor.leadingAnchor, constant: -1),

            cursor.widthAnchor.constraint(equalToConstant: 2),
            cursor.heightAnchor.constraint(equalToConstant: 16),
            cursor.centerYAnchor.constraint(equalTo: centerYAnchor),
            cursor.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])

        // Move cursor next to text
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func insertCharacter(_ ch: String) {
        text += ch
    }

    func deleteLastCharacter() {
        guard !text.isEmpty else { return }
        text = String(text.dropLast())
    }

    private func startCursorBlink() {
        stopCursorBlink()
        cursor.alpha = 1
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursor.alpha = self.cursor.alpha == 1 ? 0 : 1
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursor.alpha = 0
    }
}

// ---------------------------------------------------------------------------
// MARK: - E2EEStripView
// ---------------------------------------------------------------------------

/// E2EE control strip — mirrors the Android layout exactly:
///
///   "No contact chosen"
///   [Type your secret message here          ]
///   [Chat]  [Lock]  [Envelope+Lock]  [Person]  [?]
///
/// Views:
///   0 - Main     : info + input field + 5 icon buttons
///   1 - AddContact: name fields + add/cancel
///   2 - ContactList: scrollable contacts with select/delete/verify
///   3 - Messages : chat history
///   4 - Help     : Q&A
///   5 - Verify   : fingerprint
class E2EEStripView: UIView {

    weak var delegate: E2EEStripDelegate?

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    private enum ViewMode: Int { case main, addContact, contactList, messages, help, verify }
    private var currentMode: ViewMode = .main
    private var chosenContact: Contact?
    private var currentEncodingMode: EncodingMode = .raw
    private var pendingEnvelope: MessageEnvelope?

    // -----------------------------------------------------------------------
    // 6 container views
    // -----------------------------------------------------------------------

    private let mainContainer       = UIView()
    private let addContactContainer = UIView()
    private let contactListContainer = UIView()
    private let messagesContainer   = UIView()
    private let helpContainer       = UIView()
    private let verifyContainer     = UIView()

    private var allContainers: [UIView] {
        [mainContainer, addContactContainer, contactListContainer,
         messagesContainer, helpContainer, verifyContainer]
    }

    // -----------------------------------------------------------------------
    // View 0 - Main (Android-like layout)
    // -----------------------------------------------------------------------

    private let infoLabel   = UILabel()
    private let inputField  = FakeTextField()

    // 5 icon buttons matching Android order:
    // [Chat/Messages] [Lock/Decrypt] [Envelope+Lock/Encrypt] [Person/Contacts] [?/Help]
    private let chatIconBtn     = UIButton(type: .system)   // 1 - message history
    private let lockIconBtn     = UIButton(type: .system)   // 2 - lock (decrypt clipboard / process invite)
    private let encryptIconBtn  = UIButton(type: .system)   // 3 - envelope+lock (encrypt typed msg)
    private let contactIconBtn  = UIButton(type: .system)   // 4 - person (contacts)
    private let helpIconBtn     = UIButton(type: .system)   // 5 - ? (help)

    // Paste button next to input field (reads clipboard immediately)
    private let pasteBtn        = UIButton(type: .system)

    // Hidden toggle for encoding mode (long press on encrypt icon)
    private var encodingLabel = UILabel()

    // -----------------------------------------------------------------------
    // View 1 - Add Contact
    // -----------------------------------------------------------------------

    private let addContactInfoLabel     = UILabel()
    private let firstNameField          = FakeTextField()
    private let lastNameField           = FakeTextField()
    private let addContactAddButton     = UIButton(type: .system)
    private let addContactCancelButton  = UIButton(type: .system)

    // -----------------------------------------------------------------------
    // View 2 - Contact List
    // -----------------------------------------------------------------------

    private let contactListInfoLabel  = UILabel()
    private let contactTableView      = UITableView()
    private let contactListBackButton = UIButton(type: .system)
    private let contactListInviteBtn  = UIButton(type: .system)

    // -----------------------------------------------------------------------
    // View 3 - Messages
    // -----------------------------------------------------------------------

    private let messagesInfoLabel    = UILabel()
    private let messagesTableView    = UITableView()
    private let messagesBackButton   = UIButton(type: .system)
    private let messagesDeleteButton = UIButton(type: .system)

    // -----------------------------------------------------------------------
    // View 4 - Help
    // -----------------------------------------------------------------------

    private let helpInfoLabel  = UILabel()
    private let helpTextView   = UITextView()
    private let helpBackButton = UIButton(type: .system)

    // -----------------------------------------------------------------------
    // View 5 - Verify
    // -----------------------------------------------------------------------

    private let verifyInfoLabel    = UILabel()
    private var codeLabels: [UILabel] = []
    private let verifyBackButton   = UIButton(type: .system)
    private let verifyConfirmButton = UIButton(type: .system)

    // -----------------------------------------------------------------------
    // Table data
    // -----------------------------------------------------------------------

    private var contactListData: [Contact] = []
    private var messagesData: [StorageMessage] = []

    // -----------------------------------------------------------------------
    // MARK: - Init
    // -----------------------------------------------------------------------

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    private func buildUI() {
        backgroundColor = UIColor.secondarySystemBackground
        clipsToBounds = true

        // Accessibility: this is a container, not a single element
        isAccessibilityElement = false
        shouldGroupAccessibilityChildren = true
        accessibilityLabel = "SecureChat Controls"

        for c in allContainers {
            c.translatesAutoresizingMaskIntoConstraints = false
            c.isAccessibilityElement = false
            c.shouldGroupAccessibilityChildren = true
            addSubview(c)
            NSLayoutConstraint.activate([
                c.topAnchor.constraint(equalTo: topAnchor),
                c.leadingAnchor.constraint(equalTo: leadingAnchor),
                c.trailingAnchor.constraint(equalTo: trailingAnchor),
                c.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        buildMainView()
        buildAddContactView()
        buildContactListView()
        buildMessagesView()
        buildHelpView()
        buildVerifyView()
        showView(.main)
    }

    // ===========================  VIEW 0 - MAIN  ===========================

    private func buildMainView() {
        // Info label
        infoLabel.font = .systemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = .secondaryLabel
        infoLabel.text = "No contact chosen"
        infoLabel.textAlignment = .center
        infoLabel.isAccessibilityElement = true
        infoLabel.accessibilityLabel = "Status"
        infoLabel.accessibilityValue = "No contact chosen"
        infoLabel.accessibilityTraits = .staticText

        // Input field "Type your secret message here"
        // Uses FakeTextField (a UILabel) instead of UITextField because
        // keyboard extensions cannot host real text fields (steals firstResponder).
        let inputTap = UITapGestureRecognizer(target: self, action: #selector(inputFieldTapped))
        inputField.addGestureRecognizer(inputTap)
        inputField.isUserInteractionEnabled = true

        // Paste button — reads clipboard IMMEDIATELY into the input field
        // Solves the problem where apps with Face ID lock (e.g. WhatsApp) clear the
        // clipboard when switching away. User taps Paste right after switching to keyboard.
        let pasteConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        pasteBtn.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: pasteConfig), for: .normal)
        pasteBtn.tintColor = .systemBlue
        pasteBtn.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        pasteBtn.accessibilityLabel = "Paste from clipboard"
        pasteBtn.accessibilityHint = "Paste clipboard content into the input field. Use this if Lock cannot read the clipboard."
        pasteBtn.setContentHuggingPriority(.required, for: .horizontal)
        pasteBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 5 icon buttons (matching Android)
        let iconSize: CGFloat = 22
        let iconConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

        // 1 - Chat history (speech bubble)
        chatIconBtn.setImage(UIImage(systemName: "message.fill", withConfiguration: iconConfig), for: .normal)
        chatIconBtn.tintColor = .systemGray
        chatIconBtn.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)
        chatIconBtn.accessibilityLabel = "Messages"
        chatIconBtn.accessibilityHint = "View message history with selected contact"

        // 2 - Lock (decrypt / process invite from clipboard)
        lockIconBtn.setImage(UIImage(systemName: "lock.fill", withConfiguration: iconConfig), for: .normal)
        lockIconBtn.tintColor = .systemGray
        lockIconBtn.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        lockIconBtn.accessibilityLabel = "Decrypt"
        lockIconBtn.accessibilityHint = "Decrypt message or process invite from clipboard"

        // 3 - Envelope+Lock (encrypt typed message)
        encryptIconBtn.setImage(UIImage(systemName: "envelope.badge.shield.half.filled.fill", withConfiguration: iconConfig), for: .normal)
        encryptIconBtn.tintColor = .systemGray
        encryptIconBtn.addTarget(self, action: #selector(encryptTapped), for: .touchUpInside)
        encryptIconBtn.accessibilityLabel = "Encrypt"
        encryptIconBtn.accessibilityHint = "Encrypt typed message and paste into chat. Long press to change encoding mode"
        // Long press to toggle encoding
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(encodingLongPress(_:)))
        lp.minimumPressDuration = 0.5
        encryptIconBtn.addGestureRecognizer(lp)

        // 4 - Person (contacts)
        contactIconBtn.setImage(UIImage(systemName: "person.fill", withConfiguration: iconConfig), for: .normal)
        contactIconBtn.tintColor = .systemGray
        contactIconBtn.addTarget(self, action: #selector(contactsTapped), for: .touchUpInside)
        contactIconBtn.accessibilityLabel = "Contacts"
        contactIconBtn.accessibilityHint = "Manage contacts, send invitations"

        // 5 - Help
        helpIconBtn.setImage(UIImage(systemName: "questionmark.circle.fill", withConfiguration: iconConfig), for: .normal)
        helpIconBtn.tintColor = .systemGray
        helpIconBtn.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        helpIconBtn.accessibilityLabel = "Help"
        helpIconBtn.accessibilityHint = "View instructions and information"

        // Small encoding mode indicator
        encodingLabel.font = .systemFont(ofSize: 8, weight: .bold)
        encodingLabel.textColor = .tertiaryLabel
        encodingLabel.text = "RAW"
        encodingLabel.textAlignment = .center
        encodingLabel.isAccessibilityElement = true
        encodingLabel.accessibilityLabel = "Encoding mode"
        encodingLabel.accessibilityValue = "RAW"

        // Layout: icon buttons row -- use fillEqually for reliable hit-testing
        let iconStack = UIStackView(arrangedSubviews: [chatIconBtn, lockIconBtn, encryptIconBtn, contactIconBtn, helpIconBtn])
        iconStack.axis = .horizontal
        iconStack.distribution = .fillEqually
        iconStack.alignment = .fill
        iconStack.spacing = 4

        // Input row: [input field] [paste button]
        let inputRow = UIStackView(arrangedSubviews: [inputField, pasteBtn])
        inputRow.axis = .horizontal
        inputRow.spacing = 6
        inputRow.alignment = .center

        // VStack: info, inputRow, icons, encoding label
        let vStack = UIStackView(arrangedSubviews: [infoLabel, inputRow, iconStack, encodingLabel])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false

        mainContainer.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: mainContainer.topAnchor, constant: 4),
            vStack.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor, constant: 10),
            vStack.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor, constant: -10),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: mainContainer.bottomAnchor, constant: -2),
            inputField.heightAnchor.constraint(equalToConstant: 30),
            pasteBtn.widthAnchor.constraint(equalToConstant: 32),
            iconStack.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // ========================  VIEW 1 - ADD CONTACT  ========================

    /// Which add-contact field is active (nil = none, routes keys to host app)
    private enum ActiveContactField { case firstName, lastName }
    private var activeContactField: ActiveContactField?

    private func buildAddContactView() {
        addContactInfoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        addContactInfoLabel.textColor = .secondaryLabel
        addContactInfoLabel.text = "Add contact - tap a field to type"

        firstNameField.placeholder = "First name (required)"
        firstNameField.accessibilityLabel = "First name"
        firstNameField.accessibilityHint = "Required. Tap to type contact first name"
        let fnTap = UITapGestureRecognizer(target: self, action: #selector(firstNameFieldTapped))
        firstNameField.addGestureRecognizer(fnTap)
        firstNameField.isUserInteractionEnabled = true

        lastNameField.placeholder = "Last name (optional)"
        lastNameField.accessibilityLabel = "Last name"
        lastNameField.accessibilityHint = "Optional. Tap to type contact last name"
        let lnTap = UITapGestureRecognizer(target: self, action: #selector(lastNameFieldTapped))
        lastNameField.addGestureRecognizer(lnTap)
        lastNameField.isUserInteractionEnabled = true

        configBtn(addContactAddButton,    title: "Add",    size: 13, weight: .semibold, action: #selector(addContactConfirmTapped))
        configBtn(addContactCancelButton, title: "Cancel", size: 13, weight: .medium,   action: #selector(addContactCancelTapped))

        let row = hStack([firstNameField, lastNameField, addContactAddButton, addContactCancelButton], spacing: 6)
        firstNameField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        lastNameField.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let vStack = UIStackView(arrangedSubviews: [addContactInfoLabel, row])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addContactContainer.addSubview(vStack)
        pinFill(vStack, in: addContactContainer, h: 6, v: 4)
    }

    @objc private func firstNameFieldTapped() {
        activeContactField = .firstName
        firstNameField.isActive = true
        lastNameField.isActive = false
        deactivateSecretInput()
    }

    @objc private func lastNameFieldTapped() {
        activeContactField = .lastName
        firstNameField.isActive = false
        lastNameField.isActive = true
        deactivateSecretInput()
    }

    private func deactivateContactFields() {
        activeContactField = nil
        firstNameField.isActive = false
        lastNameField.isActive = false
    }

    // ======================  VIEW 2 - CONTACT LIST  =========================

    private func buildContactListView() {
        contactListInfoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        contactListInfoLabel.textColor = .secondaryLabel
        contactListInfoLabel.text = "Choose your chat partner"

        contactTableView.register(ContactCell.self, forCellReuseIdentifier: ContactCell.reuseId)
        contactTableView.dataSource = self
        contactTableView.delegate   = self
        contactTableView.rowHeight  = 36
        contactTableView.separatorInset = .zero
        contactTableView.backgroundColor = .clear

        configBtn(contactListBackButton, title: "Back",   size: 13, weight: .medium,   action: #selector(contactListBackTapped))
        contactListBackButton.accessibilityLabel = "Back"
        contactListBackButton.accessibilityHint = "Return to main view"
        configBtn(contactListInviteBtn,  title: "Invite", size: 13, weight: .semibold, action: #selector(contactListInviteTapped))
        contactListInviteBtn.accessibilityLabel = "Send Invite"
        contactListInviteBtn.accessibilityHint = "Generate and send invitation to add you as a contact"

        let topRow = hStack([contactListInfoLabel, contactListBackButton, contactListInviteBtn], spacing: 8)
        let vStack = UIStackView(arrangedSubviews: [topRow, contactTableView])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        contactListContainer.addSubview(vStack)
        pinFill(vStack, in: contactListContainer, h: 6, v: 4)
    }

    // ========================  VIEW 3 - MESSAGES  ===========================

    private func buildMessagesView() {
        messagesInfoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        messagesInfoLabel.textColor = .secondaryLabel
        messagesInfoLabel.text = "Messages"

        messagesTableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        messagesTableView.dataSource = self
        messagesTableView.delegate   = self
        messagesTableView.rowHeight  = UITableView.automaticDimension
        messagesTableView.estimatedRowHeight = 30
        messagesTableView.separatorStyle = .none
        messagesTableView.backgroundColor = .clear

        configBtn(messagesBackButton,   title: "Back",   size: 13, weight: .medium, action: #selector(messagesBackTapped))
        messagesBackButton.accessibilityLabel = "Back"
        messagesBackButton.accessibilityHint = "Return to main view"
        configBtn(messagesDeleteButton, title: "Delete All", size: 13, weight: .medium, action: #selector(messagesDeleteTapped))
        messagesDeleteButton.setTitleColor(.systemRed, for: .normal)
        messagesDeleteButton.accessibilityLabel = "Delete All"
        messagesDeleteButton.accessibilityHint = "Delete all messages with this contact"

        let topRow = hStack([messagesInfoLabel, messagesDeleteButton, messagesBackButton], spacing: 8)
        let vStack = UIStackView(arrangedSubviews: [topRow, messagesTableView])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        messagesContainer.addSubview(vStack)
        pinFill(vStack, in: messagesContainer, h: 6, v: 4)
    }

    // ============================  VIEW 4 - HELP  ===========================

    private func buildHelpView() {
        helpInfoLabel.font = .systemFont(ofSize: 11, weight: .bold)
        helpInfoLabel.text = "Q&A"

        helpTextView.font = .systemFont(ofSize: 11)
        helpTextView.isEditable = false
        helpTextView.isScrollEnabled = true
        helpTextView.backgroundColor = .clear
        helpTextView.text = """
What is SecureChat Keyboard?
A keyboard that encrypts your messages locally using Signal Protocol (X3DH + Double Ratchet) with post-quantum Kyber-1024 (PQXDH). It works inside any messaging app (WhatsApp, Telegram, iMessage, etc.) and NEVER connects to the internet. All encryption happens on your device.

--- THE 5 ICONS ---

1. Chat bubble = Message history with selected contact
2. Lock = Smart decrypt (reads clipboard, detects invites or encrypted messages)
3. Envelope+Lock = Encrypt your typed message and paste it into the chat
4. Person = Contacts list (select, add, delete, verify, invite)
5. ? = This help screen

--- HOW TO ADD A CONTACT ---

Method A - You invite someone:
1. Tap the Person icon to open Contacts.
2. Tap "Invite" -- an invite text is copied to your clipboard.
3. Paste the invite into any messenger and send it to your contact.
4. Your contact must also have SecureChat Keyboard installed.
5. Your contact copies your invite, then taps the Lock icon.
6. They will be prompted to enter your name and tap "Add".
7. Done! You are now connected.

Method B - Someone invites you:
1. Copy the invite text that someone sent you.
2. Tap the Lock icon -- it will detect the invite automatically.
3. Enter the contact's name and tap "Add".
4. Done! The session is established.

--- HOW TO SELECT A CONTACT ---

1. Tap the Person icon to open Contacts.
2. Tap on a contact name to select them.
3. The info label at the top will show the selected contact's name.
4. You can now encrypt/decrypt messages with that contact.

--- HOW TO ENCRYPT A MESSAGE ---

1. Select a contact first (Person icon).
2. Type your secret message in the "Type your secret message here" field.
3. Tap the Envelope+Lock icon.
4. The encrypted text is automatically pasted into the active chat.
5. Send it normally through your messenger.

--- HOW TO DECRYPT A MESSAGE ---

1. Copy the encrypted message you received.
2. Tap the Lock icon.
3. The keyboard reads the clipboard, decrypts the message, and saves it to the chat history.
4. Tap the Chat bubble icon to see the decrypted conversation.

--- HOW TO VERIFY A CONTACT ---

1. Open Contacts (Person icon).
2. Tap "Verify" next to the contact's name.
3. A 12-block numeric code will appear.
4. Compare these numbers with your contact's device (in person or via video call).
5. If they match, tap "Verified" to confirm.

--- HOW TO DELETE MESSAGES ---

1. Tap the Chat bubble icon to open message history.
2. Tap "Delete All" (in red) to erase all messages with the selected contact.

--- HOW TO DELETE A CONTACT ---

1. Open Contacts (Person icon).
2. Swipe left on the contact name, or tap "Delete" next to their name.
3. This removes the contact and all associated encryption keys.

--- ENCODING MODES ---

Long-press the Envelope+Lock icon to cycle encoding:
- RAW: Standard encrypted output
- FAIRY: Disguises encrypted text as a fairy tale story
- B64: Base64 encoded output

--- IMPORTANT NOTES ---

- Both users must have SecureChat Keyboard installed.
- The keyboard never connects to the internet.
- All keys are stored in the iOS Keychain (Secure Enclave).
- Keys rotate automatically every 2 days.
- Full Access must be enabled for clipboard access.

v4.0.0
"""

        configBtn(helpBackButton, title: "Back", size: 13, weight: .medium, action: #selector(helpBackTapped))

        let topRow = hStack([helpInfoLabel, helpBackButton], spacing: 8)
        let vStack = UIStackView(arrangedSubviews: [topRow, helpTextView])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        helpContainer.addSubview(vStack)
        pinFill(vStack, in: helpContainer, h: 6, v: 4)
    }

    // ===========================  VIEW 5 - VERIFY  ==========================

    private func buildVerifyView() {
        verifyInfoLabel.font = .systemFont(ofSize: 10, weight: .medium)
        verifyInfoLabel.textColor = .secondaryLabel
        verifyInfoLabel.numberOfLines = 2
        verifyInfoLabel.text = "Compare these numbers with your contact's device"

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 4
        grid.distribution = .fillEqually

        for _ in 0..<3 {
            var rowLabels: [UILabel] = []
            for _ in 0..<4 {
                let lbl = UILabel()
                lbl.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
                lbl.textAlignment = .center
                lbl.text = "00000"
                codeLabels.append(lbl)
                rowLabels.append(lbl)
            }
            let row = UIStackView(arrangedSubviews: rowLabels)
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 8
            grid.addArrangedSubview(row)
        }

        configBtn(verifyBackButton,    title: "Back",   size: 13, weight: .medium,   action: #selector(verifyBackTapped))
        configBtn(verifyConfirmButton, title: "Verify", size: 13, weight: .semibold, action: #selector(verifyConfirmTapped))
        verifyConfirmButton.setTitleColor(.systemGreen, for: .normal)

        let topRow = hStack([verifyInfoLabel, verifyBackButton, verifyConfirmButton], spacing: 6)
        let vStack = UIStackView(arrangedSubviews: [topRow, grid])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        verifyContainer.addSubview(vStack)
        pinFill(vStack, in: verifyContainer, h: 6, v: 4)
    }

    // -----------------------------------------------------------------------
    // MARK: - View switching
    // -----------------------------------------------------------------------

    private func showView(_ mode: ViewMode) {
        currentMode = mode
        let idx = mode.rawValue
        for (i, c) in allContainers.enumerated() { c.isHidden = (i != idx) }
        let needsExpand = (mode != .main)
        delegate?.requestHeightChange(expanded: needsExpand)
        // Deactivate all internal input when switching views
        deactivateAllInput()

        // Accessibility: announce the view change
        let viewNames: [ViewMode: String] = [
            .main: "Main view",
            .addContact: "Add contact",
            .contactList: "Contact list",
            .messages: "Message history",
            .help: "Help",
            .verify: "Verify contact",
        ]
        if let name = viewNames[mode] {
            UIAccessibility.post(notification: .screenChanged, argument: name)
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - Internal Input Routing (receives keys from KeyboardView)
    // -----------------------------------------------------------------------

    /// Whether any internal field is currently active (receiving key presses).
    /// When true, KeyboardViewController should route keys here instead of textDocumentProxy.
    var isInternalInputActive: Bool {
        return inputField.isActive || activeContactField != nil
    }

    /// Tap on the secret message field toggles it.
    @objc private func inputFieldTapped() {
        let wasActive = inputField.isActive
        deactivateContactFields()
        inputField.isActive = !wasActive
    }

    /// Called by KeyboardViewController when a key is pressed and internal input is active.
    func secretInsertText(_ text: String) {
        if inputField.isActive {
            inputField.insertCharacter(text)
        } else if let field = activeContactField {
            switch field {
            case .firstName: firstNameField.insertCharacter(text)
            case .lastName:  lastNameField.insertCharacter(text)
            }
        }
    }

    /// Called by KeyboardViewController when delete is pressed and internal input is active.
    func secretDeleteBackward() {
        if inputField.isActive {
            inputField.deleteLastCharacter()
        } else if let field = activeContactField {
            switch field {
            case .firstName: firstNameField.deleteLastCharacter()
            case .lastName:  lastNameField.deleteLastCharacter()
            }
        }
    }

    /// Deactivate the secret message input field.
    func deactivateSecretInput() {
        inputField.isActive = false
    }

    /// Deactivate ALL internal input fields.
    func deactivateAllInput() {
        inputField.isActive = false
        deactivateContactFields()
    }

    // -----------------------------------------------------------------------
    // MARK: - View 0 Actions (Main) — Android-like flows
    // -----------------------------------------------------------------------

    /// Icon 1 - Chat history
    @objc private func chatTapped() {
        guard let contact = chosenContact else {
            flashInfo("Select a contact first")
            return
        }
        reloadMessages(for: contact)
        showView(.messages)
    }

    /// Paste button: reads clipboard IMMEDIATELY into the FakeTextField.
    /// Use this when apps with Face ID lock (WhatsApp, banking apps) clear the clipboard
    /// upon switching away. Tap Paste right after switching to the keyboard.
    @objc private func pasteTapped() {
        Logger.log("[PASTE] ========== PASTE BUTTON TAPPED ==========")
        let hasStrings = UIPasteboard.general.hasStrings
        Logger.log("[PASTE] hasStrings=\(hasStrings)")

        guard let clipText = UIPasteboard.general.string, !clipText.isEmpty else {
            Logger.log("[PASTE] Clipboard empty or nil")
            if !hasStrings {
                flashInfo("No clipboard access - check Full Access")
            } else {
                flashInfo("Clipboard empty")
            }
            return
        }

        Logger.log("[PASTE] Got \(clipText.count) chars from clipboard")
        inputField.text = clipText
        inputField.isActive = false
        flashInfo("Pasted \(clipText.count) chars - tap Lock to process")
        // Clear clipboard after pasting to internal field
        UIPasteboard.general.string = ""
        Logger.log("[PASTE] ========== PASTE DONE ==========")
    }

    /// Icon 2 - Lock: smart action from clipboard OR from internal field
    /// Priority: 1) clipboard  2) internal input field content
    /// - If has encrypted message from known contact -> decrypt + show in history
    /// - If has invite (PreKeyResponse) -> show add contact
    /// - If both empty -> flash info
    @objc private func lockTapped() {
        deactivateAllInput()
        flashInfo("Reading...")

        // iOS may delay clipboard access (paste permission banner).
        // Small async delay ensures the permission dialog resolves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.processClipboard()
        }
    }

    private func processClipboard() {
        Logger.log("[LOCK] ========== PROCESSING CLIPBOARD ==========")

        // Ensure protocol is initialized before doing anything
        if !SignalProtocolManager.shared.isInitialized {
            Logger.log("[LOCK] Protocol NOT initialized, reloading...")
            SignalProtocolManager.shared.reloadAccount()
        }
        Logger.log("[LOCK] Protocol initialized=\(SignalProtocolManager.shared.isInitialized), account=\(SignalProtocolManager.shared.accountName ?? "nil"), contacts=\(SignalProtocolManager.shared.contacts.count)")

        guard SignalProtocolManager.shared.isInitialized else {
            Logger.log("[LOCK] ERROR: Protocol still not initialized after reload!")
            flashInfo("ERROR: Protocol not initialized - open main app first")
            return
        }

        // Try clipboard first, then fall back to internal input field
        let hasStrings = UIPasteboard.general.hasStrings
        Logger.log("[LOCK] UIPasteboard.general.hasStrings=\(hasStrings)")

        let clipboardText = UIPasteboard.general.string ?? ""
        let internalText = inputField.text
        Logger.log("[LOCK] clipboard length=\(clipboardText.count), internalField length=\(internalText.count)")

        let clipText: String
        if !clipboardText.isEmpty {
            clipText = clipboardText
            Logger.log("[LOCK] Using CLIPBOARD as source")
        } else if !internalText.isEmpty {
            clipText = internalText
            Logger.log("[LOCK] Clipboard empty, using INTERNAL FIELD as source (paste fallback)")
        } else {
            Logger.log("[LOCK] Both clipboard and internal field are empty")
            if !hasStrings {
                flashInfo("No clipboard access - check Full Access")
            } else {
                flashInfo("Empty - copy msg or use Paste button first")
            }
            return
        }
        Logger.log("[LOCK] Raw input length=\(clipText.count) chars")
        Logger.log("[LOCK] Raw input first 300 chars: \(String(clipText.prefix(300)))")

        // Clean the clipboard text: trim whitespace, newlines, and invisible chars
        let cleaned = clipText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")  // non-breaking space
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        Logger.log("[LOCK] Cleaned length=\(cleaned.count) chars")

        // Count invisible characters
        var invisibleCount = 0
        for scalar in cleaned.unicodeScalars {
            if scalar.value == 0x200B || scalar.value == 0x200C || scalar.value == 0x200D
                || scalar.value == 0x2060 || scalar.value == 0xFEFF || scalar.value == 0x061C
                || (scalar.value >= 0x2061 && scalar.value <= 0x2064)
                || (scalar.value >= 0x206A && scalar.value <= 0x206F) {
                invisibleCount += 1
            }
        }
        Logger.log("[LOCK] Invisible unicode chars found: \(invisibleCount)")

        // Try to find JSON within the text (in case there's extra text around it)
        let jsonText = extractJSON(from: cleaned) ?? cleaned
        Logger.log("[LOCK] extractJSON result: \(jsonText == cleaned ? "no JSON found, using cleaned" : "JSON extracted, length=\(jsonText.count)")")

        let envelope: MessageEnvelope
        do {
            envelope = try decodeAuto(jsonText)
            Logger.log("[LOCK] decodeAuto SUCCESS!")
        } catch {
            Logger.error("[LOCK] decodeAuto FAILED: \(error)")
            Logger.error("[LOCK] first 500 chars of input: \(String(jsonText.prefix(500)))")
            flashInfo("Decode failed - not a valid message")
            return
        }

        Logger.log("[LOCK] Envelope decoded: sender=\(envelope.signalProtocolAddressName), devId=\(envelope.deviceId)")
        Logger.log("[LOCK] Envelope: hasPreKeyResponse=\(envelope.preKeyResponse != nil), hasCiphertext=\(envelope.ciphertextMessage != nil), ciphertextType=\(envelope.ciphertextType), ciphertextSize=\(envelope.ciphertextMessage?.count ?? 0)")

        guard let msgType = MessageType.from(envelope) else {
            Logger.error("[LOCK] Unknown message type: preKey=\(envelope.preKeyResponse != nil) cipher=\(envelope.ciphertextMessage != nil)")
            flashInfo("Unknown message format")
            return
        }

        Logger.log("[LOCK] Detected message type: \(msgType)")
        Logger.log("[LOCK] My account: \(SignalProtocolManager.shared.accountName ?? "nil")")

        // Don't decrypt own messages
        let myAccount = SignalProtocolManager.shared.accountName ?? ""
        let senderAccount = envelope.signalProtocolAddressName
        Logger.log("[LOCK] OWN-CHECK: myAccount=\(myAccount), senderAccount=\(senderAccount), match=\(senderAccount == myAccount)")
        if senderAccount == myAccount {
            Logger.log("[LOCK] This is our own message, skipping. myAccount=\(myAccount)")
            flashInfo("Own message (you sent this)")
            UIPasteboard.general.string = ""
            return
        }

        let sender = findContact(for: envelope)
        Logger.log("[LOCK] Known sender contact: \(sender?.displayName ?? "UNKNOWN") (searched for addr=\(envelope.signalProtocolAddressName), devId=\(envelope.deviceId))")
        Logger.log("[LOCK] All known contacts: \(SignalProtocolManager.shared.contacts.map { "\($0.displayName)[\($0.signalProtocolAddressName).\($0.deviceId)]" })")

        switch msgType {
        case .preKeyResponseMessage:
            Logger.log("[LOCK] Case: preKeyResponseMessage (invite)")
            // Invite received -> add contact or update existing session
            if let sender = sender {
                Logger.log("[LOCK] Contact exists, updating session...")
                let ok = SignalProtocolManager.shared.processPreKeyResponse(envelope: envelope, contact: sender)
                Logger.log("[LOCK] Session update result: \(ok)")
                flashInfo(ok ? "Session with \(sender.displayName) updated" : "Session update failed")
            } else {
                Logger.log("[LOCK] New contact, showing add contact form...")
                flashInfo("Invite detected! Enter contact name")
                showAddContact(envelope: envelope)
            }

        case .signalMessage:
            Logger.log("[LOCK] Case: signalMessage (encrypted msg)")
            if let sender = sender {
                Logger.log("[LOCK] Contact found, decrypting...")
                chosenContact = sender
                decryptAndShow(envelope: envelope, sender: sender)
            } else {
                Logger.log("[LOCK] ERROR: Unknown sender for signal message")
                flashInfo("Unknown sender [\(String(envelope.signalProtocolAddressName.prefix(8)))...]")
            }

        case .updatedPreKeyResponseAndSignalMessage:
            Logger.log("[LOCK] Case: updatedPreKeyResponseAndSignalMessage (key rotation + msg)")
            if let sender = sender {
                Logger.log("[LOCK] Contact found, processing prekey update then decrypting...")
                chosenContact = sender
                let ok = SignalProtocolManager.shared.processPreKeyResponse(envelope: envelope, contact: sender)
                Logger.log("[LOCK] PreKey update result: \(ok)")
                decryptAndShow(envelope: envelope, sender: sender)
            } else {
                Logger.log("[LOCK] New contact with msg, showing add contact form...")
                flashInfo("Invite+msg detected! Enter contact name")
                showAddContact(envelope: envelope)
            }
        }

        // Clear both clipboard and internal field after processing
        inputField.text = ""
        UIPasteboard.general.string = ""
        Logger.log("[LOCK] ========== CLIPBOARD PROCESSING DONE ==========")
    }

    /// Try to extract JSON object from text that may have surrounding non-JSON content
    private func extractJSON(from text: String) -> String? {
        // Find the first { and last } to extract the JSON object
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            return nil
        }
        let jsonSubstring = text[firstBrace...lastBrace]
        let json = String(jsonSubstring)
        // Verify it's valid JSON
        guard let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return json
    }

    /// Icon 3 - Envelope+Lock: encrypt typed message
    @objc private func encryptTapped() {
        Logger.log("[ENC_BTN] ========== ENCRYPT BUTTON TAPPED ==========")
        guard let contact = chosenContact else {
            Logger.log("[ENC_BTN] No contact chosen!")
            flashInfo("Select a contact first")
            return
        }
        let text = inputField.text
        guard !text.isEmpty else {
            Logger.log("[ENC_BTN] Empty message!")
            flashInfo("Type a message first")
            return
        }
        Logger.log("[ENC_BTN] Encrypting \"\(text)\" for \(contact.displayName), encoding=\(currentEncodingMode.rawValue)")

        guard let envelope = SignalProtocolManager.shared.encrypt(message: text, for: contact) else {
            Logger.log("[ENC_BTN] ERROR: encrypt() returned nil!")
            flashInfo("Encryption failed")
            return
        }
        Logger.log("[ENC_BTN] Encryption OK. Encoding with \(currentEncodingMode.rawValue)...")

        do {
            let encoded = try currentEncodingMode.encoder.encode(envelope)
            Logger.log("[ENC_BTN] Encoded length=\(encoded.count) chars")
            Logger.log("[ENC_BTN] Encoded first 300: \(String(encoded.prefix(300)))")
            UIPasteboard.general.string = encoded
            delegate?.insertText(encoded)
            inputField.text = ""
            deactivateSecretInput()
            flashInfo("Encrypted & copied")
            Logger.log("[ENC_BTN] ========== ENCRYPT BUTTON DONE ==========")
        } catch {
            Logger.log("[ENC_BTN] ERROR: Encoding failed: \(error)")
            flashInfo("Encoding failed")
        }
    }

    /// Long press on encrypt icon -> toggle encoding mode
    @objc private func encodingLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        if currentEncodingMode == .raw {
            currentEncodingMode = .fairyTale
        } else {
            currentEncodingMode = .raw
        }
        let modeName = currentEncodingMode == .raw ? "RAW" : "FAIRY TALE"
        encodingLabel.text = modeName
        encodingLabel.accessibilityValue = modeName
        flashInfo("Encoding: \(currentEncodingMode == .raw ? "RAW" : "Fairy Tale")")
    }

    /// Icon 4 - Contacts
    @objc private func contactsTapped() {
        reloadContactList()
        showView(.contactList)
    }

    /// Icon 5 - Help
    @objc private func helpTapped() {
        showView(.help)
    }

    // -----------------------------------------------------------------------
    // MARK: - Decrypt logic
    // -----------------------------------------------------------------------

    private func decodeAuto(_ text: String) throws -> MessageEnvelope {
        Logger.log("[DECODE] ========== decodeAuto ==========")
        Logger.log("[DECODE] Input length=\(text.count) chars")

        // 1. Try RAW (JSON) first -- most common for invites
        Logger.log("[DECODE] Trying RAW (JSON)...")
        do {
            let envelope = try RawEncoder().decode(text)
            Logger.log("[DECODE] RAW decode SUCCESS! hasPreKey=\(envelope.preKeyResponse != nil), hasCiphertext=\(envelope.ciphertextMessage != nil)")
            return envelope
        } catch {
            Logger.log("[DECODE] RAW decode failed: \(error)")
        }

        // 2. Try FairyTale (invisible unicode chars)
        let hasInvisible = text.unicodeScalars.contains {
            $0.value == 0x200B || $0.value == 0x200C || $0.value == 0x200D
            || $0.value == 0x2060 || $0.value == 0xFEFF || $0.value == 0x061C
            || ($0.value >= 0x2061 && $0.value <= 0x2064)
            || ($0.value >= 0x206A && $0.value <= 0x206F)
        }
        Logger.log("[DECODE] Has invisible chars: \(hasInvisible)")
        if hasInvisible {
            Logger.log("[DECODE] Trying FairyTale...")
            do {
                let envelope = try FairyTaleEncoder().decode(text)
                Logger.log("[DECODE] FairyTale decode SUCCESS! hasPreKey=\(envelope.preKeyResponse != nil), hasCiphertext=\(envelope.ciphertextMessage != nil)")
                return envelope
            } catch {
                Logger.log("[DECODE] FairyTale decode failed: \(error)")
            }
        }

        // 3. Try Base64
        Logger.log("[DECODE] Trying Base64...")
        do {
            let envelope = try Base64MessageEncoder().decode(text)
            Logger.log("[DECODE] Base64 decode SUCCESS! hasPreKey=\(envelope.preKeyResponse != nil), hasCiphertext=\(envelope.ciphertextMessage != nil)")
            return envelope
        } catch {
            Logger.log("[DECODE] Base64 decode failed: \(error)")
        }

        // None worked -- throw with the raw decoder error for diagnostics
        Logger.log("[DECODE] ALL DECODERS FAILED! Throwing raw decoder error")
        return try RawEncoder().decode(text)
    }

    private func decryptAndShow(envelope: MessageEnvelope, sender: Contact) {
        Logger.log("[DECRYPT_SHOW] Decrypting and showing message from \(sender.displayName)...")
        Logger.log("[DECRYPT_SHOW] sender addr=\(sender.signalProtocolAddressName), devId=\(sender.deviceId)")
        Logger.log("[DECRYPT_SHOW] envelope ciphertextType=\(envelope.ciphertextType), ciphertextSize=\(envelope.ciphertextMessage?.count ?? 0)")
        do {
            let msg = try SignalProtocolManager.shared.decrypt(envelope: envelope, from: sender)
            Logger.log("[DECRYPT_SHOW] SUCCESS! Decrypted: \"\(msg)\"")
            updateInfoForChosenContact()
            flashInfo("Decrypted from \(sender.displayName)")
            // Auto-open chat to see the message
            reloadMessages(for: sender)
            showView(.messages)
        } catch {
            Logger.error("[DECRYPT_SHOW] FAILED: \(error)")
            let errMsg = "\(error)"
            if errMsg.contains("session") || errMsg.contains("Session") {
                flashInfo("Decrypt error: no session. Both reset & re-invite")
            } else if errMsg.contains("PreKey") || errMsg.contains("prekey") {
                flashInfo("Decrypt error: bad prekey. Both reset & re-invite")
            } else if errMsg.contains("identity") || errMsg.contains("Identity") {
                flashInfo("Decrypt error: identity mismatch. Both reset")
            } else {
                flashInfo("Decrypt failed: \(String(errMsg.prefix(40)))")
            }
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - View 1 Actions (Add Contact)
    // -----------------------------------------------------------------------

    private func showAddContact(envelope: MessageEnvelope) {
        pendingEnvelope = envelope
        firstNameField.text = ""
        lastNameField.text = ""
        addContactInfoLabel.text = "New contact detected — enter a name"
        showView(.addContact)
    }

    @objc private func addContactConfirmTapped() {
        Logger.log("[ADD_CONTACT] ========== ADD CONTACT CONFIRM ==========")
        deactivateContactFields()
        let firstName = firstNameField.text.trimmingCharacters(in: .whitespaces)
        guard !firstName.isEmpty else {
            Logger.log("[ADD_CONTACT] ERROR: First name is empty!")
            addContactInfoLabel.text = "First name is required"
            return
        }
        let lastName = lastNameField.text.trimmingCharacters(in: .whitespaces)
        Logger.log("[ADD_CONTACT] name=\"\(firstName) \(lastName)\"")

        guard let envelope = pendingEnvelope else {
            Logger.log("[ADD_CONTACT] ERROR: No pending envelope!")
            showView(.main)
            return
        }
        Logger.log("[ADD_CONTACT] pendingEnvelope: sender=\(envelope.signalProtocolAddressName), devId=\(envelope.deviceId), hasPreKey=\(envelope.preKeyResponse != nil), hasCiphertext=\(envelope.ciphertextMessage != nil)")

        do {
            let contact = try SignalProtocolManager.shared.addContact(
                firstName: firstName, lastName: lastName,
                addressName: envelope.signalProtocolAddressName, deviceId: envelope.deviceId)
            Logger.log("[ADD_CONTACT] Contact added: \(contact.displayName) addr=\(contact.signalProtocolAddressName) devId=\(contact.deviceId)")

            if envelope.preKeyResponse != nil {
                Logger.log("[ADD_CONTACT] Processing preKeyResponse from invite...")
                let ok = SignalProtocolManager.shared.processPreKeyResponse(envelope: envelope, contact: contact)
                Logger.log("[ADD_CONTACT] processPreKeyResponse result: \(ok)")
                if ok { flashInfo("Session with \(contact.displayName) created") }
                else { flashInfo("Session creation FAILED") }
            }

            chosenContact = contact
            updateInfoForChosenContact()

            if envelope.ciphertextMessage != nil {
                Logger.log("[ADD_CONTACT] Envelope also has ciphertext, decrypting...")
                decryptAndShow(envelope: envelope, sender: contact)
            }
        } catch {
            Logger.log("[ADD_CONTACT] ERROR: \(error)")
            addContactInfoLabel.text = "Error: \(error.localizedDescription)"
            return
        }

        pendingEnvelope = nil
        Logger.log("[ADD_CONTACT] ========== ADD CONTACT DONE ==========")
        if currentMode == .addContact { showView(.main) }
    }

    @objc private func addContactCancelTapped() {
        pendingEnvelope = nil
        showView(.main)
    }

    // -----------------------------------------------------------------------
    // MARK: - View 2 Actions (Contact List)
    // -----------------------------------------------------------------------

    private func reloadContactList() {
        contactListData = SignalProtocolManager.shared.contacts
        contactTableView.reloadData()
    }

    @objc private func contactListBackTapped() { showView(.main) }

    @objc private func contactListInviteTapped() {
        sendInvite()
        showView(.main)
    }

    private func selectContact(_ contact: Contact) {
        chosenContact = contact
        updateInfoForChosenContact()
        showView(.main)
    }

    private func removeContact(_ contact: Contact) {
        SignalProtocolManager.shared.removeContact(contact)
        if chosenContact == contact {
            chosenContact = nil
            infoLabel.text = "No contact chosen"
        }
        reloadContactList()
    }

    private func verifyContact(_ contact: Contact) {
        chosenContact = contact
        loadFingerprint(for: contact)
        showView(.verify)
    }

    private func sendInvite() {
        Logger.log("[SEND_INVITE] ========== SENDING INVITE ==========")
        Logger.log("[SEND_INVITE] encoding=\(currentEncodingMode.rawValue)")
        guard let envelope = SignalProtocolManager.shared.createPreKeyResponseEnvelope() else {
            Logger.log("[SEND_INVITE] ERROR: createPreKeyResponseEnvelope returned nil!")
            flashInfo("Could not create invite")
            return
        }
        Logger.log("[SEND_INVITE] Envelope created: sender=\(envelope.signalProtocolAddressName), devId=\(envelope.deviceId)")
        do {
            let encoded = try currentEncodingMode.encoder.encode(envelope)
            Logger.log("[SEND_INVITE] Encoded invite length=\(encoded.count) chars")
            Logger.log("[SEND_INVITE] First 300 chars: \(String(encoded.prefix(300)))")
            UIPasteboard.general.string = encoded
            delegate?.insertText(encoded)
            flashInfo("Invite copied & sent")
            Logger.log("[SEND_INVITE] ========== INVITE SENT OK ==========")
        } catch {
            Logger.log("[SEND_INVITE] ERROR: Encoding failed: \(error)")
            flashInfo("Invite failed")
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - View 3 Actions (Messages)
    // -----------------------------------------------------------------------

    private func reloadMessages(for contact: Contact) {
        messagesData = SignalProtocolManager.shared.getMessages(for: contact)
        messagesInfoLabel.text = "Chat: \(contact.displayName)"
        messagesTableView.reloadData()
        if !messagesData.isEmpty {
            let last = IndexPath(row: messagesData.count - 1, section: 0)
            messagesTableView.scrollToRow(at: last, at: .bottom, animated: false)
        }
    }

    @objc private func messagesBackTapped() { showView(.main) }

    @objc private func messagesDeleteTapped() {
        guard let contact = chosenContact else { return }
        SignalProtocolManager.shared.deleteMessages(for: contact)
        reloadMessages(for: contact)
        flashInfo("History deleted")
    }

    // -----------------------------------------------------------------------
    // MARK: - View 4 (Help) & View 5 (Verify) Actions
    // -----------------------------------------------------------------------

    @objc private func helpBackTapped() { showView(.main) }

    private func loadFingerprint(for contact: Contact) {
        verifyInfoLabel.text = "Compare with \(contact.displayName)'s device"
        guard let groups = SignalProtocolManager.shared.generateFingerprint(for: contact) else {
            for lbl in codeLabels { lbl.text = "-----" }
            return
        }
        for (i, lbl) in codeLabels.enumerated() {
            lbl.text = i < groups.count ? groups[i] : "-----"
        }
    }

    @objc private func verifyBackTapped() { showView(.contactList) }

    @objc private func verifyConfirmTapped() {
        guard let contact = chosenContact else { return }
        SignalProtocolManager.shared.verifyContact(contact)
        reloadContactList()
        showView(.contactList)
    }

    // -----------------------------------------------------------------------
    // MARK: - Helpers
    // -----------------------------------------------------------------------

    private func findContact(for envelope: MessageEnvelope) -> Contact? {
        SignalProtocolManager.shared.contacts.first {
            $0.signalProtocolAddressName == envelope.signalProtocolAddressName
                && $0.deviceId == envelope.deviceId
        }
    }

    private func updateInfoForChosenContact() {
        if let c = chosenContact {
            let text = "Contact: \(c.displayName)" + (c.verified ? " [verified]" : "")
            infoLabel.text = text
            infoLabel.accessibilityValue = text
        } else {
            infoLabel.text = "No contact chosen"
            infoLabel.accessibilityValue = "No contact chosen"
        }
    }

    private func flashInfo(_ msg: String) {
        infoLabel.text = msg
        infoLabel.accessibilityValue = msg
        // Announce status changes to VoiceOver
        UIAccessibility.post(notification: .announcement, argument: msg)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            if self.infoLabel.text == msg { self.updateInfoForChosenContact() }
        }
    }

    // -----------------------------------------------------------------------
    // MARK: - Layout helpers
    // -----------------------------------------------------------------------

    private func configBtn(_ btn: UIButton, title: String, size: CGFloat, weight: UIFont.Weight, action: Selector) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func hStack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = spacing
        s.alignment = .center
        return s
    }

    private func pinFill(_ child: UIView, in parent: UIView, h: CGFloat, v: CGFloat) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: v),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: h),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -h),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -v),
        ])
    }

    // -----------------------------------------------------------------------
    // MARK: - Public
    // -----------------------------------------------------------------------

    func setExpanded(_ expanded: Bool) {
        // Input field always visible in main view now (like Android)
    }
}

// ===========================================================================
// MARK: - UITableViewDataSource & Delegate
// ===========================================================================

extension E2EEStripView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === contactTableView { return contactListData.count }
        if tableView === messagesTableView { return messagesData.count }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === contactTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: ContactCell.reuseId, for: indexPath) as! ContactCell
            let contact = contactListData[indexPath.row]
            cell.configure(contact: contact,
                           onDelete: { [weak self] in self?.removeContact(contact) },
                           onVerify: { [weak self] in self?.verifyContact(contact) })
            return cell
        }
        if tableView === messagesTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
            let msg = messagesData[indexPath.row]
            let isOwn = (msg.senderUUID == SignalProtocolManager.shared.accountName)
            cell.configure(message: msg, isOwn: isOwn)
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if tableView === contactTableView {
            selectContact(contactListData[indexPath.row])
        }
    }
}

// ===========================================================================
// MARK: - ContactCell
// ===========================================================================

private class ContactCell: UITableViewCell {
    static let reuseId = "ContactCell"
    private let nameLabel = UILabel()
    private let verifiedLabel = UILabel()
    private let deleteBtn = UIButton(type: .system)
    private let verifyBtn = UIButton(type: .system)
    private var onDelete: (() -> Void)?
    private var onVerify: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        verifiedLabel.font = .systemFont(ofSize: 11)
        deleteBtn.setTitle("X", for: .normal)
        deleteBtn.setTitleColor(.systemRed, for: .normal)
        deleteBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        deleteBtn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        verifyBtn.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        verifyBtn.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [nameLabel, verifiedLabel, verifyBtn, deleteBtn])
        stack.axis = .horizontal; stack.spacing = 8; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(contact: Contact, onDelete: @escaping () -> Void, onVerify: @escaping () -> Void) {
        self.onDelete = onDelete; self.onVerify = onVerify
        nameLabel.text = contact.displayName
        if contact.verified {
            verifiedLabel.text = "Verified"; verifiedLabel.textColor = .systemGreen
            verifyBtn.setTitle("View", for: .normal)
        } else {
            verifiedLabel.text = "Unverified"; verifiedLabel.textColor = .systemRed
            verifyBtn.setTitle("Verify", for: .normal)
        }

        // Accessibility
        let status = contact.verified ? "verified" : "unverified"
        accessibilityLabel = "\(contact.displayName), \(status)"
        accessibilityHint = "Tap to select this contact"
        deleteBtn.accessibilityLabel = "Delete \(contact.displayName)"
        verifyBtn.accessibilityLabel = contact.verified ? "View verification for \(contact.displayName)" : "Verify \(contact.displayName)"
    }
    @objc private func deleteTapped()  { onDelete?() }
    @objc private func verifyTapped()  { onVerify?() }
}

// ===========================================================================
// MARK: - MessageCell
// ===========================================================================

private class MessageCell: UITableViewCell {
    static let reuseId = "MessageCell"
    private let bubble = UILabel()
    private let timeLabel = UILabel()
    private var leadingC: NSLayoutConstraint!
    private var trailingC: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear; selectionStyle = .none
        bubble.font = .systemFont(ofSize: 12)
        bubble.numberOfLines = 0
        bubble.layer.cornerRadius = 8
        bubble.layer.masksToBounds = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 9)
        timeLabel.textColor = .tertiaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)
        contentView.addSubview(timeLabel)

        leadingC  = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        trailingC = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
            timeLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 1),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(message: StorageMessage, isOwn: Bool) {
        bubble.text = "  \(message.unencryptedMessage)  "
        let fmt = DateFormatter(); fmt.dateFormat = "dd.MM.yyyy HH:mm"
        let timeStr = fmt.string(from: message.timestamp)
        timeLabel.text = timeStr
        leadingC.isActive = false; trailingC.isActive = false
        if isOwn {
            trailingC.isActive = true
            bubble.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
            bubble.textColor = .label
            timeLabel.textAlignment = .right
        } else {
            leadingC.isActive = true
            bubble.backgroundColor = UIColor.systemGray5
            bubble.textColor = .label
            timeLabel.textAlignment = .left
        }

        // Accessibility
        let sender = isOwn ? "You" : "Contact"
        isAccessibilityElement = true
        accessibilityLabel = "\(sender): \(message.unencryptedMessage), \(timeStr)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leadingC.isActive = false; trailingC.isActive = false
    }
}
