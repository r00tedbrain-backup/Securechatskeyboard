# SecureChat Keyboard — iOS

Post-quantum encrypted keyboard for iOS. End-to-end encryption with Signal Protocol + Kyber PQC, directly from your keyboard.

## Project Structure

```
ios-securechat/
  SecureChatKeyboard/
    Package.swift                          — SPM config (LibSignalClient dependency)
    SecureChatKeyboard/                    — Containing app (SwiftUI)
      SecureChatKeyboardApp.swift           — App entry point
      Views/
        ContentView.swift                   — Setup guide, settings, account info
    KeyboardExtension/                     — Custom Keyboard Extension (UIKit)
      KeyboardViewController.swift          — UIInputViewController (main entry)
      Info.plist                            — Extension config (RequestsOpenAccess=true)
      Views/
        E2EEStripView.swift                 — Encrypt/Decrypt/Contacts strip
      Keyboard/
        KeyboardView.swift                  — QWERTY keyboard layout
    Shared/                                — Code shared between app and extension
      Protocol/
        SignalProtocolManager.swift          — Main E2EE manager (singleton)
        Models/
          Contact.swift                     — Contact model
          StorageMessage.swift              — Chat history record
          MessageEnvelope.swift             — Encrypted message wrapper
          MessageType.swift                 — Message type detection
          PreKeyResponseData.swift          — PreKey serialization models
          PreKeyMetadata.swift              — Key rotation metadata
        Stores/
          SignalStoreManager.swift           — Protocol store persistence
        Encoding/
          MessageEncoder.swift              — Encoder protocol + EncodingMode enum
          RawEncoder.swift                  — JSON encoder
          FairyTaleEncoder.swift            — Steganographic encoder
          Base64MessageEncoder.swift        — Base64 encoder
      Storage/
        KeychainHelper.swift                — iOS Keychain wrapper (hardware-backed)
        AppGroupStorage.swift               — App Group shared container
      Util/
        Logger.swift                        — OSLog wrapper
        GZip.swift                          — ZLIB compression (for steganography)
```

## Architecture

### Containing App (SwiftUI)
The main app provides:
- Setup guide (enable keyboard, grant full access)
- Account information display
- Security specifications
- Data reset functionality

### Keyboard Extension (UIKit)
The custom keyboard provides:
- Full QWERTY keyboard with shift, numbers, symbols
- E2EE control strip with encrypt/decrypt/contacts/chat buttons
- Paste & Decrypt button (iOS has no clipboard listener — explicit action needed)
- Encoding mode toggle (Raw / Fairy Tale / Base64)
- Dark/light mode adaptive appearance

### Shared Framework
Code shared between both targets:
- Signal Protocol manager (encrypt, decrypt, sessions, contacts)
- All data models (Codable for native Swift serialization)
- Storage layer (Keychain + App Group)
- Message encoders (Raw, FairyTale steganography, Base64)

## Dependencies

| Library | Purpose |
|---|---|
| LibSignalClient (SPM) | Signal Protocol — same Rust core as Android's libsignal-android |

LibSignalClient includes Kyber-1024 natively (PQXDH). No BouncyCastle equivalent needed.

## Storage Architecture

| Data | Storage | Security |
|---|---|---|
| Identity key pair | iOS Keychain | Hardware-backed (Secure Enclave) |
| Registration ID | iOS Keychain | Hardware-backed |
| Account credentials | iOS Keychain | Hardware-backed |
| Session records | App Group files | File-level encryption |
| Pre-keys | App Group files | File-level encryption |
| Contacts | App Group files | File-level encryption |
| Messages | App Group files | File-level encryption |
| Metadata | App Group UserDefaults | Standard iOS protection |

## Setup in Xcode

1. Open Xcode > Create new project > App
2. Product Name: `SecureChatKeyboard`
3. Bundle ID: `com.bwt.securechats`
4. Add target: File > New > Target > Custom Keyboard Extension
5. Extension name: `KeyboardExtension`
6. Enable App Groups capability on BOTH targets: `group.com.bwt.securechats`
7. Enable Keychain Sharing on BOTH targets: `com.bwt.securechats.keychain`
8. Add SPM dependency: `https://github.com/signalapp/libsignal` > LibSignalClient
9. Copy source files from this directory into the Xcode project
10. Set deployment target: iOS 16.0
11. Build and run on device (keyboard extensions need a real device to test properly)

## Key Differences from Android Version

| Feature | Android | iOS |
|---|---|---|
| Clipboard detection | Automatic listener | Manual "Paste & Decrypt" button |
| Open Access warning | None (VIBRATE only) | "Full Access" warning shown to user |
| Key storage | EncryptedSharedPreferences | Keychain (Secure Enclave — hardware) |
| Memory limit | Standard service process | 30-60 MB extension limit |
| Serialization | Jackson + JSON | Codable (native Swift) |
| PQC library | BouncyCastle + libsignal | libsignal only (Rust core includes Kyber) |
| Secure text fields | Handled by IME | iOS replaces with system keyboard |
| Keyboard layouts | 49 XML layouts | QWERTY (extensible) |

## TODO (Next Steps)

- [ ] Create Xcode project with proper signing and capabilities
- [ ] Add LibSignalClient SPM dependency
- [ ] Implement actual crypto calls in SignalProtocolManager (marked with TODO)
- [ ] Implement session establishment flow
- [ ] Implement fingerprint verification UI
- [ ] Add more keyboard layouts
- [ ] Add haptic feedback
- [ ] Add contact management sub-views in E2EE strip
- [ ] Test memory usage on older devices
- [ ] App Store submission preparation

## License

GPL-3.0 — Same as the Android version.
