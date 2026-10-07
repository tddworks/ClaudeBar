package com.tddworks.claudebar.alerting

/**
 * The credentials that let ClaudeBar write to one Notify! device: its id and per-device token.
 * Made by [of] from the pane's two fields, or by [fromPastedText] from whatever is on the
 * clipboard — a Notify! URL with both inside, or a bare `id token` pair.
 */
public class NotifyDeviceLink private constructor(
    /** As the gateway spells it: `IO`+14 or legacy 8 (iPhone, iPad), `WB`+14, `MC`+14, `GRP`+5. */
    val deviceId: String,
    /** The per-device secret: never logged, never in settings.json, never in [toString]. */
    val token: String,
) {
    /** Which namespace the id is in, and so which surfaces this link can carry. */
    val kind: NotifyDeviceKind get() = NotifyDeviceKind.of(deviceId)

    /** Checked before spending a request: the gateway refuses a start for a Mac or a browser. */
    val supportsLiveActivity: Boolean get() = kind.supportsLiveActivity
    val supportsWidget: Boolean get() = kind.supportsWidget
    val supportsScreenWidget: Boolean get() = kind.supportsScreenWidget

    override fun equals(other: Any?): Boolean =
        other is NotifyDeviceLink && deviceId == other.deviceId && token == other.token

    override fun hashCode(): Int = 31 * deviceId.hashCode() + token.hashCode()

    override fun toString(): String = "NotifyDeviceLink($deviceId)"

    companion object {
        /** Both halves trimmed; null when the id is not shaped like one or the token is empty. */
        fun of(deviceId: String, token: String): NotifyDeviceLink? {
            val id = deviceId.trim()
            val secret = token.trim()
            if (!isValidDeviceId(id) || secret.isEmpty()) return null
            return NotifyDeviceLink(id, secret)
        }

        /**
         * A link out of pasted text: any Notify! URL (`/notify/{id}?token=`,
         * `/live-activity/{id}?token=`, `/widgets/{id}?token=` …), else an id and token
         * separated by whitespace, a comma or a colon.
         */
        fun fromPastedText(pastedText: String): NotifyDeviceLink? {
            val text = pastedText.trim()
            if (text.isEmpty()) return null
            PastedUrl.parse(text)?.let { url ->
                return of(url.lastPathSegment ?: "", url.query("token") ?: "")
            }
            val parts = splitPair(text)
            if (parts.size != 2) return null
            return of(parts[0], parts[1])
        }

        /**
         * Whether a string is shaped like a gateway id at all — the gateway's own loose check,
         * so an id from a namespace added later still links. What it can carry is
         * [NotifyDeviceKind]'s question.
         */
        fun isValidDeviceId(value: String): Boolean =
            value.length in 8..32 && value.all { it.isAsciiLetterOrDigit() }

        /**
         * The device id in pasted text, with or without a token: the gateway's own `/link`
         * answer hands back a URL with the token stripped, and half an answer still fills a field.
         */
        fun deviceIdInPastedText(text: String): String? {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) return null
            PastedUrl.parse(trimmed)?.lastPathSegment?.let { if (isValidDeviceId(it)) return it }
            val first = splitPair(trimmed).firstOrNull() ?: return null
            return first.takeIf(::isValidDeviceId)
        }

        private fun splitPair(text: String): List<String> =
            text.split { it.isWhitespace() || it == ',' || it == ':' }

        private fun String.split(separator: (Char) -> Boolean): List<String> {
            val parts = mutableListOf<String>()
            val current = StringBuilder()
            for (c in this) {
                if (separator(c)) {
                    if (current.isNotEmpty()) parts += current.toString()
                    current.clear()
                } else {
                    current.append(c)
                }
            }
            if (current.isNotEmpty()) parts += current.toString()
            return parts
        }
    }
}

internal fun Char.isAsciiLetterOrDigit(): Boolean = this in 'a'..'z' || this in 'A'..'Z' || this in '0'..'9'

/**
 * A URL with an authority (`scheme://host…`), as Foundation's `URLComponents` reads one: a
 * string with spaces is no URL, and `id:token` is a scheme and a path, with no host.
 */
private class PastedUrl(private val path: String, private val rawQuery: String?) {
    /** The last non-empty path segment, where every gateway route that carries an id puts it. */
    val lastPathSegment: String? get() = path.split('/').lastOrNull { it.isNotEmpty() }

    fun query(name: String): String? = rawQuery?.split('&')
        ?.map { it.substringBefore('=') to (if ('=' in it) it.substringAfter('=') else "") }
        ?.firstOrNull { percentDecoded(it.first) == name }
        ?.second?.let(::percentDecoded)

    companion object {
        private val shape = Regex("^[A-Za-z][A-Za-z0-9+.\\-]*://([^/?#]*)([^?#]*)(?:\\?([^#]*))?(?:#.*)?$")

        fun parse(text: String): PastedUrl? {
            if (text.any { it.isWhitespace() }) return null
            val match = shape.matchEntire(text) ?: return null
            return PastedUrl(percentDecoded(match.groupValues[2]), match.groups[3]?.value)
        }

        private fun percentDecoded(value: String): String {
            if ('%' !in value) return value
            val bytes = mutableListOf<Byte>()
            var i = 0
            while (i < value.length) {
                val c = value[i]
                val hex = if (c == '%' && i + 2 < value.length && value[i + 1].isHex() && value[i + 2].isHex()) {
                    value.substring(i + 1, i + 3).toInt(16)
                } else {
                    null
                }
                if (hex != null) {
                    bytes += hex.toByte()
                    i += 3
                } else {
                    bytes += c.toString().encodeToByteArray().toList()
                    i++
                }
            }
            return bytes.toByteArray().decodeToString()
        }

        private fun Char.isHex(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
    }
}

/**
 * Which kind of Notify! identity an id names, and so what ClaudeBar can put on it. The kinds
 * that cannot are named and everything else is allowed — app device ids are not one shape,
 * and refusing an unknown one would break a real phone the day Notify! mints a new format.
 */
public enum class NotifyDeviceKind {
    /** An iPhone or iPad: `IO`+14, or the legacy 8 characters (which older poll-only Macs share). */
    APP_DEVICE,

    /** A push-capable Mac listener, `MC`+14. */
    MAC,

    /** A web-push browser, `WB`+14. */
    WEB,

    /** A notification group, `GRP`+5: a fan-out target with no surface of its own. */
    GROUP,

    /** Well formed but in no namespace named here — let through, since only the gateway can decide. */
    UNRECOGNIZED;

    /** Whether a Live Activity can be started here; the gateway refuses a Mac or a browser with a 400. */
    val supportsLiveActivity: Boolean
        get() = this == APP_DEVICE || this == UNRECOGNIZED

    /** Everything but a group: the gateway puts no device-type gate on widgets. */
    val supportsWidget: Boolean get() = this != GROUP

    /** The Lock Screen widget's answer, for the same reason. */
    val supportsScreenWidget: Boolean get() = supportsWidget

    val supportsAnySurface: Boolean get() = supportsLiveActivity || supportsWidget || supportsScreenWidget

    /** What the settings pane calls it. */
    val displayName: String
        get() = when (this) {
            APP_DEVICE -> "iPhone or iPad"
            MAC -> "Mac"
            WEB -> "browser"
            GROUP -> "group"
            UNRECOGNIZED -> "device"
        }

    /** Why a Live Activity cannot be shown here, for the person who just entered the id; null when it can. */
    val liveActivityUnsupportedReason: String?
        get() = when (this) {
            APP_DEVICE, UNRECOGNIZED -> null
            MAC -> "This is a Mac ID. A Live Activity is an iPhone and iPad feature, so ClaudeBar cannot start one here. The widget still works."
            WEB -> "This is a browser ID. A Live Activity is an iPhone and iPad feature, so ClaudeBar cannot start one here. The widget still works."
            GROUP -> GROUP_REASON
        }

    val screenWidgetUnsupportedReason: String? get() = widgetUnsupportedReason

    /** Only a group cannot keep a widget. */
    val widgetUnsupportedReason: String? get() = if (this == GROUP) GROUP_REASON else null

    companion object {
        private const val GROUP_REASON =
            "This is a group ID. A group fans a notification out to its members and owns no Lock Screen of its own, so use the device ID and token for a single device instead."

        /**
         * The gateway's grammars: `GRP[A-Z0-9]{5}`, `WB[A-Z0-9]{14}`, `MC[A-Z0-9]{14}`,
         * `IO[A-Z0-9]{14}`, legacy `[A-Za-z0-9]{8}` (case-insensitive: older Macs minted mixed
         * case). `GRP`+5 is also 8 long; the group prefix is tested first, as the gateway does.
         * Prefix and length are matched together, so a legacy id that happens to start with
         * "MC" stays a phone.
         */
        fun of(deviceId: String): NotifyDeviceKind {
            fun hasPrefix(prefix: String, count: Int): Boolean =
                deviceId.length == prefix.length + count && deviceId.startsWith(prefix) &&
                    deviceId.drop(prefix.length).all { it in '0'..'9' || it in 'A'..'Z' }

            if (hasPrefix("GRP", 5)) return GROUP
            if (hasPrefix("WB", 14)) return WEB
            if (hasPrefix("MC", 14)) return MAC
            if (hasPrefix("IO", 14)) return APP_DEVICE
            if (deviceId.length == 8 && deviceId.all { it.isAsciiLetterOrDigit() }) return APP_DEVICE
            return UNRECOGNIZED
        }
    }
}

/** What the gateway knows of a device. `name` is never empty: the gateway makes one up from the platform. */
internal data class NotifyDeviceInfo(
    val deviceId: String,
    val name: String,
    val platform: String? = null,
) {
    /** "Apollo (iOS)". */
    val displayDescription: String
        get() = if (platform.isNullOrEmpty()) name else "$name ($platform)"
}
