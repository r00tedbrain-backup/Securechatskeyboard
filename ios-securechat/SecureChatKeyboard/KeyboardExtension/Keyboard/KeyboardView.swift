import UIKit

// =============================================================================
// MARK: - KeyView (custom UIControl — replaces UIButton for instant response)
// =============================================================================

/// Lightweight key control that fires on touch-down for instant character input.
/// No system button animation delays. Minimal overhead.
private class KeyView: UIControl {

    let label = UILabel()
    var keyValue: String = ""
    var isSpecial: Bool = false

    /// Extra hit-area expansion beyond the default 2pt (used for space bar)
    var hitExpandX: CGFloat = 2
    var hitExpandY: CGFloat = 2

    /// Visual feedback colors (set externally before display)
    var normalBg: UIColor = .white { didSet { backgroundColor = normalBg } }
    var pressedBg: UIColor = UIColor.systemGray3

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        layer.cornerRadius = 5.5   // Native iOS key corner radius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0.5
        isExclusiveTouch = false          // allow multi-finger rapid typing
        isMultipleTouchEnabled = false

        // Accessibility
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError() }

    // Expand hit area so adjacent keys share boundaries (variable per key)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -hitExpandX, dy: -hitExpandY).contains(point)
    }

    // Instant visual feedback — no animation, just color swap
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? pressedBg : normalBg
        }
    }

    func configure(text: String, value: String, font: UIFont, textColor: UIColor,
                   bg: UIColor, pressed: UIColor, shadow: Float, isDark: Bool) {
        label.text = text
        label.font = font
        label.textColor = textColor
        keyValue = value
        normalBg = bg
        pressedBg = pressed
        backgroundColor = bg
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = shadow

        // Update accessibility label
        accessibilityLabel = text.isEmpty ? value : text
    }

    func setImage(_ systemName: String, pointSize: CGFloat, tint: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: systemName, withConfiguration: config))
        iv.tintColor = tint
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = false
        iv.isAccessibilityElement = false
        addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.isHidden = true

        // Map SF Symbol names to human-readable accessibility labels
        let a11yMap: [String: String] = [
            "shift": "Shift",
            "shift.fill": "Shift",
            "capslock.fill": "Caps Lock",
            "delete.left": "Delete",
            "globe": "Next Keyboard",
            "face.smiling": "Emoji",
        ]
        if let mapped = a11yMap[systemName] {
            accessibilityLabel = mapped
        }
    }
}

// =============================================================================
// MARK: - KeyboardView
// =============================================================================

/// Native-feeling iOS keyboard with Spanish (ES) layout.
/// Uses custom UIControl subclass (KeyView) for instant touch response,
/// updates labels in-place instead of rebuilding, and eliminates dead zones.
class KeyboardView: UIView {

    weak var delegate: KeyboardViewDelegate?

    // -------------------------------------------------------------------------
    // MARK: - Keyboard Mode
    // -------------------------------------------------------------------------

    private enum KeyboardMode { case letters, numbers, symbols }

    private var mode: KeyboardMode = .letters
    private var isUppercase = true
    private var isCapsLock = false

    // -------------------------------------------------------------------------
    // MARK: - Layout Data (Spanish)
    // -------------------------------------------------------------------------

    private let letterRows: [[String]] = [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l","\u{00F1}"],
        ["z","x","c","v","b","n","m"],
    ]
    private let numberRows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","$","&","@","\""],
        [".",",","?","!","'"],
    ]
    private let symbolRows: [[String]] = [
        ["[","]","{","}","#","%","^","*","+","="],
        ["_","\\","|","~","<",">","\u{20AC}","\u{00A3}","\u{00A5}","\u{2022}"],
        [".",",","?","!","'"],
    ]

    private let accentMap: [String: [String]] = [
        "a": ["a","\u{00E1}","\u{00E0}","\u{00E4}","\u{00E2}","\u{00E3}","\u{00E5}","\u{00E6}"],
        "e": ["e","\u{00E9}","\u{00E8}","\u{00EB}","\u{00EA}"],
        "i": ["i","\u{00ED}","\u{00EC}","\u{00EF}","\u{00EE}"],
        "o": ["o","\u{00F3}","\u{00F2}","\u{00F6}","\u{00F4}","\u{00F5}","\u{00F8}"],
        "u": ["u","\u{00FA}","\u{00F9}","\u{00FC}","\u{00FB}"],
        "n": ["n","\u{00F1}"],
        "c": ["c","\u{00E7}"],
        "s": ["s","\u{00DF}"],
    ]

    // -------------------------------------------------------------------------
    // MARK: - Appearance
    // -------------------------------------------------------------------------

    private var isDarkMode = false
    private var currentReturnKeyType: UIReturnKeyType = .default

    private var keyBg: UIColor      { isDarkMode ? UIColor(white: 0.42, alpha: 1) : .white }
    private var keyPressed: UIColor  { isDarkMode ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.82, alpha: 1) }
    private var keyText: UIColor     { isDarkMode ? .white : .black }
    private var specialBg: UIColor   { isDarkMode ? UIColor(white: 0.30, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: 1) }
    private var specialPressed: UIColor { isDarkMode ? UIColor(white: 0.42, alpha: 1) : UIColor(white: 0.58, alpha: 1) }
    private var boardBg: UIColor     { isDarkMode ? UIColor(white: 0.12, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1) }
    private var shadowAlpha: Float   { isDarkMode ? 0.35 : 0.25 }

    private var returnBg: UIColor {
        switch currentReturnKeyType {
        case .go, .search, .send: return .systemBlue
        default: return specialBg
        }
    }
    private var returnText: UIColor {
        switch currentReturnKeyType {
        case .go, .search, .send: return .white
        default: return keyText
        }
    }
    private var returnTitle: String {
        switch currentReturnKeyType {
        case .go: return "ir"
        case .search: return "buscar"
        case .send: return "enviar"
        case .next: return "sig."
        case .done: return "OK"
        case .join: return "unirse"
        case .route: return "ruta"
        case .emergencyCall: return "SOS"
        default: return "intro"
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Key storage (for in-place label updates — avoids full rebuild)
    // -------------------------------------------------------------------------

    private var charKeysByRow: [[KeyView]] = [[], [], []]
    private var shiftKey: KeyView?
    private var deleteKey: KeyView?
    private var modeToggleKey: KeyView?
    private var symbolToggleKey: KeyView?
    private var spaceKey: KeyView?
    private var periodKey: KeyView?
    private var returnKey: KeyView?
    private var globeKey: KeyView?

    private let containerStack = UIStackView()
    private var deleteTimer: Timer?
    private var accentOverlay: AccentPopupView?
    private var isBuilt = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = true

        // Accessibility: this view is a container, not a single element
        isAccessibilityElement = false
        shouldGroupAccessibilityChildren = true
        accessibilityLabel = "SecureChat Keyboard"

        containerStack.axis = .vertical
        containerStack.spacing = 11   // Native iOS uses ~11pt row spacing
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerStack)
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    // -------------------------------------------------------------------------
    // MARK: - Full rebuild (ONLY on mode change: letters/numbers/symbols)
    // -------------------------------------------------------------------------

    private func buildKeyboard() {
        containerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        charKeysByRow = [[], [], []]
        shiftKey = nil; deleteKey = nil; symbolToggleKey = nil
        backgroundColor = boardBg

        let rows: [[String]]
        switch mode {
        case .letters:  rows = letterRows
        case .numbers:  rows = numberRows
        case .symbols:  rows = symbolRows
        }

        for (ri, row) in rows.enumerated() {
            let rv = UIView()
            rv.translatesAutoresizingMaskIntoConstraints = false
            rv.heightAnchor.constraint(equalToConstant: 42).isActive = true  // Native iOS key height
            containerStack.addArrangedSubview(rv)
            buildRow(row, rowIndex: ri, in: rv)
        }

        let bv = UIView()
        bv.translatesAutoresizingMaskIntoConstraints = false
        bv.heightAnchor.constraint(equalToConstant: 42).isActive = true  // Native iOS key height
        containerStack.addArrangedSubview(bv)
        buildBottomRow(in: bv)

        isBuilt = true
        applyAppearance()
    }

    // -------------------------------------------------------------------------
    // MARK: - In-place label update (shift/case — instant, NO rebuild)
    // -------------------------------------------------------------------------

    private func updateLabelsForCase() {
        guard mode == .letters else { return }
        for (ri, row) in letterRows.enumerated() {
            for (ci, key) in row.enumerated() {
                guard ci < charKeysByRow[ri].count else { continue }
                let display = isUppercase ? key.uppercased() : key
                charKeysByRow[ri][ci].label.text = display
                charKeysByRow[ri][ci].keyValue = display
                charKeysByRow[ri][ci].accessibilityLabel = display
            }
        }
        // Update shift icon
        if let sk = shiftKey {
            sk.subviews.compactMap { $0 as? UIImageView }.forEach { $0.removeFromSuperview() }
            sk.label.isHidden = true
            let name = isCapsLock ? "capslock.fill" : (isUppercase ? "shift.fill" : "shift")
            sk.setImage(name, pointSize: 18, tint: keyText)
            sk.normalBg = isCapsLock ? keyBg : specialBg
            sk.backgroundColor = sk.normalBg
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Row builders
    // -------------------------------------------------------------------------

    private func buildRow(_ keys: [String], rowIndex: Int, in container: UIView) {
        var views: [UIView] = []
        let spacing: CGFloat = 6   // Native iOS inter-key spacing

        // Left special key on row 2
        if rowIndex == 2 {
            if mode == .letters {
                let sk = makeSpecialKey()
                sk.setImage(isUppercase ? "shift.fill" : "shift", pointSize: 18, tint: keyText)
                sk.addTarget(self, action: #selector(shiftTapped), for: .touchDown)
                let dblTap = UITapGestureRecognizer(target: self, action: #selector(capsLockTapped))
                dblTap.numberOfTapsRequired = 2
                sk.addGestureRecognizer(dblTap)
                shiftKey = sk
                views.append(sk)
            } else {
                let t = (mode == .numbers) ? "#+=" : "123"
                let sk = makeSpecialKey()
                sk.configure(text: t, value: t,
                             font: .systemFont(ofSize: 15, weight: .medium),
                             textColor: keyText, bg: specialBg, pressed: specialPressed,
                             shadow: shadowAlpha, isDark: isDarkMode)
                sk.accessibilityLabel = (mode == .numbers) ? "Symbols" : "Numbers"
                sk.accessibilityHint = "Switch keyboard mode"
                sk.addTarget(self, action: #selector(symbolToggleTapped), for: .touchDown)
                symbolToggleKey = sk
                views.append(sk)
            }
        }

        // Character keys
        for key in keys {
            let display = (mode == .letters && isUppercase) ? key.uppercased() : key
            let kv = makeCharKey(display: display, value: display, lowered: key)
            charKeysByRow[rowIndex].append(kv)
            views.append(kv)
        }

        // Delete on right of row 2
        if rowIndex == 2 {
            let dk = makeSpecialKey()
            dk.setImage("delete.left", pointSize: 18, tint: keyText)
            dk.addTarget(self, action: #selector(deleteTapped), for: .touchDown)
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
            lp.minimumPressDuration = 0.25
            lp.cancelsTouchesInView = false
            dk.addGestureRecognizer(lp)
            deleteKey = dk
            views.append(dk)
        }

        layoutRow(views, rowIndex: rowIndex, container: container, spacing: spacing)
    }

    private func buildBottomRow(in container: UIView) {
        let spacing: CGFloat = 6   // Native iOS inter-key spacing
        var views: [UIView] = []

        // Mode toggle (123 / ABC)
        let mt = makeSpecialKey()
        let modeTitle = (mode == .letters) ? "123" : "ABC"
        mt.configure(text: modeTitle, value: modeTitle,
                     font: .systemFont(ofSize: 16, weight: .regular),
                     textColor: keyText, bg: specialBg, pressed: specialPressed,
                     shadow: shadowAlpha, isDark: isDarkMode)
        mt.accessibilityLabel = (mode == .letters) ? "Numbers" : "Letters"
        mt.accessibilityHint = "Switch keyboard mode"
        mt.addTarget(self, action: #selector(numberToggleTapped), for: .touchDown)
        modeToggleKey = mt
        views.append(mt)

        // Globe / emoji
        let gk = makeSpecialKey()
        if delegate?.needsInputModeSwitchKey == true {
            gk.setImage("globe", pointSize: 17, tint: keyText)
            gk.addTarget(self, action: #selector(globeTapped), for: .touchDown)
        } else {
            gk.setImage("face.smiling", pointSize: 17, tint: keyText)
        }
        globeKey = gk
        views.append(gk)

        // Space bar — widest key, matching Apple's native keyboard proportions.
        // On native iOS Spanish keyboard, bottom row is: [123] [emoji] [_____space_____] [return]
        // NO period key. Space bar takes ~60% of the row width.
        let sp = makeCharKey(display: "", value: " ", lowered: "")
        sp.accessibilityLabel = "Space"
        sp.hitExpandX = 8   // generous horizontal reach
        sp.hitExpandY = 6   // generous vertical reach
        let langLabel = UILabel()
        langLabel.text = "ES"
        langLabel.font = .systemFont(ofSize: 14, weight: .regular)
        langLabel.textColor = keyText.withAlphaComponent(0.35)
        langLabel.translatesAutoresizingMaskIntoConstraints = false
        langLabel.isUserInteractionEnabled = false
        langLabel.isAccessibilityElement = false
        sp.addSubview(langLabel)
        NSLayoutConstraint.activate([
            langLabel.centerXAnchor.constraint(equalTo: sp.centerXAnchor),
            langLabel.centerYAnchor.constraint(equalTo: sp.centerYAnchor),
        ])
        spaceKey = sp
        views.append(sp)

        // NO period key in letters mode — matches native iOS Spanish keyboard exactly.
        // Period is available in numbers/symbols mode.
        periodKey = nil

        // Return — uses icon like native iOS (return arrow) instead of text label
        let rk = makeSpecialKey()
        rk.accessibilityLabel = "Return"
        rk.configure(text: "", value: "return",
                     font: .systemFont(ofSize: 16, weight: .medium),
                     textColor: returnText, bg: returnBg, pressed: specialPressed,
                     shadow: shadowAlpha, isDark: isDarkMode)
        // Use return arrow icon for default/standard return, text for special types
        switch currentReturnKeyType {
        case .go, .search, .send, .next, .done, .join, .route, .emergencyCall:
            rk.label.isHidden = false
            rk.label.text = returnTitle
        default:
            rk.setImage("return.left", pointSize: 18, tint: returnText)
        }
        rk.addTarget(self, action: #selector(returnTapped), for: .touchDown)
        returnKey = rk
        views.append(rk)

        layoutBottomRow(views, container: container, spacing: spacing)
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout helpers
    // -------------------------------------------------------------------------

    private func layoutRow(_ views: [UIView], rowIndex: Int, container: UIView, spacing: CGFloat) {
        guard !views.isEmpty else { return }
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
            $0.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
            $0.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }

        let leftInset: CGFloat = (rowIndex == 1 && mode == .letters) ? 12 : 0

        if rowIndex == 2 {
            let specialW: CGFloat = 44
            let chars = Array(views.dropFirst().dropLast())
            let first = views.first!
            let last = views.last!

            first.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            first.widthAnchor.constraint(equalToConstant: specialW).isActive = true
            last.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
            last.widthAnchor.constraint(equalToConstant: specialW).isActive = true

            if let c0 = chars.first {
                c0.leadingAnchor.constraint(equalTo: first.trailingAnchor, constant: spacing).isActive = true
            }
            if let cN = chars.last {
                cN.trailingAnchor.constraint(equalTo: last.leadingAnchor, constant: -spacing).isActive = true
            }
            for i in 1..<chars.count {
                chars[i].leadingAnchor.constraint(equalTo: chars[i-1].trailingAnchor, constant: spacing).isActive = true
                chars[i].widthAnchor.constraint(equalTo: chars[0].widthAnchor).isActive = true
            }
        } else {
            views[0].leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leftInset).isActive = true
            views.last!.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -leftInset).isActive = true
            for i in 1..<views.count {
                views[i].leadingAnchor.constraint(equalTo: views[i-1].trailingAnchor, constant: spacing).isActive = true
                views[i].widthAnchor.constraint(equalTo: views[0].widthAnchor).isActive = true
            }
        }
    }

    private func layoutBottomRow(_ views: [UIView], container: UIView, spacing: CGFloat) {
        guard views.count == 4 else { return }
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
            $0.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
            $0.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
        let mBtn = views[0], gBtn = views[1], sBar = views[2], rBtn = views[3]

        // Native iOS Spanish keyboard bottom row proportions (measured on iPhone 15, 393pt width):
        //   [123: ~44pt] [globe: ~44pt] [______space: ~240pt______] [return: ~53pt]
        // Total keys = 44+44+240+53 = 381pt  + 3 gaps * 4pt = 393pt (6pt margins)
        // Space bar is ~61% of total width — the dominant key.
        mBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        mBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true

        gBtn.leadingAnchor.constraint(equalTo: mBtn.trailingAnchor, constant: spacing).isActive = true
        gBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true

        sBar.leadingAnchor.constraint(equalTo: gBtn.trailingAnchor, constant: spacing).isActive = true

        rBtn.leadingAnchor.constraint(equalTo: sBar.trailingAnchor, constant: spacing).isActive = true
        rBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        rBtn.widthAnchor.constraint(equalToConstant: 53).isActive = true
    }

    // -------------------------------------------------------------------------
    // MARK: - Key factories
    // -------------------------------------------------------------------------

    private func makeCharKey(display: String, value: String, lowered: String) -> KeyView {
        let kv = KeyView()
        kv.configure(text: display, value: value,
                     font: .systemFont(ofSize: 25, weight: .light),
                     textColor: keyText, bg: keyBg, pressed: keyPressed,
                     shadow: shadowAlpha, isDark: isDarkMode)

        // Fire character on touchDown for instant feel
        kv.addTarget(self, action: #selector(charKeyDown(_:)), for: .touchDown)

        // Long press for accents (only if accent map entry exists)
        if accentMap[lowered] != nil {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(accentLongPress(_:)))
            lp.minimumPressDuration = 0.35
            lp.cancelsTouchesInView = false   // don't block the initial touchDown
            kv.addGestureRecognizer(lp)
        }

        return kv
    }

    private func makeSpecialKey() -> KeyView {
        let kv = KeyView()
        kv.isSpecial = true
        kv.normalBg = specialBg
        kv.pressedBg = specialPressed
        kv.backgroundColor = specialBg
        kv.layer.shadowColor = UIColor.black.cgColor
        kv.layer.shadowOpacity = shadowAlpha
        return kv
    }

    // -------------------------------------------------------------------------
    // MARK: - Apply appearance in-place (no rebuild)
    // -------------------------------------------------------------------------

    private func applyAppearance() {
        backgroundColor = boardBg
        for row in charKeysByRow {
            for kv in row {
                kv.normalBg = kv.isSpecial ? specialBg : keyBg
                kv.pressedBg = kv.isSpecial ? specialPressed : keyPressed
                kv.label.textColor = keyText
                kv.layer.shadowOpacity = shadowAlpha
            }
        }
        for sk in [shiftKey, deleteKey, modeToggleKey, symbolToggleKey, globeKey] {
            guard let sk = sk else { continue }
            sk.normalBg = specialBg
            sk.pressedBg = specialPressed
            sk.backgroundColor = specialBg
            sk.tintColor = keyText
            sk.label.textColor = keyText
            sk.layer.shadowOpacity = shadowAlpha
        }
        if let sk = shiftKey, isCapsLock {
            sk.normalBg = keyBg
            sk.backgroundColor = keyBg
        }
        spaceKey?.normalBg = keyBg
        spaceKey?.pressedBg = keyPressed
        spaceKey?.backgroundColor = keyBg
        if let pk = periodKey {
            pk.normalBg = keyBg
            pk.pressedBg = keyPressed
            pk.label.textColor = keyText
        }

        if let rk = returnKey {
            rk.normalBg = returnBg
            rk.backgroundColor = returnBg
            rk.label.textColor = returnText
            rk.label.text = returnTitle
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions (fire on touchDown for instant response)
    // -------------------------------------------------------------------------

    @objc private func charKeyDown(_ sender: KeyView) {
        let text = sender.keyValue
        guard !text.isEmpty else {
            delegate?.insertText(" ")
            return
        }
        delegate?.insertText(text)

        // Auto-lowercase after typing (unless caps lock) — in-place, no rebuild
        if isUppercase && !isCapsLock && mode == .letters {
            isUppercase = false
            updateLabelsForCase()
        }
    }

    @objc private func shiftTapped(_ sender: KeyView) {
        isUppercase.toggle()
        isCapsLock = false
        updateLabelsForCase()
    }

    @objc private func capsLockTapped() {
        isCapsLock = true
        isUppercase = true
        updateLabelsForCase()
    }

    @objc private func deleteTapped(_ sender: KeyView) {
        delegate?.deleteBackward()
    }

    @objc private func deleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                self?.delegate?.deleteBackward()
            }
        case .ended, .cancelled:
            deleteTimer?.invalidate()
            deleteTimer = nil
        default: break
        }
    }

    @objc private func returnTapped(_ sender: KeyView) {
        delegate?.insertNewline()
    }

    @objc private func numberToggleTapped(_ sender: KeyView) {
        if mode == .letters {
            mode = .numbers
        } else {
            mode = .letters
            isUppercase = true
            isCapsLock = false
        }
        buildKeyboard()
    }

    @objc private func symbolToggleTapped(_ sender: KeyView) {
        mode = (mode == .numbers) ? .symbols : .numbers
        buildKeyboard()
    }

    @objc private func globeTapped(_ sender: KeyView) {
        delegate?.advanceToNextInputMode()
    }

    // -------------------------------------------------------------------------
    // MARK: - Accent Long Press
    // -------------------------------------------------------------------------

    @objc private func accentLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let kv = gesture.view as? KeyView else { return }
        let lowered = kv.keyValue.lowercased()
        guard var accents = accentMap[lowered] else { return }
        if isUppercase || isCapsLock { accents = accents.map { $0.uppercased() } }

        switch gesture.state {
        case .began:
            showAccentPopup(from: kv, accents: accents)
        case .changed:
            let loc = gesture.location(in: accentOverlay)
            accentOverlay?.highlightAccent(at: loc)
        case .ended:
            if let selected = accentOverlay?.selectedAccent() {
                delegate?.insertText(selected)
                if isUppercase && !isCapsLock && mode == .letters {
                    isUppercase = false
                    updateLabelsForCase()
                }
            }
            hideAccentPopup()
        case .cancelled, .failed:
            hideAccentPopup()
        default: break
        }
    }

    private func showAccentPopup(from key: KeyView, accents: [String]) {
        hideAccentPopup()
        let popup = AccentPopupView(accents: accents, keyBg: keyBg, keyText: keyText, isDark: isDarkMode)
        popup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(popup)
        let frame = key.convert(key.bounds, to: self)
        NSLayoutConstraint.activate([
            popup.bottomAnchor.constraint(equalTo: topAnchor, constant: frame.minY - 4),
            popup.centerXAnchor.constraint(equalTo: leadingAnchor, constant: frame.midX),
            popup.heightAnchor.constraint(equalToConstant: 52),
        ])
        accentOverlay = popup
    }

    private func hideAccentPopup() {
        accentOverlay?.removeFromSuperview()
        accentOverlay = nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------

    func updateAppearance(isDark: Bool, returnKeyType: UIReturnKeyType) {
        let changed = (isDarkMode != isDark) || (currentReturnKeyType != returnKeyType)
        isDarkMode = isDark
        currentReturnKeyType = returnKeyType
        if !isBuilt {
            buildKeyboard()
        } else if changed {
            applyAppearance()
        }
    }

    func setShiftState(uppercase: Bool) {
        guard mode == .letters, !isCapsLock else { return }
        if isUppercase != uppercase {
            isUppercase = uppercase
            updateLabelsForCase()
        }
    }
}

// =============================================================================
// MARK: - AccentPopupView
// =============================================================================

private class AccentPopupView: UIView {

    private var accentLabels: [UILabel] = []
    private let accents: [String]
    private var highlightedIndex: Int = -1

    init(accents: [String], keyBg: UIColor, keyText: UIColor, isDark: Bool) {
        self.accents = accents
        super.init(frame: .zero)
        backgroundColor = keyBg
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(accents.count) * 36 + 8).isActive = true

        for a in accents {
            let lbl = UILabel()
            lbl.text = a
            lbl.textAlignment = .center
            lbl.font = .systemFont(ofSize: 22, weight: .regular)
            lbl.textColor = keyText
            lbl.layer.cornerRadius = 5
            lbl.layer.masksToBounds = true
            lbl.isAccessibilityElement = true
            lbl.accessibilityLabel = a
            lbl.accessibilityTraits = .keyboardKey
            stack.addArrangedSubview(lbl)
            accentLabels.append(lbl)
        }

        // Accessibility for accent popup
        isAccessibilityElement = false
        accessibilityLabel = "Accent options"
    }
    required init?(coder: NSCoder) { fatalError() }

    func highlightAccent(at point: CGPoint) {
        for (i, lbl) in accentLabels.enumerated() {
            let f = lbl.convert(lbl.bounds, to: self)
            if f.contains(point) {
                if highlightedIndex != i {
                    if highlightedIndex >= 0 && highlightedIndex < accentLabels.count {
                        accentLabels[highlightedIndex].backgroundColor = .clear
                    }
                    lbl.backgroundColor = .systemBlue
                    lbl.textColor = .white
                    highlightedIndex = i
                }
                return
            }
        }
    }

    func selectedAccent() -> String? {
        guard highlightedIndex >= 0 && highlightedIndex < accents.count else {
            return accents.first
        }
        return accents[highlightedIndex]
    }
}
