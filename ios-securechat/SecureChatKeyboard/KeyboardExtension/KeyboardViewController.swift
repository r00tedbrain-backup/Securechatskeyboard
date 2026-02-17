import UIKit

/// Main keyboard view controller -- the entry point for the Custom Keyboard Extension.
/// Equivalent to Android's LatinIME InputMethodService.
///
/// Layout structure:
///   - Top: E2EEStripView (encrypt/decrypt controls, contacts, messages)
///   - Bottom: KeyboardView (QWERTY Spanish layout with native-like appearance)
class KeyboardViewController: UIInputViewController {

    // MARK: - UI Components

    private var e2eeStrip: E2EEStripView!
    private var keyboardView: KeyboardView!

    // MARK: - Layout

    /// Height of the strip in collapsed (main buttons only) mode.
    /// Must fit: infoLabel(14) + inputField(30) + iconStack(40) + encodingLabel(10) + spacing(4*3) + padding(6)
    private let stripCollapsedHeight: CGFloat = 116
    /// Height of the strip in expanded mode (contact list, messages, etc.).
    private let stripExpandedHeight: CGFloat = 220
    /// Height of the keyboard area.
    private let keyboardHeight: CGFloat = 220

    private var stripHeightConstraint: NSLayoutConstraint!
    private var totalHeightConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize the Signal Protocol on first load
        SignalProtocolManager.shared.reloadAccount()

        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateKeyAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateKeyAppearance()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Called when the text is about to change
    }

    override func textDidChange(_ textInput: UITextInput?) {
        updateKeyAppearance()
        updateShiftState()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let inputView = self.inputView else { return }

        // Let the system manage inputView width. Only set height via constraints.
        inputView.allowsSelfSizing = true

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

        // Accessibility: define the navigation order (strip first, then keyboard)
        inputView.accessibilityElements = [e2eeStrip!, keyboardView!]

        // Constraints
        let totalH = stripCollapsedHeight + keyboardHeight
        totalHeightConstraint = inputView.heightAnchor.constraint(equalToConstant: totalH)
        stripHeightConstraint = e2eeStrip.heightAnchor.constraint(equalToConstant: stripCollapsedHeight)

        NSLayoutConstraint.activate([
            totalHeightConstraint,

            // E2EE Strip at top
            e2eeStrip.topAnchor.constraint(equalTo: inputView.topAnchor),
            e2eeStrip.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            e2eeStrip.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            stripHeightConstraint,

            // Keyboard below the strip, filling remaining space
            keyboardView.topAnchor.constraint(equalTo: e2eeStrip.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])
    }

    private func updateKeyAppearance() {
        let proxy = textDocumentProxy
        let isDark = (traitCollection.userInterfaceStyle == .dark)
        keyboardView?.updateAppearance(isDark: isDark, returnKeyType: proxy.returnKeyType ?? .default)
    }

    /// Determine if shift should be active based on text context.
    private func updateShiftState() {
        let proxy = textDocumentProxy

        // Auto-capitalize at start of document or after sentence-ending punctuation
        let shouldCapitalize: Bool
        if let before = proxy.documentContextBeforeInput {
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                shouldCapitalize = true
            } else if let lastChar = trimmed.last {
                shouldCapitalize = (lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == "\n")
            } else {
                shouldCapitalize = true
            }
        } else {
            shouldCapitalize = true
        }

        if let autocap = proxy.autocapitalizationType {
            switch autocap {
            case .allCharacters:
                keyboardView?.setShiftState(uppercase: true)
                return
            case .none:
                keyboardView?.setShiftState(uppercase: false)
                return
            case .words:
                if let before = proxy.documentContextBeforeInput, before.last == " " {
                    keyboardView?.setShiftState(uppercase: true)
                    return
                }
            case .sentences:
                keyboardView?.setShiftState(uppercase: shouldCapitalize)
                return
            @unknown default: break
            }
        }

        keyboardView?.setShiftState(uppercase: shouldCapitalize)
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

extension KeyboardViewController: KeyboardViewDelegate {
    func insertText(_ text: String) {
        if e2eeStrip.isInternalInputActive {
            e2eeStrip.secretInsertText(text)
        } else {
            textDocumentProxy.insertText(text)
        }
    }

    func deleteBackward() {
        if e2eeStrip.isInternalInputActive {
            e2eeStrip.secretDeleteBackward()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    func insertNewline() {
        if e2eeStrip.isInternalInputActive {
            // Newline deactivates all internal fields (like "done")
            e2eeStrip.deactivateAllInput()
        } else {
            textDocumentProxy.insertText("\n")
        }
    }
}

// MARK: - E2EEStripDelegate

extension KeyboardViewController: E2EEStripDelegate {
    func requestHeightChange(expanded: Bool) {
        let stripH = expanded ? stripExpandedHeight : stripCollapsedHeight
        let totalH = stripH + keyboardHeight

        stripHeightConstraint.constant = stripH
        totalHeightConstraint.constant = totalH
        e2eeStrip.setExpanded(expanded)

        UIView.animate(withDuration: 0.2) {
            self.inputView?.layoutIfNeeded()
        }
    }
}
