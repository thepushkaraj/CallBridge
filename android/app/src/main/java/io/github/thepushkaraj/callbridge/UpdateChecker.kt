package io.github.thepushkaraj.callbridge

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Checks GitHub Releases for a newer version. Any failure (offline, repo not
 * published yet, rate limit) returns null and the app behaves as before —
 * the update check is the app's only internet call.
 */
object UpdateChecker {
    private const val REPO = "thepushkaraj/CallBridge"
    private const val API = "https://api.github.com/repos/$REPO/releases/latest"
    private const val TIMEOUT_MS = 5000

    data class Update(val version: String, val apkUrl: String)

    fun check(currentVersionName: String): Update? {
        return try {
            val connection = URL(API).openConnection() as HttpURLConnection
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/vnd.github+json")

            val body = if (connection.responseCode == 200) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.disconnect()
                return null
            }

            val root = JSONObject(body)
            val tag = root.optString("tag_name").removePrefix("v")
            val assets = root.optJSONArray("assets") ?: return null

            var apkUrl: String? = null
            for (i in 0 until assets.length()) {
                val asset = assets.getJSONObject(i)
                if (asset.optString("name").endsWith(".apk")) {
                    apkUrl = asset.optString("browser_download_url")
                    break
                }
            }

            val url = apkUrl ?: return null
            if (isNewer(tag, currentVersionName)) Update(version = tag, apkUrl = url) else null
        } catch (e: Exception) {
            null
        }
    }

    /** Semantic compare of dotted version strings, e.g. 0.3.0 vs 0.2.3. */
    fun isNewer(candidate: String, current: String): Boolean {
        fun parts(v: String) = v.removePrefix("v").split('.', '-').mapNotNull { it.toIntOrNull() }
        val a = parts(candidate)
        val b = parts(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }
}
