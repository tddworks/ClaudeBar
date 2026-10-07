package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import platform.CoreCrypto.CCCrypt
import platform.CoreCrypto.CCKeyDerivationPBKDF
import platform.CoreCrypto.kCCAlgorithmAES
import platform.CoreCrypto.kCCDecrypt
import platform.CoreCrypto.kCCOptionPKCS7Padding
import platform.CoreCrypto.kCCPBKDF2
import platform.CoreCrypto.kCCPRFHmacAlgSHA1
import platform.CoreCrypto.kCCSuccess
import platform.CoreFoundation.CFDictionaryAddValue
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.CFTypeRefVar
import platform.CoreFoundation.kCFBooleanTrue
import platform.CoreFoundation.kCFTypeDictionaryKeyCallBacks
import platform.CoreFoundation.kCFTypeDictionaryValueCallBacks
import platform.Foundation.CFBridgingRelease
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.NSDate
import platform.Foundation.NSFileHandle
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSPipe
import platform.Foundation.NSString
import platform.Foundation.NSTask
import platform.Foundation.NSURL
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSUserName
import platform.Foundation.create
import platform.Foundation.fileHandleWithNullDevice
import platform.Foundation.readDataToEndOfFile
import platform.Foundation.waitUntilExit
import platform.Foundation.timeIntervalSince1970
import platform.Security.SecItemCopyMatching
import platform.Security.errSecSuccess
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.posix.size_tVar

internal actual fun loginUserName(): String = NSUserName()

/** The real lookup connections on this Mac. */
internal object SystemLookup {
    val security: SecurityTool = SystemSecurityTool
    val database: SQLiteReading by lazy { SystemSQLite() }

    fun browserCookies(home: String = NSHomeDirectory()): BrowserCookieReading =
        BrowserCookieStores(home, database, KeychainSafeStorage, CommonCryptoCookies, now = { NSDate().timeIntervalSince1970 })

    fun browserStorage(home: String = NSHomeDirectory()): BrowserStorageReading = BrowserStorageStores(home)
}

/** `/usr/bin/security`, run to its end; what it printed on stdout. */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
internal object SystemSecurityTool : SecurityTool {
    override fun run(arguments: List<String>): SecurityResult {
        val task = NSTask()
        task.executableURL = NSURL.fileURLWithPath("/usr/bin/security")
        task.arguments = arguments
        val output = NSPipe()
        task.standardOutput = output
        task.standardError = NSFileHandle.fileHandleWithNullDevice()
        if (!task.launchAndReturnError(null)) return SecurityResult(-1, "")
        val data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        val text = NSString.create(data, NSUTF8StringEncoding)?.toString().orEmpty()
        return SecurityResult(task.terminationStatus, text)
    }
}

/**
 * A browser's own Keychain item, read with `SecItemCopyMatching`: macOS asks the person once,
 * by the browser's name, before it hands ClaudeBar the cookie password.
 */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
internal object KeychainSafeStorage : SafeStorageKeychain {
    override fun password(service: String, account: String): String? = memScoped {
        val serviceRef = CFBridgingRetain(service)
        val accountRef = CFBridgingRetain(account)
        val query = CFDictionaryCreateMutable(null, 5, kCFTypeDictionaryKeyCallBacks.ptr, kCFTypeDictionaryValueCallBacks.ptr)
        CFDictionaryAddValue(query, kSecClass, kSecClassGenericPassword)
        CFDictionaryAddValue(query, kSecAttrService, serviceRef)
        CFDictionaryAddValue(query, kSecAttrAccount, accountRef)
        CFDictionaryAddValue(query, kSecMatchLimit, kSecMatchLimitOne)
        CFDictionaryAddValue(query, kSecReturnData, kCFBooleanTrue)
        val result = alloc<CFTypeRefVar>()
        try {
            if (SecItemCopyMatching(query, result.ptr) != errSecSuccess) return null
            val data = CFBridgingRelease(result.value) as? NSData ?: return null
            NSString.create(data, NSUTF8StringEncoding)?.toString()
        } finally {
            query?.let { CFRelease(it) }
            serviceRef?.let { CFRelease(it) }
            accountRef?.let { CFRelease(it) }
        }
    }
}

/** PBKDF2 and AES-CBC through CommonCrypto. */
@OptIn(ExperimentalForeignApi::class)
internal object CommonCryptoCookies : CookieCrypto {
    override fun pbkdf2Sha1(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray? {
        val key = ByteArray(length)
        val status = password.usePinned { pass ->
            salt.usePinned { saltPin ->
                key.usePinned { out ->
                    CCKeyDerivationPBKDF(
                        kCCPBKDF2, pass.addressOf(0), password.size.convert(),
                        saltPin.addressOf(0).reinterpret<UByteVar>(), salt.size.convert(),
                        kCCPRFHmacAlgSHA1, iterations.convert(), out.addressOf(0).reinterpret<UByteVar>(), length.convert(),
                    )
                }
            }
        }
        return if (status == kCCSuccess) key else null
    }

    override fun aes128CbcDecrypt(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray? {
        if (data.isEmpty()) return null
        val output = ByteArray(data.size + 16)
        val status = memScoped {
            val moved = alloc<size_tVar>()
            val status = data.usePinned { input ->
                key.usePinned { keyPin ->
                    iv.usePinned { ivPin ->
                        output.usePinned { out ->
                            CCCrypt(
                                kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                keyPin.addressOf(0), key.size.convert(), ivPin.addressOf(0),
                                input.addressOf(0), data.size.convert(), out.addressOf(0), output.size.convert(), moved.ptr,
                            )
                        }
                    }
                }
            }
            if (status == kCCSuccess) moved.value.toInt() else -1
        }
        return if (status >= 0) output.copyOf(status) else null
    }
}
