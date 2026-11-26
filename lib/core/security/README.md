# lib/core/security

| File | Contents |
| --- | --- |
| `app_lock.dart` | `AppLock.isEnabled()` / `AppLock.setEnabled(enabled:, auth:)`: the "ask for biometrics or device PIN on open" flag (prefs key `app_lock`). Turning it on first asks `local_auth` to confirm the owner; returns an `AppLockToggleResult`. |
| `pbkdf2.dart` | `Pbkdf2Engine.instance`: the one place passwords become keys (PBKDF2-HMAC-SHA256, 32 bytes). `derive` uses the native code (Android `Pbkdf2.kt`, iOS `AppDelegate.swift`) once it passes a self-test (`selfTestVectors`, generated), else pure Dart in an isolate. `deriveForWriting` always returns the Dart key and only checks native. Iteration counts are always the caller's. |
| `ledger_backup_codec.dart` | The encrypted backup file format. `LedgerBackupCodec.seal` / `open` / `parseHeader`: a JSON header plus the gzipped snapshot sealed with AES-256-GCM under a PBKDF2-HMAC-SHA256 key from the user's passphrase (600,000 iterations). The header is bound to the ciphertext as associated data. Throws `BackupFormatException` or `BackupPassphraseException`. |
| `data_key.dart` | End-to-end encryption of private sync fields. `DataCipher` (`seal` / `open` single strings, `enc1:` prefix), `WrappedDataKey` (the server copy), `DataKeyStore.instance` (`cipher()`, `save()`, `clear()`, static `create()`, `wrap()`, `unwrap()`). |

How the pieces connect:

- `AppLock` is toggled from `screens/offline/settings/privacy_security_screen.dart`.
  `main.dart` reads the same `app_lock` flag to show `LockScreen` and
  re-locks when the app is paused.
- `AuthSession` (core/sync) creates a random 32-byte data key on register,
  wraps it with a PBKDF2 key derived from the password, and uploads only the
  wrapped copy. On login it unwraps it and keeps the raw key in
  `flutter_secure_storage`; a password change re-wraps the same key.
- `sync_crypto.dart` / `sync_codec.dart` use `DataCipher` to seal notes,
  categories, names, etc. before `/sync` and to open them in the reply.
  Amounts, dates and ids stay readable on the server.

Conventions:

- PBKDF2-HMAC-SHA256 (210000 iterations for new wraps) goes through
  `Pbkdf2Engine`: native where available, pure Dart in a background isolate
  otherwise. New wraps and backup files always use the Dart key (native only
  checks); unwraps and backup opens use native and retry in Dart if the key
  does not open the box.
- `open()` passes unsealed (pre-encryption) values through unchanged and
  returns null instead of ciphertext when decryption fails.
- Guests and sessions from before encryption have no key (`cipher()` is null).
