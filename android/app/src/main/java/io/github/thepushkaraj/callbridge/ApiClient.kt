package io.github.thepushkaraj.callbridge

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object ApiClient {
    const val EVENT_RINGING = "ringing"
    const val EVENT_TEST = "test"

    private const val PREFS = "callbridge"
    private const val TIMEOUT_MS = 4000

    fun sendEvent(context: Context, event: String, number: String = "", caller: String = ""): Result<Unit> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val host = prefs.getString("host", null)?.trim().orEmpty()
        if (host.isEmpty()) {
            return Result.failure(IllegalStateException("No Mac IP configured"))
        }
        val port = prefs.getString("port", null)?.trim().takeUnless { it.isNullOrEmpty() } ?: "8765"
        val secret = prefs.getString("secret", null)?.trim().orEmpty()

        val body = JSONObject().apply {
            put("event", event)
            put("number", number)
            put("caller", caller)
            put("device", android.os.Build.MODEL)
        }
        return post("http://$host:$port/call", secret, body)
    }

    private fun post(url: String, secret: String, body: JSONObject): Result<Unit> {
        var connection: HttpURLConnection? = null
        return try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            if (secret.isNotEmpty()) {
                connection.setRequestProperty("X-CallBridge-Secret", secret)
            }
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = connection.responseCode
            if (code in 200..299) {
                Result.success(Unit)
            } else {
                Result.failure(RuntimeException("HTTP $code"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        } finally {
            connection?.disconnect()
        }
    }
}
