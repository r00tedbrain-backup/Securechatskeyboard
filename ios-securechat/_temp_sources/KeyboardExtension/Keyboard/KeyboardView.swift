import UIKit

/// The main keyboard view containing all key rows.
/// Supports QWERTY layout with shift, numbers, and special characters.
class KeyboardView: UIView {

    weak var delegate: KeyboardViewDelegate?

    // MARK: - Layout Definitions

    private let letterRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    private let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    // MARK: - State

    private var isUppercase = true
    private var isShowingNumbers = false

    // MARK: - UI Elements

    private let rowsStack = UIStackView()
    private var keyButtons: [[UIButton]] = []
    private let shiftButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let numberToggleButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    // MARK: - Appearance

    private var keyBackgroundColor: UIColor = .white
    private var keyTextColor: UIColor = .black
    private var specialKeyColor: UIColor = UIColor.systemGray3

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboard()
    }

    // MARK: - Setup

    private func setupKeyboard() {
        backgroundColor = UIColor.systemGray5

        rowsStack.axis = .vertical
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 6
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        buildKeyRows()
    }

    private func buildKeyRows() {
        // Clear existing rows
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        keyButtons = []

        let rows = isShowingNumbers ? numberRows : letterRows

        for (rowIndex, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 4

            // Add shift button on the left of row 2 (letter mode only)
            if rowIndex == 2 && !isShowingNumbers {
                let shift = createSpecialKey(title: isUppercase ? "shift.fill" : "shift",
                                             systemImage: true)
                shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
                rowStack.addArrangedSubview(shift)
            }

            var rowButtons: [UIButton] = []
            for key in row {
                let displayKey = isUppercase ? key : key.lowercased()
                let button = createKeyButton(title: displayKey)
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(button)
                rowButtons.append(button)
            }
            keyButtons.append(rowButtons)

            // Add delete button on the right of row 2
            if rowIndex == 2 {
                let del = createSpecialKey(title: "delete.left", systemImage: true)
                del.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
                del.addGestureRecognizer(longPress)
                rowStack.addArrangedSubview(del)
            }

            rowsStack.addArrangedSubview(rowStack)
        }

        // Bottom row: 123/ABC, Globe, Space, Return
        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 4

        let numToggle = createSpecialKey(title: isShowingNumbers ? "ABC" : "123", systemImage: false)
        numToggle.addTarget(self, action: #selector(numberToggleTapped), for: .touchUpInside)
        numToggle.widthAnchor.constraint(equalToConstant: 50).isActive = true
        bottomRow.addArrangedSubview(numToggle)

        // Globe key (switch keyboard)
        let globe = createSpecialKey(title: "globe", systemImage: true)
        globe.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        bottomRow.addArrangedSubview(globe)

        // Space bar
        let space = createKeyButton(title: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        bottomRow.addArrangedSubview(space)

        // Return key
        let ret = createSpecialKey(title: "return", systemImage: false)
        ret.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        ret.widthAnchor.constraint(equalToConstant: 88).isActive = true
        bottomRow.addArrangedSubview(ret)

        rowsStack.addArrangedSubview(bottomRow)
    }

    // MARK: - Key Factory

    private func createKeyButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .regular)
        button.setTitleColor(keyTextColor, for: .normal)
        button.backgroundColor = keyBackgroundColor
        button.layer.cornerRadius = 5
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 0.5
        return button
    }

    private func createSpecialKey(title: String, systemImage: Bool) -> UIButton {
        let button = UIButton(type: .system)
        if systemImage {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: title, withConfiguration: config), for: .normal)
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        }
        button.tintColor = keyTextColor
        button.backgroundColor = specialKeyColor
        button.layer.cornerRadius = 5
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 0.5
        return button
    }

    // MARK: - Actions

    @objc private func keyTapped(_ sender: UIButton) {
        guard let text = sender.title(for: .normal) else { return }
        delegate?.insertText(text)

        // Auto-lowercase after first character
        if isUppercase && !isShowingNumbers {
            isUppercase = false
            buildKeyRows()
        }
    }

    @objc private func shiftTapped() {
        isUppercase.toggle()
        buildKeyRows()
    }

    @objc private func deleteTapped() {
        delegate?.deleteBackward()
    }

    @objc private func deleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Continuous delete while holding
        if gesture.state == .began || gesture.state == .changed {
            delegate?.deleteBackward()
        }
    }

    @objc private func spaceTapped() {
        delegate?.insertText(" ")
    }

    @objc private func returnTapped() {
        delegate?.insertNewline()
    }

    @objc private func numberToggleTapped() {
        isShowingNumbers.toggle()
        buildKeyRows()
    }

    @objc private func globeTapped() {
        if delegate?.needsInputModeSwitchKey == true {
            delegate?.advanceToNextInputMode()
        }
    }

    // MARK: - Appearance Update

    func updateAppearance(isDark: Bool, returnKeyType: UIReturnKeyType) {
        if isDark {
            keyBackgroundColor = UIColor(white: 0.35, alpha: 1)
            keyTextColor = .white
            specialKeyColor = UIColor(white: 0.25, alpha: 1)
            backgroundColor = UIColor(white: 0.12, alpha: 1)
        } else {
            keyBackgroundColor = .white
            keyTextColor = .black
            specialKeyColor = UIColor.systemGray3
            backgroundColor = UIColor.systemGray5
        }
        buildKeyRows()
    }
}
