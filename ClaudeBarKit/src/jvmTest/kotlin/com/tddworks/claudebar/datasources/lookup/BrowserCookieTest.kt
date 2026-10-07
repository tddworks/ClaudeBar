package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookie
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** `browserCookies` — *COOKIE SOURCE*: the first store holding a named cookie. */
class BrowserCookieTest {
    private fun reader(format: BrowserCookieCredential.Format, stores: List<List<BrowserCookie>>) = BrowserCookieReader(
        BrowserCookieCredential(listOf("acme.test"), listOf("session", "csrf"), format),
        FakeCookies(stores, domains = listOf("acme.test"), names = listOf("session", "csrf")),
    )

    @Test
    fun `should use the first named cookie's value as the key when the definition asks for a value`() {
        val found = reader(BrowserCookieCredential.Format.VALUE, listOf(listOf(BrowserCookie("session", "s-1"), BrowserCookie("csrf", "c-1")))).find()
        assertEquals("s-1", found?.credential?.token)
    }

    @Test
    fun `should send every named cookie as one Cookie header when the definition asks for a header`() {
        val found = reader(BrowserCookieCredential.Format.HEADER, listOf(listOf(BrowserCookie("session", "s-1"), BrowserCookie("csrf", "c-1")))).find()
        assertEquals("session=s-1; csrf=c-1", found?.credential?.token)
    }

    @Test
    fun `should pass over a browser whose cookies are empty for the next one`() {
        val found = reader(BrowserCookieCredential.Format.VALUE, listOf(listOf(BrowserCookie("session", "")), listOf(BrowserCookie("session", "s-2")))).find()
        assertEquals("s-2", found?.credential?.token)
    }

    @Test
    fun `should find no key when no browser is signed in`() {
        assertNull(reader(BrowserCookieCredential.Format.VALUE, emptyList()).find())
    }

    @Test
    fun `should name the site, never a cookie's value, in the lookup order`() {
        val lookup = lookup("""{"browserCookies":{"domains":["acme.test"],"names":["session"]}}""")
        assertEquals(listOf("Browser cookies for acme.test"), lookup.lookupOrder)
        assertEquals(CredentialLookup.BrowserCookies(BrowserCookieCredential(listOf("acme.test"), listOf("session"))), lookup)
    }
}
