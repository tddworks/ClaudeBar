package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.process.BinaryArchitecture.ARM64
import com.tddworks.claudebar.datasources.process.BinaryArchitecture.X86_64
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.ByteBuffer

/**
 * The architecture slices of the binaries ClaudeBar resolves and runs (#251): an Intel-only
 * CLI runs under Rosetta, and macOS names ClaudeBar in its "apps for Intel processors" warning.
 */
class MachOSliceReaderTest {
    private val files = FakeFiles()

    private fun read(bytes: ByteArray) = MachOSliceReader.architectures(files.install("/tmp/claudebar-macho", bytes), files)

    @Test
    fun `should read a plain arm64 app as arm64`() {
        assertEquals(listOf(ARM64), read(MachOFixtures.thin(ARM64)))
    }

    @Test
    fun `should read a plain Intel app as Intel-only`() {
        assertEquals(listOf(X86_64), read(MachOFixtures.thin(X86_64)))
    }

    @Test
    fun `should read both slices of a universal app`() {
        assertEquals(listOf(ARM64, X86_64), read(MachOFixtures.universal(listOf(ARM64, X86_64))))
    }

    @Test
    fun `should read a universal app whichever slice comes first`() {
        assertEquals(listOf(X86_64, ARM64), read(MachOFixtures.universal(listOf(X86_64, ARM64))))
    }

    @Test
    fun `should read a universal app's newer 64-bit table too`() {
        assertEquals(listOf(ARM64, X86_64), read(MachOFixtures.universal(listOf(ARM64, X86_64), magic64 = true)))
    }

    @Test
    fun `should keep a universal app's unknown slices from looking like a native twin`() {
        // All slices unknown tells nothing: "can't tell", never "no native slice".
        val header = ByteBuffer.allocate(28).apply {
            put(byteArrayOf(0xCA.toByte(), 0xFE.toByte(), 0xBA.toByte(), 0xBE.toByte()))
            putInt(1)
            putInt(0x0000_0009) // an old CPU type nobody ships anymore
            putInt(0)
            putInt(28)
            putInt(0)
            putInt(12)
        }.array()

        assertNull(read(header))
    }

    @Test
    fun `should admit it can't tell for a shell script`() {
        assertNull(read(MachOFixtures.shellScript))
    }

    @Test
    fun `should admit it can't tell for a file that isn't an app binary`() {
        assertNull(read(MachOFixtures.plainText))
    }

    @Test
    fun `should admit it can't tell for a file that isn't there`() {
        assertNull(MachOSliceReader.architectures("/bin/claudebar-not-a-real-binary", files))
    }

    @Test
    fun `should read macOS's own shell as a universal app`() {
        // The real thing: /bin/zsh has shipped arm64 + x86_64 since macOS 12.
        val slices = MachOSliceReader.architectures("/bin/zsh", DiskFiles).orEmpty()

        assertTrue(ARM64 in slices)
        assertTrue(X86_64 in slices)
    }
}
