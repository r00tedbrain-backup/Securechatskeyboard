# SecureChats Keyboard -- iOS

Post-quantum encrypted keyboard for iOS. End-to-end encryption with Signal Protocol + Kyber (ML-KEM / PQXDH), directly from your keyboard. No servers, no accounts, zero data collection.

Developed by **R00tedbrain**. Version 9.0.0.

## Features

- Full QWERTY keyboard matching native iOS look and feel
- End-to-end encryption with one tap from the E2EE control strip
- Signal Protocol (X3DH + Double Ratchet) with post-quantum Kyber-1024 (PQXDH)
- All data encrypted at rest with AES-256-GCM (master key in iOS Keychain / Secure Enclave)
- Three encoding modes: RAW (JSON), Fairy Tale (steganography), Base64
- Paste button for apps with Face ID lock (WhatsApp, banking apps) that clear clipboard on switch
- Contact management, message history, fingerprint verification
- Full Factory Reset option to wipe all data including Keychain
- Works in any app: iMessage, WhatsApp, Telegram, Signal, email, etc.
- Completely offline -- zero network connections
- Open source (GPL-3.0)

## Project Structure

```
SecureChatKeyboard/
  SecureChatKeyboard/                    -- Containing app (SwiftUI)
    SecureChatKeyboardApp.swift           -- App entry point
    Views/
      ContentView.swift                   -- Setup guide, settings, reset buttons, about
      E2EProtocolTest.swift               -- Built-in E2E protocol test
    Shared/                               -- Mirror of KeyboardExtension/Shared (both targets)
  KeyboardExtension/                     -- Custom Keyboard Extension (UIKit)
    KeyboardViewController.swift          -- UIInputViewController (main entry)
    Info.plist                            -- Extension config (RequestsOpenAccess=true)
    Views/
      E2EEStripView.swift                 -- E2EE control strip (5 icons + paste + input field)
    Keyboard/
      KeyboardView.swift                  -- QWERTY keyboard (native iOS dimensions and feel)
    Shared/
      Protocol/
        SignalProtocolManager.swift        -- Signal Protocol + Kyber manager (singleton)
        Models/
          Contact.swift                   -- Contact model
          StorageMessage.swift            -- Chat history record
          MessageEnvelope.swift           -- Encrypted message wrapper (JSON array serialization)
          MessageType.swift               -- Message type detection (invite/message/rotation)
          PreKeyResponseData.swift        -- PreKey bundle serialization
          PreKeyMetadata.swift            -- Key rotation metadata
        Stores/
          SignalStoreManager.swift         -- Protocol store persistence
        Encoding/
          MessageEncoder.swift            -- Encoder protocol + EncodingMode enum
          RawEncoder.swift                -- JSON encoder/decoder
          FairyTaleEncoder.swift          -- Steganographic encoder (Unicode invisible chars)
          Base64MessageEncoder.swift      -- Base64 encoder/decoder
      Storage/
        KeychainHelper.swift              -- iOS Keychain wrapper (Secure Enclave backed)
        AppGroupStorage.swift             -- App Group shared container with AES-256-GCM encryption
      Util/
        Logger.swift                      -- OSLog wrapper (private in Release, public in Debug)
        GZip.swift                        -- ZLIB compression (for steganography)
  SignalFfi/
    libsignal_ffi.a                       -- Universal static library (Git LFS, ~133 MB)
    device/libsignal_ffi.a                -- Device-only library (Git LFS, ~120 MB)
    simulator/libsignal_ffi.a             -- Simulator-only library (Git LFS, ~133 MB)
```

## Security Architecture

| Data | Storage | Protection |
|------|---------|------------|
| Identity key pair | iOS Keychain | Hardware-backed (Secure Enclave), AfterFirstUnlockThisDeviceOnly |
| Registration ID | iOS Keychain | Hardware-backed |
| Account UUID | iOS Keychain | Hardware-backed |
| AES-256 master key | iOS Keychain | Hardware-backed, used for file encryption |
| Session records | App Group files | AES-256-GCM encrypted at rest |
| Pre-keys (ECC + Kyber) | App Group files | AES-256-GCM encrypted at rest |
| Contacts | App Group files | AES-256-GCM encrypted at rest |
| Message history | App Group files | AES-256-GCM encrypted at rest |
| Rotation metadata | App Group UserDefaults | Standard iOS data protection |

### Logging Security

- In **Debug** builds: all logs use `%{public}` for easy debugging
- In **Release** builds: `Logger.log()` and `Logger.debug()` are compiled out entirely. Only `Logger.error()` emits, using `%{private}` redaction. No sensitive data (messages, UUIDs, keys, clipboard) is ever written to the system log in production.

## Keyboard Dimensions (Native iOS Match)

The keyboard replicates native iOS keyboard dimensions:

| Property | Value | Native iOS |
|----------|-------|------------|
| Key height | 42pt | ~42pt |
| Row spacing | 11pt | ~11pt |
| Inter-key spacing | 6pt | ~6pt |
| Font | 25pt SF Light | ~25pt Light |
| Corner radius | 5.5pt | ~5.5pt |
| Bottom row | [123] [globe] [space] [return] | Same (no period in Spanish) |
| Space bar width | ~240pt (iPhone 15) | ~240pt |
| Return key | Arrow icon (53pt) | Arrow icon (~53pt) |
| Total keyboard height | 216pt | ~216pt |

## E2EE Control Strip

The strip above the keyboard provides 5 icon buttons plus a paste button:

1. **Chat bubble** -- Message history with selected contact
2. **Lock** -- Smart decrypt: reads clipboard (or internal field as fallback), detects invites or encrypted messages
3. **Envelope+Lock** -- Encrypt typed message and paste into chat. Long press to change encoding mode.
4. **Person** -- Contacts list (select, add, delete, verify, send invite)
5. **?** -- Help screen with full instructions
6. **Clipboard icon** -- Paste button: reads clipboard immediately into internal field (solves Face ID clipboard clearing)

## Build Requirements

- Xcode 15+
- iOS 16.0 deployment target
- Apple Developer account (for signing and capabilities)
- App Groups: `group.com.bwt.securechats`
- Keychain Sharing: `com.bwt.securechats.keychain`
- Git LFS (for libsignal_ffi.a files)

## Build and Run

```bash
# Clone with LFS
git lfs install
git clone https://github.com/r00tedbrain/SecureChatKeyboardBWT3.0.git
cd SecureChatKeyboardBWT3.0/ios-securechat/SecureChatKeyboard

# Open in Xcode
open SecureChatKeyboard.xcodeproj

# Select scheme: SecureChatKeyboard
# Select device or simulator
# Build and run (Cmd+R)
```

After installing:
1. Open Settings > General > Keyboard > Keyboards > Add New Keyboard > SecureChat
2. Tap SecureChat > Allow Full Access
3. Switch to SecureChat Keyboard in any text field

## Dependencies

| Library | Source | Purpose |
|---------|--------|---------|
| LibSignalClient | libsignal_ffi.a (static, Git LFS) | Signal Protocol + Kyber-1024 (PQXDH) -- same Rust core as Android |
| CryptoKit | iOS SDK | AES-256-GCM storage encryption |

No third-party SDKs, analytics, or tracking frameworks.

## Cross-Platform

Currently iOS-to-iOS only. Android-to-iOS interoperability is planned for a future release. The cryptographic layer is identical (both use libsignal with Kyber). The remaining work is JSON serialization format alignment between platforms.

## License

GPL-3.0
