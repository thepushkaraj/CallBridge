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
    companion object {
        const val APP_TAG = "callbridge"

        fun fromJson(raw: String): PairingPayload? {
            return try {
                val obj = org.json.JSONObject(raw)
                if (obj.optString("app", APP_TAG) != APP_TAG) return null
                val host = obj.optString("host").trim()
                val port = obj.optInt("port", 0)
                if (host.isEmpty() || port !in 1..65535) return null
                PairingPayload(
                    host = host,
                    port = port,
                    secret = obj.optString("secret").takeIf { it.isNotEmpty() }
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}
