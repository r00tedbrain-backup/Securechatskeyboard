# SecureChats Keyboard BWT

<div align="center">
  <img src="https://github.com/user-attachments/assets/5a517fa3-29bd-453f-9242-65a7aa058c79" alt="SecureChats Keyboard" width="600" />
</div>

End-to-end encrypted keyboard for **Android** and **iOS**. Encrypts and decrypts messages directly from your keyboard using Signal Protocol with post-quantum Kyber (ML-KEM). No servers, no accounts, no data collection. Works inside any messaging app.

Developed by **R00tedbrain**.

---

## English

### What Is This

SecureChats Keyboard is a custom keyboard that adds end-to-end encryption to any messaging app. Instead of relying on the messenger's own encryption, you encrypt the message yourself before sending it. The recipient decrypts it with the same keyboard on their device. No server or intermediary can read your messages.

The keyboard works offline. It never connects to the internet. All cryptographic operations happen locally on your device.

### Platforms

| Platform | Status | Version | Store |
|----------|--------|---------|-------|
| Android | Released | 3.0.0 | [Google Play](https://play.google.com/store/apps/details?id=com.bwt.securechats&hl=es) |
| iOS | Released | 9.0.0 | [App Store](https://apps.apple.com/es/app/securechatkeyboard/id6759229092) |

### Cryptography

- **Signal Protocol**: X3DH key agreement + Double Ratchet for forward secrecy and post-compromise security
- **Post-Quantum**: Kyber-1024 / ML-KEM via PQXDH (protection against future quantum computing attacks)
- **Storage encryption**: AES-256-GCM at rest
  - Android: EncryptedSharedPreferences (AES256-GCM + hardware-backed MasterKey)
  - iOS: CryptoKit AES-256-GCM with master key in iOS Keychain (Secure Enclave)
- **Key rotation**: Automatic every 2 days
- **Identity keys**: Hardware-backed storage (Android Keystore / iOS Secure Enclave)

### Encoding Modes

Messages can be encoded in three formats:
- **RAW**: Direct JSON output
- **Fairy Tale**: Steganographic encoding using invisible Unicode characters hidden inside a fairy tale story
- **Base64**: Standard Base64 encoding

### How It Works

1. Both users install SecureChats Keyboard
2. User A generates an invite (contains their public key bundle including Kyber keys)
3. User A sends the invite through any messenger (WhatsApp, Telegram, iMessage, etc.)
4. User B copies the invite and processes it with the Lock button
5. A session is established using Signal Protocol + PQXDH
6. Both users can now exchange encrypted messages through any app

The keyboard never sends or receives data. Users manually copy/paste encrypted text through their existing messengers.

### Security Architecture

**Zero data collection.** No analytics, telemetry, crash reports, or tracking of any kind.

**Zero network access.** The app makes no network connections. It works entirely offline.

**No servers.** No backend infrastructure. No accounts. No registration.

**No key recovery.** We have no access to your encryption keys. If you lose them, we cannot recover them.

| Data | Android | iOS |
|------|---------|-----|
| Identity keys | Android Keystore | iOS Keychain (Secure Enclave) |
| Session records | EncryptedSharedPreferences | App Group + AES-256-GCM |
| Pre-keys (ECC + Kyber) | EncryptedSharedPreferences | App Group + AES-256-GCM |
| Contacts | EncryptedSharedPreferences | App Group + AES-256-GCM |
| Message history | EncryptedSharedPreferences | App Group + AES-256-GCM |

### Message Types

1. **PreKeyResponse** -- Invite message containing the public key bundle (ECC + Kyber)
2. **SignalMessage** -- Regular encrypted message (Double Ratchet)
3. **PreKeyResponse + SignalMessage** -- Encrypted message bundled with updated key bundle (key rotation)

### Project Structure

```
SecureChatKeyboardBWT3.0/
  app/                                  -- Android app (Kotlin/Java)
  ios-securechat/
    SecureChatKeyboard/
      SecureChatKeyboard/               -- iOS containing app (SwiftUI)
      KeyboardExtension/                -- iOS keyboard extension (UIKit)
        Keyboard/
          KeyboardView.swift            -- QWERTY keyboard (native iOS feel)
        Views/
          E2EEStripView.swift           -- E2EE control strip
        Shared/
          Protocol/
            SignalProtocolManager.swift  -- Signal Protocol + Kyber
          Storage/
            KeychainHelper.swift        -- iOS Keychain wrapper
            AppGroupStorage.swift       -- Encrypted file storage (AES-256-GCM)
      SignalFfi/                        -- libsignal static libraries (Git LFS)
```

### Building

**Android:**
```bash
git clone https://github.com/r00tedbrain/SecureChatKeyboardBWT3.0.git
cd SecureChatKeyboardBWT3.0
./gradlew assembleDebug
```

**iOS:**
```bash
cd ios-securechat/SecureChatKeyboard
open SecureChatKeyboard.xcodeproj
# Build with Xcode (requires Apple Developer account for signing)
# Deployment target: iOS 16.0
```

iOS requires:
- Xcode 15+
- App Groups capability: `group.com.bwt.securechats`
- Keychain Sharing capability
- libsignal static libraries (included via Git LFS)

### Dependencies

| Library | Platform | Purpose |
|---------|----------|---------|
| libsignal-android 0.73.2 | Android | Signal Protocol + Kyber |
| Bouncy Castle PQC 1.78.1 | Android | Post-quantum cryptography provider |
| AndroidX Security Crypto | Android | EncryptedSharedPreferences |
| Jackson Databind 2.14.1 | Android | JSON serialization |
| LibSignalClient (libsignal_ffi.a) | iOS | Signal Protocol + Kyber (Rust core) |
| CryptoKit | iOS | AES-256-GCM storage encryption |

### Key Differences Between Platforms

| Feature | Android | iOS |
|---------|---------|-----|
| Clipboard access | Automatic listener | Manual Paste button + Lock |
| Permissions | VIBRATE only | Full Access (for clipboard) |
| Key storage | EncryptedSharedPreferences | Keychain (Secure Enclave) |
| File encryption | AES256-GCM (AndroidX) | AES-256-GCM (CryptoKit) |
| PQC library | BouncyCastle + libsignal | libsignal only (Rust core) |
| Serialization | Jackson JSON | Codable (native Swift) |
| Keyboard layouts | 49 XML layouts, 89+ languages | Spanish QWERTY (extensible) |
| Cross-platform | Android-to-Android | iOS-to-iOS |

Cross-platform interoperability (Android to iOS) is planned for a future release.

### Known Limitations

- 1-to-1 conversations only (no group chat)
- Some messengers may not handle invisible Unicode properly (Fairy Tale mode)
- Message size limits on some platforms (~3500 bytes)
- iOS keyboard extensions have a 30-60 MB memory limit
- Cross-platform (Android <-> iOS) not yet supported

### Credits

Originally based on [KryptEY](https://github.com/amnesica/KryptEY) by [mellitopia](https://github.com/mellitopia) and [amnesica](https://github.com/amnesica). The iOS version was built from scratch using the same Signal Protocol foundation.

Keyboard base: [AOSP LatinIME](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/), [Simple Keyboard](https://github.com/rkkr/simple-keyboard), [OpenBoard](https://github.com/openboard-team/openboard).

### License

GPL-3.0. See [LICENSE](LICENSE) for details.

### Links

- [Privacy Policy & Terms](https://r00tedbrain.github.io/securechats-privacy/)
- [GitHub](https://github.com/r00tedbrain)

---

## Espanol

### Que Es

SecureChats Keyboard es un teclado personalizado que anade cifrado de extremo a extremo a cualquier aplicacion de mensajeria. En lugar de depender del cifrado del mensajero, tu cifras el mensaje antes de enviarlo. El destinatario lo descifra con el mismo teclado en su dispositivo. Ningun servidor o intermediario puede leer tus mensajes.

El teclado funciona sin conexion. Nunca se conecta a internet. Todas las operaciones criptograficas ocurren localmente en tu dispositivo.

### Plataformas

| Plataforma | Estado | Version | Tienda |
|------------|--------|---------|--------|
| Android | Publicado | 3.0.0 | [Google Play](https://play.google.com/store/apps/details?id=com.bwt.securechats&hl=es) |
| iOS | Publicado | 9.0.0 | [App Store](https://apps.apple.com/es/app/securechatkeyboard/id6759229092) |

### Criptografia

- **Protocolo Signal**: Acuerdo de claves X3DH + Double Ratchet para forward secrecy y seguridad post-compromiso
- **Post-Cuantico**: Kyber-1024 / ML-KEM via PQXDH (proteccion contra futuros ataques de computacion cuantica)
- **Cifrado en reposo**: AES-256-GCM
  - Android: EncryptedSharedPreferences (AES256-GCM + MasterKey respaldada por hardware)
  - iOS: CryptoKit AES-256-GCM con clave maestra en iOS Keychain (Secure Enclave)
- **Rotacion de claves**: Automatica cada 2 dias
- **Claves de identidad**: Almacenamiento respaldado por hardware (Android Keystore / iOS Secure Enclave)

### Modos de Codificacion

Los mensajes se pueden codificar en tres formatos:
- **RAW**: Salida JSON directa
- **Fairy Tale**: Codificacion esteganografica usando caracteres Unicode invisibles dentro de un cuento de hadas
- **Base64**: Codificacion Base64 estandar

### Como Funciona

1. Ambos usuarios instalan SecureChats Keyboard
2. El usuario A genera una invitacion (contiene su paquete de claves publicas incluyendo Kyber)
3. El usuario A envia la invitacion por cualquier mensajero (WhatsApp, Telegram, iMessage, etc.)
4. El usuario B copia la invitacion y la procesa con el boton Lock
5. Se establece una sesion usando Signal Protocol + PQXDH
6. Ambos usuarios pueden intercambiar mensajes cifrados a traves de cualquier app

El teclado nunca envia ni recibe datos. Los usuarios copian/pegan manualmente texto cifrado a traves de sus mensajeros existentes.

### Seguridad

**Cero recopilacion de datos.** Sin analiticas, telemetria, reportes de errores ni rastreo de ningun tipo.

**Cero acceso a red.** La aplicacion no realiza conexiones de red. Funciona completamente offline.

**Sin servidores.** Sin infraestructura backend. Sin cuentas. Sin registro.

**Sin recuperacion de claves.** No tenemos acceso a tus claves de cifrado. Si las pierdes, no podemos recuperarlas.

### Compilacion

**Android:**
```bash
git clone https://github.com/r00tedbrain/SecureChatKeyboardBWT3.0.git
cd SecureChatKeyboardBWT3.0
./gradlew assembleDebug
```

**iOS:**
```bash
cd ios-securechat/SecureChatKeyboard
open SecureChatKeyboard.xcodeproj
# Compilar con Xcode (requiere cuenta de Apple Developer para firmar)
# Target de despliegue: iOS 16.0
```

### Creditos

Basado originalmente en [KryptEY](https://github.com/amnesica/KryptEY) por [mellitopia](https://github.com/mellitopia) y [amnesica](https://github.com/amnesica). La version iOS fue construida desde cero usando la misma base del Protocolo Signal.

### Licencia

GPL-3.0. Ver [LICENSE](LICENSE) para detalles.

### Enlaces

- [Politica de Privacidad y Terminos](https://r00tedbrain.github.io/securechats-privacy/)
- [GitHub](https://github.com/r00tedbrain)
