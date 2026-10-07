package com.tddworks.claudebar.leaderboard

import org.kotlincrypto.hash.sha2.SHA512

/**
 * Ed25519 (RFC 8032) in pure Kotlin, because Kotlin/Native can't call CryptoKit. The arithmetic
 * is TweetNaCl's: field elements are sixteen 16-bit limbs, chosen for being small and auditable
 * rather than fast — the leaderboard signs a handful of requests an hour. A private key is the
 * 32-byte seed, as CryptoKit's `rawRepresentation` is. Signatures are deterministic.
 */
internal object Ed25519 {
    const val SEED_SIZE = 32
    const val SIGNATURE_SIZE = 64

    /** The 32-byte public key of a 32-byte seed. */
    fun publicKey(seed: ByteArray): ByteArray {
        require(seed.size == SEED_SIZE) { "An Ed25519 seed is $SEED_SIZE bytes" }
        val a = clampedScalar(seed)
        return pack(scalarBase(a))
    }

    fun sign(message: ByteArray, seed: ByteArray): ByteArray {
        require(seed.size == SEED_SIZE) { "An Ed25519 seed is $SEED_SIZE bytes" }
        val digest = sha512(seed)
        val a = clampedScalar(seed)
        val publicKey = pack(scalarBase(a))

        val r = reduce(sha512(digest.copyOfRange(32, 64), message))
        val bigR = pack(scalarBase(r))
        val h = reduce(sha512(bigR, publicKey, message))

        val x = LongArray(64)
        for (i in 0 until 32) x[i] = u(r[i])
        for (i in 0 until 32) for (j in 0 until 32) x[i + j] += u(h[i]) * u(a[j])
        val s = ByteArray(32)
        modL(s, x)
        return bigR + s
    }

    /** Whether `signature` is `publicKey`'s over `message`. */
    fun verify(signature: ByteArray, message: ByteArray, publicKey: ByteArray): Boolean {
        if (signature.size != SIGNATURE_SIZE || publicKey.size != 32) return false
        val q = unpackNegated(publicKey) ?: return false
        val h = reduce(sha512(signature.copyOfRange(0, 32), publicKey, message))
        val p = scalarMult(q, h)
        add(p, scalarBase(signature.copyOfRange(32, 64)))
        val t = pack(p)
        var difference = 0
        for (i in 0 until 32) difference = difference or (t[i].toInt() xor signature[i].toInt())
        return difference == 0
    }

    // — Hashing and scalars —

    private fun sha512(vararg parts: ByteArray): ByteArray = SHA512().apply { parts.forEach { update(it) } }.digest()

    private fun clampedScalar(seed: ByteArray): ByteArray = sha512(seed).copyOfRange(0, 32).also {
        it[0] = (it[0].toInt() and 248).toByte()
        it[31] = ((it[31].toInt() and 127) or 64).toByte()
    }

    private fun u(byte: Byte): Long = byte.toLong() and 0xff

    private val L = longArrayOf(
        0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10,
    )

    /** `x` (64 limbs of a byte each, possibly overflowing) mod the group order, into `r`'s 32 bytes. */
    private fun modL(r: ByteArray, x: LongArray) {
        for (i in 63 downTo 32) {
            var carry = 0L
            var j = i - 32
            while (j < i - 12) {
                x[j] += carry - 16 * x[i] * L[j - (i - 32)]
                carry = (x[j] + 128) shr 8
                x[j] -= carry shl 8
                j++
            }
            x[j] += carry
            x[i] = 0
        }
        var carry = 0L
        for (j in 0 until 32) {
            x[j] += carry - (x[31] shr 4) * L[j]
            carry = x[j] shr 8
            x[j] = x[j] and 255
        }
        for (j in 0 until 32) x[j] -= carry * L[j]
        for (i in 0 until 32) {
            x[i + 1] += x[i] shr 8
            r[i] = (x[i] and 255).toByte()
        }
    }

    /** A 64-byte hash mod the group order. */
    private fun reduce(hash: ByteArray): ByteArray {
        val x = LongArray(64) { u(hash[it]) }
        return ByteArray(32).also { modL(it, x) }
    }

    // — The field, GF(2^255 - 19) —

    private fun gf(vararg limbs: Long) = LongArray(16).also { limbs.copyInto(it) }

    private val gf0 = gf()
    private val gf1 = gf(1)
    private val D = gf(
        0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
        0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203,
    )
    private val D2 = gf(
        0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
        0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406,
    )
    private val X = gf(
        0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
        0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169,
    )
    private val Y = gf(
        0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
        0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
    )
    private val I = gf(
        0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
        0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83,
    )

    private fun carry(o: LongArray) {
        for (i in 0 until 16) {
            o[i] += 1L shl 16
            val c = o[i] shr 16
            if (i < 15) o[i + 1] += c - 1 else o[0] += 38 * (c - 1)
            o[i] -= c shl 16
        }
    }

    /** Swaps `p` and `q` when `b` is 1, in constant time. */
    private fun select(p: LongArray, q: LongArray, b: Int) {
        val c = (b - 1).toLong().inv()
        for (i in 0 until 16) {
            val t = c and (p[i] xor q[i])
            p[i] = p[i] xor t
            q[i] = q[i] xor t
        }
    }

    private fun pack25519(o: ByteArray, n: LongArray) {
        val m = gf()
        val t = n.copyOf()
        carry(t); carry(t); carry(t)
        repeat(2) {
            m[0] = t[0] - 0xffed
            for (i in 1 until 15) {
                m[i] = t[i] - 0xffff - ((m[i - 1] shr 16) and 1)
                m[i - 1] = m[i - 1] and 0xffff
            }
            m[15] = t[15] - 0x7fff - ((m[14] shr 16) and 1)
            val b = ((m[15] shr 16) and 1).toInt()
            m[14] = m[14] and 0xffff
            select(t, m, 1 - b)
        }
        for (i in 0 until 16) {
            o[2 * i] = (t[i] and 0xff).toByte()
            o[2 * i + 1] = (t[i] shr 8).toByte()
        }
    }

    private fun differs(a: LongArray, b: LongArray): Boolean {
        val c = ByteArray(32).also { pack25519(it, a) }
        val d = ByteArray(32).also { pack25519(it, b) }
        return !c.contentEquals(d)
    }

    private fun parity(a: LongArray): Int = ByteArray(32).also { pack25519(it, a) }[0].toInt() and 1

    private fun unpack25519(o: LongArray, n: ByteArray) {
        for (i in 0 until 16) o[i] = u(n[2 * i]) + (u(n[2 * i + 1]) shl 8)
        o[15] = o[15] and 0x7fff
    }

    private fun plus(o: LongArray, a: LongArray, b: LongArray) { for (i in 0 until 16) o[i] = a[i] + b[i] }

    private fun minus(o: LongArray, a: LongArray, b: LongArray) { for (i in 0 until 16) o[i] = a[i] - b[i] }

    private fun times(o: LongArray, a: LongArray, b: LongArray) {
        val t = LongArray(31)
        for (i in 0 until 16) for (j in 0 until 16) t[i + j] += a[i] * b[j]
        for (i in 0 until 15) t[i] += 38 * t[i + 16]
        for (i in 0 until 16) o[i] = t[i]
        carry(o); carry(o)
    }

    private fun square(o: LongArray, a: LongArray) = times(o, a, a)

    private fun invert(o: LongArray, i: LongArray) {
        val c = i.copyOf()
        for (a in 253 downTo 0) {
            square(c, c)
            if (a != 2 && a != 4) times(c, c, i)
        }
        c.copyInto(o)
    }

    private fun pow2523(o: LongArray, i: LongArray) {
        val c = i.copyOf()
        for (a in 250 downTo 0) {
            square(c, c)
            if (a != 1) times(c, c, i)
        }
        c.copyInto(o)
    }

    // — Points, in extended coordinates (X, Y, Z, T) —

    private fun add(p: Array<LongArray>, q: Array<LongArray>) {
        val a = gf(); val b = gf(); val c = gf(); val d = gf(); val t = gf()
        val e = gf(); val f = gf(); val g = gf(); val h = gf()
        minus(a, p[1], p[0]); minus(t, q[1], q[0]); times(a, a, t)
        plus(b, p[0], p[1]); plus(t, q[0], q[1]); times(b, b, t)
        times(c, p[3], q[3]); times(c, c, D2)
        times(d, p[2], q[2]); plus(d, d, d)
        minus(e, b, a); minus(f, d, c); plus(g, d, c); plus(h, b, a)
        times(p[0], e, f); times(p[1], h, g); times(p[2], g, f); times(p[3], e, h)
    }

    private fun swap(p: Array<LongArray>, q: Array<LongArray>, b: Int) {
        for (i in 0 until 4) select(p[i], q[i], b)
    }

    private fun pack(p: Array<LongArray>): ByteArray {
        val tx = gf(); val ty = gf(); val zi = gf()
        invert(zi, p[2])
        times(tx, p[0], zi)
        times(ty, p[1], zi)
        val r = ByteArray(32)
        pack25519(r, ty)
        r[31] = (r[31].toInt() xor (parity(tx) shl 7)).toByte()
        return r
    }

    private fun scalarMult(q: Array<LongArray>, s: ByteArray): Array<LongArray> {
        val p = arrayOf(gf0.copyOf(), gf1.copyOf(), gf1.copyOf(), gf0.copyOf())
        for (i in 255 downTo 0) {
            val b = (s[i / 8].toInt() shr (i and 7)) and 1
            swap(p, q, b)
            add(q, p)
            add(p, p)
            swap(p, q, b)
        }
        return p
    }

    private fun scalarBase(s: ByteArray): Array<LongArray> {
        val t = gf().also { times(it, X, Y) }
        return scalarMult(arrayOf(X.copyOf(), Y.copyOf(), gf1.copyOf(), t), s)
    }

    /** The negated point a public key encodes, or null when it encodes none. */
    private fun unpackNegated(key: ByteArray): Array<LongArray>? {
        val r = arrayOf(gf(), gf(), gf1.copyOf(), gf())
        val t = gf(); val chk = gf(); val num = gf(); val den = gf()
        val den2 = gf(); val den4 = gf(); val den6 = gf()
        unpack25519(r[1], key)
        square(num, r[1])
        times(den, num, D)
        minus(num, num, r[2])
        plus(den, r[2], den)
        square(den2, den)
        square(den4, den2)
        times(den6, den4, den2)
        times(t, den6, num)
        times(t, t, den)
        pow2523(t, t)
        times(t, t, num)
        times(t, t, den)
        times(t, t, den)
        times(r[0], t, den)
        square(chk, r[0])
        times(chk, chk, den)
        if (differs(chk, num)) times(r[0], r[0], I)
        square(chk, r[0])
        times(chk, chk, den)
        if (differs(chk, num)) return null
        if (parity(r[0]) == (u(key[31]) shr 7).toInt()) minus(r[0], gf0, r[0])
        times(r[3], r[0], r[1])
        return r
    }
}
