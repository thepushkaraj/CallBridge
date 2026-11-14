package io.github.thepushkaraj.callbridge

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Checks GitHub Releases for a newer version. The check is the app's only
 * internet call; failures are reported so manual checks can surface them.
 */
object UpdateChecker {
    private const val REPO = "thepushkaraj/CallBridge"
    private const val API = "http://127.0.0.1:8000/releases/latest.json"
    private const val TIMEOUT_MS = 5000

    data class Update(val version: String, val apkUrl: String)

    sealed class CheckResult {
        data class Available(val update: Update) : CheckResult()
        /** 200 with nothing newer, or the repo has no published releases yet. */
        object UpToDate : CheckResult()
        /** Network error or unexpected response. */
        object Failed : CheckResult()
    }

    fun check(currentVersionName: String): CheckResult {
        return try {
            val connection = URL(API).openConnection() as HttpURLConnection
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/vnd.github+json")

            val status = connection.responseCode
            if (status == 404) return CheckResult.UpToDate // no releases published yet
            if (status != 200) {
                connection.disconnect()
                return CheckResult.Failed
            }

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val root = JSONObject(body)
            val tag = root.optString("tag_name").removePrefix("v")
            val assets = root.optJSONArray("assets") ?: return CheckResult.UpToDate

            var apkUrl: String? = null
            for (i in 0 until assets.length()) {
                val asset = assets.getJSONObject(i)
                if (asset.optString("name").endsWith(".apk")) {
                    apkUrl = asset.optString("browser_download_url")
                    break
                }
            }

            val url = apkUrl ?: return CheckResult.UpToDate
            val update = Update(version = tag, apkUrl = url)
            if (isNewer(tag, currentVersionName)) CheckResult.Available(update) else CheckResult.UpToDate
        } catch (e: Exception) {
            CheckResult.Failed
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
