# Security Policy

## Supported Versions

| Platform | Version | Supported |
|----------|---------|-----------|
| Android  | 3.0.x   | Yes       |
| iOS      | 9.0.x   | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in SecureChats Keyboard, please report it responsibly.

**Email:** r00tedbrain@immoactivatiassociatssl.com

**What to include:**

- Description of the vulnerability
- Steps to reproduce
- Affected platform (Android, iOS, or both)
- Potential impact assessment
- Any suggested fix (optional)

**Response time:** We aim to acknowledge reports within 72 hours and provide an initial assessment within 7 days.

**Scope:** This policy covers the SecureChats Keyboard application, its keyboard extension, and all cryptographic operations including Signal Protocol implementation, Kyber/ML-KEM key encapsulation, AES-256-GCM storage encryption, and key management.

**Out of scope:**

- Vulnerabilities in third-party dependencies (report directly to the maintainer)
- Issues that require physical access to an unlocked device
- Social engineering attacks

## Disclosure Policy

We follow coordinated disclosure. Please do not publish vulnerability details until we have released a fix or 90 days have passed since the initial report, whichever comes first.

## Security Architecture

For details on the cryptographic architecture, storage encryption, and key management, see the [README](README.md).
