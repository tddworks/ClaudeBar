package com.tddworks.claudebar.datasources.process

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Minimal Mach-O headers for the architecture tests: only what the slice reader looks at, the rest zeros. */
internal object MachOFixtures {
    const val ARM64_CPU_TYPE = 0x0100_000C
    const val X86_64_CPU_TYPE = 0x0100_0007

    /** A thin 64-bit Mach-O image header. */
    fun thin(architecture: BinaryArchitecture): ByteArray =
        ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN).apply {
            put(byteArrayOf(0xCF.toByte(), 0xFA.toByte(), 0xED.toByte(), 0xFE.toByte()))
            putInt(cpuType(architecture))
            putInt(0) // cpusubtype
            putInt(2) // filetype: MH_EXECUTE
            putInt(0) // ncmds
            putInt(0) // sizeofcmds
            putInt(0) // flags
            putInt(0) // reserved
        }.array()

    /** A universal binary's fat header listing [architectures]; `fat_arch_64` entries when [magic64]. */
    fun universal(architectures: List<BinaryArchitecture>, magic64: Boolean = false): ByteArray {
        val entrySize = if (magic64) 32 else 20
        return ByteBuffer.allocate(8 + architectures.size * entrySize).order(ByteOrder.BIG_ENDIAN).apply {
            put(byteArrayOf(0xCA.toByte(), 0xFE.toByte(), 0xBA.toByte(), if (magic64) 0xBF.toByte() else 0xBE.toByte()))
            putInt(architectures.size)
            for ((index, architecture) in architectures.withIndex()) {
                val offset = (8 + architectures.size * entrySize + index * 16).toLong()
                putInt(cpuType(architecture))
                putInt(0) // cpusubtype
                if (magic64) {
                    putLong(offset)
                    putLong(16) // size
                    putInt(12) // align (2^12)
                    putInt(0) // reserved
                } else {
                    putInt(offset.toInt())
                    putInt(16) // size
                    putInt(12) // align (2^12)
                }
            }
        }.array()
    }

    /** A shell script: a real file a CLI could be, but no Mach-O header. */
    val shellScript: ByteArray = "#!/bin/sh\necho hi\n".encodeToByteArray()

    /** Plain text that is neither Mach-O nor a script. */
    val plainText: ByteArray = "not a binary\n".encodeToByteArray()

    /** A thin header for [architecture], or a script when it is null — a CLI without arch info. */
    fun binary(architecture: BinaryArchitecture?): ByteArray = architecture?.let(::thin) ?: shellScript

    private fun cpuType(architecture: BinaryArchitecture) =
        if (architecture == BinaryArchitecture.ARM64) ARM64_CPU_TYPE else X86_64_CPU_TYPE
}
