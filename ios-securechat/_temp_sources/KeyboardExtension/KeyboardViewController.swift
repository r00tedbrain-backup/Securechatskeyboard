import UIKit

/// Main keyboard view controller — the entry point for the Custom Keyboard Extension.
/// Equivalent to Android's LatinIME InputMethodService.
///
/// Layout structure:
///   - Top: E2EEStripView (encrypt/decrypt controls, contacts, messages)
///   - Middle: Key rows (QWERTY or other layouts)
///   - Bottom: Space bar row with globe key
class KeyboardViewController: UIInputViewController {

    // MARK: - UI Components

    private var e2eeStrip: E2EEStripView!
    private var keyboardView: KeyboardView!

    // MARK: - State

    private var isUppercase = false
    private var isShowingNumbers = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize the Signal Protocol on first load
        SignalProtocolManager.shared.reloadAccount()

        setupUI()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Called when the text is about to change
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Update key appearance based on context (e.g., shift state)
        updateKeyAppearance()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let inputView = self.inputView else { return }
        inputView.translatesAutoresizingMaskIntoConstraints = false

        // E2EE Strip (top section)
        e2eeStrip = E2EEStripView(frame: .zero)
        e2eeStrip.translatesAutoresizingMaskIntoConstraints = false
        e2eeStrip.delegate = self
        inputView.addSubview(e2eeStrip)

        // Keyboard Keys (main section)
        keyboardView = KeyboardView(frame: .zero)
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.delegate = self
        inputView.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            // E2EE Strip at top
            e2eeStrip.topAnchor.constraint(equalTo: inputView.topAnchor),
            e2eeStrip.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            e2eeStrip.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            e2eeStrip.heightAnchor.constraint(equalToConstant: 44),

            // Keyboard below the strip
            keyboardView.topAnchor.constraint(equalTo: e2eeStrip.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
        ])
    }

    private func updateKeyAppearance() {
        let proxy = textDocumentProxy
        let isDark = (traitCollection.userInterfaceStyle == .dark)
        keyboardView?.updateAppearance(isDark: isDark, returnKeyType: proxy.returnKeyType ?? .default)
    }

    // MARK: - Text Input

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func insertNewline() {
        textDocumentProxy.insertText("\n")
    }
}

// MARK: - KeyboardViewDelegate

protocol KeyboardViewDelegate: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func insertNewline()
    var needsInputModeSwitchKey: Bool { get }
    func advanceToNextInputMode()
}

extension KeyboardViewController: KeyboardViewDelegate {}

// MARK: - E2EEStripDelegate

protocol E2EEStripDelegate: AnyObject {
    func insertText(_ text: String)
}

extension KeyboardViewController: E2EEStripDelegate {}
