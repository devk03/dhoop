package com.noop.ble

import org.junit.Assert.assertEquals
import org.junit.Test

class Whoop5ResponsePayloadOracleTest {
    private fun frame(body: ByteArray): ByteArray {
        val inner = byteArrayOf(36, 9, 22, 7, 1) + body
        val length = inner.size + 4
        return byteArrayOf(0xaa.toByte(), 1, (length and 255).toByte(), (length shr 8).toByte(), 0, 1, 0, 0) + inner + ByteArray(4)
    }
    @Test fun matchesSwiftPayloadOracleAcrossShortAndMultiByteLengths() {
        val cases = listOf(byteArrayOf(), byteArrayOf(0xaa.toByte(), 1, 9),
            byteArrayOf(0xaa.toByte(), 1, 0xff.toByte(), 0xff.toByte()), frame(byteArrayOf()),
            frame(byteArrayOf(0)), frame(byteArrayOf(4, 0, 0)),
            frame(ByteArray(256) { it.toByte() } + byteArrayOf(1, 2, 3)), frame(byteArrayOf(9, 8, 7)).copyOf(7))
        val actual = cases.joinToString("|") { input ->
            whoop5CommandResponsePayload(input)?.joinToString("") { "%02x".format(it.toInt() and 255) } ?: "nil"
        }
        // Verbatim stdout of the production Swift helper compiled standalone, not a hand-copied Kotlin expectation.
        assertEquals("nil|nil|nil|nil|00|040000|000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff010203|nil", actual)
    }
}
