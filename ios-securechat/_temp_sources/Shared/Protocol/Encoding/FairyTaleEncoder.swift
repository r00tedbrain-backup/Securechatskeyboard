import Foundation

/// Steganographic encoder that hides encrypted messages inside invisible Unicode characters,
/// appended to decoy fairy tale text.
/// Equivalent to Android's FairyTaleEncoder.java + EncodeHelper.java
struct FairyTaleEncoder: MessageEncoder {

    // MARK: - Invisible Unicode Characters (4-bit mapping)

    /// 16 zero-width/invisible Unicode characters mapping to 4-bit values (0000-1111).
    /// Matches the Android implementation exactly for cross-platform compatibility.
    private static let invisibleChars: [Character] = [
        "\u{200C}", // ZERO WIDTH NON-JOINER        = 0000
        "\u{200D}", // ZERO WIDTH JOINER             = 0001
        "\u{2060}", // WORD JOINER                   = 0010
        "\u{2061}", // FUNCTION APPLICATION           = 0011
        "\u{2062}", // INVISIBLE TIMES                = 0100
        "\u{2063}", // INVISIBLE SEPARATOR            = 0101
        "\u{2064}", // INVISIBLE PLUS                 = 0110
        "\u{206A}", // INHIBIT SYMMETRIC SWAPPING     = 0111
        "\u{206B}", // ACTIVATE SYMMETRIC SWAPPING    = 1000
        "\u{206C}", // INHIBIT ARABIC FORM SHAPING    = 1001
        "\u{206D}", // ACTIVATE ARABIC FORM SHAPING   = 1010
        "\u{206E}", // NATIONAL DIGIT SHAPES          = 1011
        "\u{206F}", // NOMINAL DIGIT SHAPES           = 1100
        "\u{FEFF}", // ZERO WIDTH NO-BREAK SPACE      = 1101
        "\u{200B}", // ZERO WIDTH SPACE               = 1110
        "\u{061C}", // ARABIC LETTER MARK             = 1111
    ]

    /// Reverse lookup: character -> 4-bit value
    private static let charToNibble: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (index, char) in invisibleChars.enumerated() {
            map[char] = UInt8(index)
        }
        return map
    }()

    // MARK: - JSON Key Abbreviations (must match Android's EncodeHelper)

    private static let keyAbbreviations: [(full: String, short: String)] = [
        ("\"preKeyResponse\"", "\"pR\""),
        ("\"ciphertextMessage\"", "\"cM\""),
        ("\"ciphertextType\"", "\"cT\""),
        ("\"timestamp\"", "\"ts\""),
        ("\"signalProtocolAddressName\"", "\"a\""),
        ("\"deviceId\"", "\"d\""),
        ("\"identityKey\"", "\"iK\""),
        ("\"devices\"", "\"dv\""),
        ("\"kyberPubKey\"", "\"kP\""),
        ("\"kyberPreKeyId\"", "\"kI\""),
        ("\"kyberSignature\"", "\"kS\""),
        ("\"signedPreKey\"", "\"sP\""),
        ("\"preKey\"", "\"pK\""),
        ("\"keyId\"", "\"kd\""),
        ("\"publicKey\"", "\"pk\""),
        ("\"signature\"", "\"sg\""),
        ("\"registrationId\"", "\"rI\""),
    ]

    // MARK: - Decoy Fairy Tales

    private static let cinderellaSentences: [String] = [
        "Once upon a time there was a gentleman who married, for his second wife, the proudest and most haughty woman that ever was seen.",
        "She had two daughters of her own, who were, indeed, exactly like her in all things.",
        "The gentleman had also a young daughter, of rare goodness and sweetness of temper.",
        "The poor girl bore all patiently, and dared not complain to her father.",
        "It happened that the King's son gave a ball, and invited to it all persons of fashion.",
        "They talked all day long of nothing but how they should be dressed.",
    ]

    private static let rapunzelSentences: [String] = [
        "There were once a man and a woman who had long in vain wished for a child.",
        "These people had a little window at the back of their house from which a splendid garden could be seen.",
        "The garden was full of the most beautiful flowers and herbs.",
        "It was, however, surrounded by a high wall, and no one dared to go into it.",
        "For it belonged to an enchantress, who had great power and was dreaded by all the world.",
        "One day the woman was standing by the window and looking down into the garden.",
    ]

    // MARK: - Encode

    func encode(_ envelope: MessageEnvelope) throws -> String {
        // 1. Serialize to compact JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let jsonData = try encoder.encode(envelope)
        guard var json = String(data: jsonData, encoding: .utf8) else {
            throw EncodingError.encodingFailed("JSON to string conversion failed")
        }

        // 2. Minify JSON keys
        for abbr in Self.keyAbbreviations {
            json = json.replacingOccurrences(of: abbr.full, with: abbr.short)
        }

        // 3. GZIP compress
        guard let minifiedData = json.data(using: .utf8) else {
            throw EncodingError.encodingFailed("Minified JSON to data failed")
        }
        let compressed = try GZip.compress(minifiedData)

        // 4. Convert bytes to binary, then to invisible Unicode chars (4 bits per char)
        var invisibleString = ""
        for byte in compressed {
            let highNibble = (byte >> 4) & 0x0F
            let lowNibble = byte & 0x0F
            invisibleString.append(Self.invisibleChars[Int(highNibble)])
            invisibleString.append(Self.invisibleChars[Int(lowNibble)])
        }

        // 5. Prepend a random fairy tale sentence as decoy
        let allSentences = Self.cinderellaSentences + Self.rapunzelSentences
        let decoySentence = allSentences.randomElement() ?? allSentences[0]

        return decoySentence + invisibleString
    }

    // MARK: - Decode

    func decode(_ text: String) throws -> MessageEnvelope {
        // 1. Extract invisible characters from the text
        var nibbles: [UInt8] = []
        for char in text {
            if let nibble = Self.charToNibble[char] {
                nibbles.append(nibble)
            }
        }

        guard !nibbles.isEmpty, nibbles.count % 2 == 0 else {
            throw EncodingError.decodingFailed("No valid invisible characters found in text")
        }

        // 2. Reconstruct bytes from nibble pairs
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: nibbles.count, by: 2) {
            let byte = (nibbles[i] << 4) | nibbles[i + 1]
            bytes.append(byte)
        }

        // 3. GZIP decompress
        let decompressed = try GZip.decompress(Data(bytes))

        // 4. De-minify JSON keys
        guard var json = String(data: decompressed, encoding: .utf8) else {
            throw EncodingError.decodingFailed("Decompressed data to string failed")
        }
        // Reverse the abbreviations (short -> full)
        for abbr in Self.keyAbbreviations.reversed() {
            json = json.replacingOccurrences(of: abbr.short, with: abbr.full)
        }

        // 5. Deserialize
        guard let data = json.data(using: .utf8) else {
            throw EncodingError.decodingFailed("De-minified JSON to data failed")
        }
        return try JSONDecoder().decode(MessageEnvelope.self, from: data)
    }
}
