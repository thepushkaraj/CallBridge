package io.github.thepushkaraj.callbridge

/**
 * Connection settings encoded by the Mac app into the pairing QR code:
 * {"app":"callbridge","v":1,"host":"192.168.1.20","port":8765,"secret":"..."}
 * Unknown fields are ignored; `secret` is absent when no secret is set.
 */
data class PairingPayload(
    val host: String,
    val port: Int,
    val secret: String?
) {
    sealed class DecodeResult {
        data class Ok(val payload: PairingPayload) : DecodeResult()
        data object Invalid : DecodeResult()
        data object NotOnLocalNetwork : DecodeResult()
    }

    companion object {
        const val APP_TAG = "callbridge"

        fun fromJson(raw: String): PairingPayload? {
            return (decode(raw) as? DecodeResult.Ok)?.payload
        }

        fun decode(raw: String): DecodeResult {
            return try {
                val obj = org.json.JSONObject(raw)
                if (obj.optString("app", APP_TAG) != APP_TAG) return DecodeResult.Invalid
                val host = obj.optString("host").trim()
                val port = obj.optInt("port", 0)
                if (host.isEmpty() || port !in 1..65535) return DecodeResult.Invalid
                if (!LanAddress.isPrivateIPv4(host)) return DecodeResult.NotOnLocalNetwork
                DecodeResult.Ok(
                    PairingPayload(
                        host = host,
                        port = port,
                        secret = obj.optString("secret").takeIf { it.isNotEmpty() }
                    )
                )
            } catch (e: Exception) {
                DecodeResult.Invalid
            }
        }
    }
}

/** IPv4 addresses that stay on a local network. Hostnames and public IPs are rejected. */
object LanAddress {
    fun isPrivateIPv4(host: String): Boolean {
        val parts = host.split('.')
        if (parts.size != 4) return false
        val octets = parts.map { part ->
            if (part.isEmpty() || part.any { !it.isDigit() }) return false
            if (part.length > 1 && part[0] == '0') return false
            val value = part.toIntOrNull() ?: return false
            if (value !in 0..255) return false
            value
        }
        val first = octets[0]
        val second = octets[1]
        return first == 10 ||
            (first == 172 && second in 16..31) ||
            (first == 192 && second == 168) ||
            (first == 169 && second == 254)
    }
}
