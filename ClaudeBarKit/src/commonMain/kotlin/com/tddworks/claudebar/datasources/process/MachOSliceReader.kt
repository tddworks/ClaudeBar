package com.tddworks.claudebar.datasources.process

/** The processor architecture a Mach-O slice is built for. */
internal enum class BinaryArchitecture { ARM64, X86_64 }

/**
 * The architecture slices a Mach-O binary records, thin or universal, read from its first
 * bytes — so ClaudeBar can tell whether a CLI it resolves runs natively or under Rosetta
 * (#251). Nothing is spawned.
 */
internal object MachOSliceReader {
    /** Room for the fixed header and a fat table of [MAX_FAT_ENTRIES] `fat_arch_64` entries. */
    const val MAX_HEADER_BYTES = 8 + 16 * 32
    private const val MAX_FAT_ENTRIES = 16

    /** The binary at [path]'s architectures in file order; null when the file can't be read. */
    fun architectures(path: String, files: MachineFiles): List<BinaryArchitecture>? =
        files.header(path, MAX_HEADER_BYTES)?.let(::architectures)

    /**
     * The parse itself. Null for anything that isn't a Mach-O image whose slices are known —
     * a script (the npm-wrapper shape), a data file — so callers keep their decision.
     */
    fun architectures(header: ByteArray): List<BinaryArchitecture>? {
        if (header.size < 8) return null
        val b = IntArray(header.size) { header[it].toInt() and 0xFF }
        fun big(at: Int) = (b[at].toLong() shl 24) or (b[at + 1].toLong() shl 16) or (b[at + 2].toLong() shl 8) or b[at + 3].toLong()
        fun little(at: Int) = b[at].toLong() or (b[at + 1].toLong() shl 8) or (b[at + 2].toLong() shl 16) or (b[at + 3].toLong() shl 24)
        val magic = listOf(b[0], b[1], b[2], b[3])
        return when (magic) {
            listOf(0xCF, 0xFA, 0xED, 0xFE) -> listOfNotNull(architecture(little(4)))
            listOf(0xFE, 0xED, 0xFA, 0xCF) -> listOfNotNull(architecture(big(4)))
            listOf(0xCA, 0xFE, 0xBA, 0xBE) -> fatArchitectures(b.size, 20, ::big)
            listOf(0xCA, 0xFE, 0xBA, 0xBF) -> fatArchitectures(b.size, 32, ::big)
            else -> null
        }
    }

    /** A fat table's entries, whose `cputype` is big-endian whatever the host. */
    private fun fatArchitectures(size: Int, entrySize: Int, big: (Int) -> Long): List<BinaryArchitecture>? {
        val count = big(4)
        if (count <= 0 || count > MAX_FAT_ENTRIES) return null
        val slices = mutableListOf<BinaryArchitecture>()
        for (index in 0 until count.toInt()) {
            val at = 8 + index * entrySize
            if (at + 4 > size) break
            architecture(big(at))?.let(slices::add)
        }
        return slices.ifEmpty { null }
    }

    private fun architecture(cpuType: Long): BinaryArchitecture? = when (cpuType) {
        0x0100_000CL -> BinaryArchitecture.ARM64
        0x0100_0007L -> BinaryArchitecture.X86_64
        else -> null
    }
}
