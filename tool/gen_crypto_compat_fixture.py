#!/usr/bin/env python3
"""Writes test/fixtures/crypto_compat.json: a wrapped data key and a backup
file made with Python (hashlib PBKDF2, pyca/cryptography AES-GCM), not with the
app. The Dart tests open both through the Dart and the native engine, which
proves the stored formats the app shipped (WrappedDataKey and waffr-backup v1)
still open, whichever implementation derives the key.

The output is fixed (fixed key, salts and nonces), so the file only changes
when this script does.

    python3 tool/gen_crypto_compat_fixture.py
"""

import base64
import gzip
import hashlib
import json
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test/fixtures/crypto_compat.json"
b64 = lambda raw: base64.b64encode(raw).decode()


def wrapped_key(password: str, iterations: int, salt: bytes, nonce: bytes, data_key: bytes) -> dict:
    # DataKeyStore.wrap: PBKDF2(password) → AES-256-GCM(data_key), stored as
    # base64(nonce || ciphertext || tag).
    kek = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations, 32)
    boxed = nonce + AESGCM(kek).encrypt(nonce, data_key, None)
    return {
        "password": password,
        "data_key_hex": data_key.hex(),
        "wrapped": {"salt": b64(salt), "iterations": iterations, "wrapped_key": b64(boxed)},
    }


def backup_file(passphrase: str, iterations: int, salt: bytes, nonce: bytes, body: dict) -> dict:
    # LedgerBackupCodec v1: AAD = format|version|created_at|kdf|iterations|salt|cipher.
    created_at = "2026-11-20T09:30:00.000Z"
    aad = "|".join(
        ["waffr-backup", "1", created_at, "pbkdf2-hmac-sha256", str(iterations), b64(salt), "aes-256-gcm"]
    ).encode()
    key = hashlib.pbkdf2_hmac("sha256", passphrase.encode("utf-8"), salt, iterations, 32)
    plain = gzip.compress(json.dumps(body, ensure_ascii=False).encode("utf-8"), mtime=0)
    sealed = AESGCM(key).encrypt(nonce, plain, aad)
    file = {
        "format": "waffr-backup",
        "version": 1,
        "created_at": created_at,
        "kdf": {"name": "pbkdf2-hmac-sha256", "iterations": iterations, "salt": b64(salt)},
        "cipher": "aes-256-gcm",
        "nonce": b64(nonce),
        "data": b64(sealed[:-16]),
        "mac": b64(sealed[-16:]),
    }
    return {"passphrase": passphrase, "body": body, "file": json.dumps(file)}


def main() -> None:
    fixture = {
        "wrapped_keys": [
            wrapped_key("correct horse 1", 210_000, bytes(range(16)), bytes(range(12)), bytes(range(32, 64))),
            wrapped_key("كلمة المرور ٢٠٢٦ 🔐", 210_000, bytes(range(50, 66)), bytes(range(1, 13)), bytes(range(64, 96))),
            wrapped_key("é-not-normalised", 100_000, bytes(range(70, 86)), bytes(range(2, 14)), bytes(range(96, 128))),
        ],
        "backups": [
            backup_file(
                "a long backup passphrase",
                100_000,
                bytes(range(16)),
                bytes(range(12)),
                {"snapshot": {"transactions": {"upserts": [{"client_id": "t1", "amount": "12500", "note": "إيجار"}]}}, "account_email": None},
            ),
        ],
    }
    OUT.write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
