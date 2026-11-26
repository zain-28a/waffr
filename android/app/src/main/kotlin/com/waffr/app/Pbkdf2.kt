package com.waffr.app

import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * PBKDF2-HMAC-SHA256 (RFC 8018) over the exact bytes Dart sends.
 *
 * Built on Android's own HmacSHA256 (served by Conscrypt/BoringSSL), with the
 * password as raw UTF-8 bytes from Dart. It deliberately avoids
 * PBEKeySpec(char[]), whose conversion of characters to bytes is up to the
 * provider and has differed across Android versions: that would change the
 * key for Arabic or emoji passwords.
 *
 * Must give the same bytes as the app's Dart implementation
 * (lib/core/security/pbkdf2.dart); Pbkdf2Test checks the shared vectors.
 * Plain JVM code (no Android classes), so the unit tests run on a JVM.
 */
object Pbkdf2 {
    const val MAX_ITERATIONS = 10_000_000
    const val MAX_PASSWORD_BYTES = 1024
    private const val HASH_BYTES = 32

    fun hmacSha256(password: ByteArray, salt: ByteArray, iterations: Int, length: Int = HASH_BYTES): ByteArray {
        require(iterations in 1..MAX_ITERATIONS) { "iterations" }
        require(salt.size in 1..64) { "salt" }
        require(password.size <= MAX_PASSWORD_BYTES) { "password" }
        require(length in 1..64) { "length" }

        // An HMAC key shorter than the 64-byte block is padded with zeros, so
        // an empty password is the same key as 64 zero bytes. SecretKeySpec
        // refuses an empty key; this gives the identical result.
        val key = if (password.isEmpty()) ByteArray(64) else password.copyOf()
        val mac = Mac.getInstance("HmacSHA256")
        try {
            mac.init(SecretKeySpec(key, "HmacSHA256"))
        } finally {
            key.fill(0)
        }

        val out = ByteArray(length)
        val u = ByteArray(HASH_BYTES)
        val t = ByteArray(HASH_BYTES)
        var block = 1
        var offset = 0
        while (offset < length) {
            // U1 = HMAC(P, S || INT(i)); Uj = HMAC(P, Uj-1); T = U1 ^ ... ^ Uc
            mac.update(salt)
            mac.update(byteArrayOf((block ushr 24).toByte(), (block ushr 16).toByte(), (block ushr 8).toByte(), block.toByte()))
            mac.doFinal(u, 0)
            u.copyInto(t)
            for (i in 1 until iterations) {
                mac.update(u)
                mac.doFinal(u, 0)
                for (j in 0 until HASH_BYTES) t[j] = (t[j].toInt() xor u[j].toInt()).toByte()
            }
            val take = minOf(HASH_BYTES, length - offset)
            t.copyInto(out, offset, 0, take)
            offset += take
            block++
        }
        u.fill(0)
        t.fill(0)
        return out
    }

    /**
     * The platform's PBKDF2WithHmacSHA256 SecretKeyFactory. Benchmark only, to
     * compare speed: the app never uses it, because it takes characters, not
     * bytes (see above). Its output is checked against the vectors anyway.
     */
    fun secretKeyFactory(password: ByteArray, salt: ByteArray, iterations: Int, length: Int = HASH_BYTES): ByteArray {
        val chars = String(password, Charsets.UTF_8).toCharArray()
        val spec = PBEKeySpec(chars, salt, iterations, length * 8)
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
            chars.fill('\u0000')
        }
    }
}
