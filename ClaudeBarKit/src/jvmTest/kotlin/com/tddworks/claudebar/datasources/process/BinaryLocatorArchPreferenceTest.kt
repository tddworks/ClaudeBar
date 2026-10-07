package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.process.BinaryArchitecture.ARM64
import com.tddworks.claudebar.datasources.process.BinaryArchitecture.X86_64
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Which binary ClaudeBar picks and spawns (#251): an Intel-only CLI or login shell runs under
 * Rosetta, and macOS names ClaudeBar — the app that spawned it — in its Intel-apps warning.
 */
class BinaryLocatorArchPreferenceTest {
    private val files = FakeFiles()
    private val locator = BinaryLocator(FakeMachine(architecture = ARM64), files, FakeSubprocesses())

    /** `fixture-tool` built for [architecture] (null: a script with no arch info), in its own folder. */
    private fun install(architecture: BinaryArchitecture?, subpath: String) =
        files.install("/tmp/claudebar-locator/$subpath/fixture-tool", MachOFixtures.binary(architecture))

    private fun base(path: String) = path.substringBeforeLast('/')

    // Which shell binary the PATH lookups spawn

    @Test
    fun `should keep the user's shell when it runs natively on this Mac`() {
        assertEquals("/opt/homebrew/bin/fish", BinaryLocator.whichShellPath("/opt/homebrew/bin/fish", ARM64, listOf(ARM64)))
    }

    @Test
    fun `should keep a universal shell as it is`() {
        assertEquals("/bin/zsh", BinaryLocator.whichShellPath("/bin/zsh", ARM64, listOf(ARM64, X86_64)))
    }

    @Test
    fun `should keep the user's shell when its architecture can't be read`() {
        // No arch info is no reason to override anything.
        assertEquals("/usr/local/bin/fish", BinaryLocator.whichShellPath("/usr/local/bin/fish", ARM64, null))
    }

    @Test
    fun `should spawn the system shell when the user's shell is Intel-only on an arm64 Mac`() {
        assertEquals("/bin/zsh", BinaryLocator.whichShellPath("/usr/local/bin/zsh", ARM64, listOf(X86_64)))
    }

    @Test
    fun `should keep an Intel-only shell on an Intel Mac`() {
        assertEquals("/usr/local/bin/zsh", BinaryLocator.whichShellPath("/usr/local/bin/zsh", X86_64, listOf(X86_64)))
    }

    @Test
    fun `should spawn the system shell when the user's shell can't run on this Mac at all`() {
        assertEquals("/bin/zsh", BinaryLocator.whichShellPath("/opt/homebrew/bin/zsh", X86_64, listOf(ARM64)))
    }

    @Test
    fun `should wire the guard to the user's own shell`() {
        // The wiring reads the real shell binary; /bin/zsh is universal on any recent Mac.
        val onDisk = BinaryLocator(FakeMachine(architecture = ARM64), DiskFiles, FakeSubprocesses())

        assertEquals("/bin/zsh", onDisk.whichShellPath("/bin/zsh"))
    }

    // Which copy of a tool wins when several folders have one

    @Test
    fun `should prefer the native copy when two folders both have the CLI`() {
        val intel = install(X86_64, "first/bin")
        val native = install(ARM64, "second/bin")

        val found = locator.candidates(listOf(base(intel), base(native)), "fixture-tool")

        assertEquals(native, found.first())
        assertEquals(2, found.size)
    }

    @Test
    fun `should keep the folder order when the first copy is already native`() {
        val first = install(ARM64, "first/bin")
        val second = install(X86_64, "second/bin")

        assertEquals(first, locator.candidates(listOf(base(first), base(second)), "fixture-tool").first())
    }

    @Test
    fun `should keep the folder order when neither copy is native`() {
        val first = install(X86_64, "first/bin")
        val second = install(X86_64, "second/bin")

        assertEquals(first, locator.candidates(listOf(base(first), base(second)), "fixture-tool").first())
    }

    @Test
    fun `should keep the folder order when neither copy's architecture can be read`() {
        // Scripts (the npm-wrapper shape) carry no arch info; nothing may change.
        val first = install(null, "first/bin")
        val second = install(null, "second/bin")

        val found = locator.candidates(listOf(base(first), base(second)), "fixture-tool")

        assertEquals(first, found.first())
        assertEquals(2, found.size)
    }

    @Test
    fun `should prefer the older nvm version's native copy over a newer Intel-only one`() {
        val older = install(ARM64, "nvm/versions/node/v24.10.0/bin")
        install(X86_64, "nvm/versions/node/v24.11.0/bin")

        // The versions folder contributes one candidate: its best.
        assertEquals(listOf(older), locator.candidates(listOf("/tmp/claudebar-locator/nvm/versions"), "fixture-tool"))
    }

    @Test
    fun `should keep the newer nvm version when both copies are native`() {
        install(ARM64, "nvm/versions/node/v24.10.0/bin")
        val newer = install(ARM64, "nvm/versions/node/v24.11.0/bin")

        assertEquals(newer, locator.candidates(listOf("/tmp/claudebar-locator/nvm/versions"), "fixture-tool").first())
    }

    @Test
    fun `should keep the newer nvm version when neither copy says its architecture`() {
        install(null, "nvm/versions/node/v24.10.0/bin")
        val newer = install(null, "nvm/versions/node/v24.11.0/bin")

        assertEquals(newer, locator.candidates(listOf("/tmp/claudebar-locator/nvm/versions"), "fixture-tool").first())
    }

    // When the login shell's answer gets overridden

    @Test
    fun `should keep the shell's answer when it runs natively`() {
        val answer = install(ARM64, "dir0/bin")

        assertEquals(answer, locator.settled("fixture-tool", answer, emptyList()))
    }

    @Test
    fun `should keep the shell's answer when its architecture can't be read`() {
        val answer = install(null, "dir0/bin")

        assertEquals(answer, locator.settled("fixture-tool", answer, emptyList()))
    }

    @Test
    fun `should keep the shell's Intel-only answer when no native copy exists in the fallback folders`() {
        val answer = install(X86_64, "dir0/bin")
        val fallback = install(X86_64, "dir1/bin")

        assertEquals(answer, locator.settled("fixture-tool", answer, listOf(fallback)))
    }

    @Test
    fun `should prefer the fallback folders' native copy over the shell's Intel-only answer`() {
        val answer = install(X86_64, "dir0/bin")
        val fallback = install(ARM64, "dir1/bin")

        assertEquals(fallback, locator.settled("fixture-tool", answer, listOf(fallback)))
    }
}
