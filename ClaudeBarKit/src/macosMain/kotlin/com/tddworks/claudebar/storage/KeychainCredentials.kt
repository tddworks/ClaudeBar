package com.tddworks.claudebar.storage

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import platform.CoreFoundation.CFDictionaryAddValue
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFMutableDictionaryRef
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.CFTypeRef
import platform.CoreFoundation.CFTypeRefVar
import platform.CoreFoundation.kCFBooleanTrue
import platform.CoreFoundation.kCFTypeDictionaryKeyCallBacks
import platform.CoreFoundation.kCFTypeDictionaryValueCallBacks
import platform.Foundation.CFBridgingRelease
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.dataWithBytes
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.usePinned
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
import platform.Security.errSecItemNotFound
import platform.Security.errSecSuccess
import platform.Security.kSecAttrAccessible
import platform.Security.kSecAttrAccessibleAfterFirstUnlock
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData

/**
 * Secrets as generic-password items in the login Keychain, under one service. A locally
 * built, ad-hoc-signed app can be refused (errSecAuthFailed): callers that must store a
 * secret check it landed (docs/settings.md).
 */
@OptIn(ExperimentalForeignApi::class)
class KeychainCredentials(private val service: String = "com.tddworks.claudebar.credentials") : CredentialRepository {

    override fun save(value: String, key: String) {
        val data = CFBridgingRetain(value.encodeToByteArray().toNSData())
        try {
            val updateStatus = withQuery(key) { query ->
                withDictionary(kSecValueData to data) { update -> SecItemUpdate(query, update) }
            }
            if (updateStatus == errSecSuccess) return
            if (updateStatus != errSecItemNotFound) return fail("update", updateStatus)
            val addStatus = withQuery(key, kSecValueData to data, kSecAttrAccessible to kSecAttrAccessibleAfterFirstUnlock) {
                SecItemAdd(it, null)
            }
            if (addStatus != errSecSuccess) fail("save", addStatus)
        } finally {
            data?.let { CFRelease(it) }
        }
    }

    override fun get(key: String): String? = memScoped {
        val result = alloc<CFTypeRefVar>()
        val status = withQuery(key, kSecReturnData to kCFBooleanTrue, kSecMatchLimit to kSecMatchLimitOne) {
            SecItemCopyMatching(it, result.ptr)
        }
        if (status != errSecSuccess) {
            if (status != errSecItemNotFound) fail("read", status)
            return null
        }
        val data = CFBridgingRelease(result.value) as? NSData ?: return null
        data.toByteArray().decodeToString()
    }

    override fun delete(key: String): Boolean {
        val status = withQuery(key) { SecItemDelete(it) }
        if (status == errSecSuccess || status == errSecItemNotFound) return true
        fail("delete", status)
        return false
    }

    /** class + service + account, plus [extra]; released after [use]. */
    private fun <T> withQuery(key: String, vararg extra: Pair<CFTypeRef?, CFTypeRef?>, use: (CFMutableDictionaryRef?) -> T): T {
        val serviceRef = CFBridgingRetain(service)
        val accountRef = CFBridgingRetain(key)
        try {
            return withDictionary(
                kSecClass to kSecClassGenericPassword, kSecAttrService to serviceRef, kSecAttrAccount to accountRef, *extra,
                use = use,
            )
        } finally {
            serviceRef?.let { CFRelease(it) }
            accountRef?.let { CFRelease(it) }
        }
    }

    private fun <T> withDictionary(vararg entries: Pair<CFTypeRef?, CFTypeRef?>, use: (CFMutableDictionaryRef?) -> T): T {
        val dictionary = CFDictionaryCreateMutable(null, entries.size.toLong(), kCFTypeDictionaryKeyCallBacks.ptr, kCFTypeDictionaryValueCallBacks.ptr)
        entries.forEach { (key, value) -> CFDictionaryAddValue(dictionary, key, value) }
        try {
            return use(dictionary)
        } finally {
            dictionary?.let { CFRelease(it) }
        }
    }

    private fun ByteArray.toNSData(): NSData =
        if (isEmpty()) NSData() else usePinned { NSData.dataWithBytes(it.addressOf(0), size.toULong()) }

    private fun NSData.toByteArray(): ByteArray {
        val size = length.toInt()
        return if (size == 0) ByteArray(0) else bytes!!.readBytes(size)
    }

    // The value is never logged — only what failed and its status.
    private fun fail(operation: String, status: Int) {
        AppLog.credentials.error("Keychain credential $operation failed with status $status")
    }
}
