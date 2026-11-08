package io.github.thepushkaraj.callbridge

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {

    private lateinit var statusRow: View
    private lateinit var statusDot: View
    private lateinit var statusText: TextView
    private lateinit var testStatusText: TextView
    private lateinit var hostInput: com.google.android.material.textfield.TextInputEditText
    private lateinit var portInput: com.google.android.material.textfield.TextInputEditText
    private lateinit var secretInput: com.google.android.material.textfield.TextInputEditText
    private lateinit var hostLayout: com.google.android.material.textfield.TextInputLayout
    private lateinit var manualBox: View
    private lateinit var manualToggle: com.google.android.material.button.MaterialButton
    private lateinit var oemHintCard: View
    private lateinit var oemHintText: TextView

    private val prefs by lazy { getSharedPreferences("callbridge", Context.MODE_PRIVATE) }

    private val scannerLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) {
                // The scanner persisted the payload; mirror it into the fields so a
                // later save() can't stomp the scanned port/secret with stale text.
                syncFieldsFromPrefs(force = true)
                val host = prefs.getString("host", null)?.trim().orEmpty()
                val port = prefs.getString("port", null)?.trim().takeUnless { it.isNullOrEmpty() } ?: "8765"
                refreshStatus(pairedHost = host)
                showTestStatus(getString(R.string.paired_check_hint, host, port), ok = true)
            }
        }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            refreshStatus()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusRow = findViewById(R.id.status_row)
        statusDot = findViewById(R.id.status_dot)
        statusText = findViewById(R.id.status_text)
        testStatusText = findViewById(R.id.test_status_text)
        hostInput = findViewById(R.id.host_input)
        portInput = findViewById(R.id.port_input)
        secretInput = findViewById(R.id.secret_input)
        hostLayout = findViewById(R.id.host_layout)
        manualBox = findViewById(R.id.manual_box)
        manualToggle = findViewById(R.id.manual_toggle)
        oemHintCard = findViewById(R.id.oem_hint_card)
        oemHintText = findViewById(R.id.oem_hint_text)

        syncFieldsFromPrefs()

        findViewById<View>(R.id.scan_button).setOnClickListener {
            scannerLauncher.launch(Intent(this, ScannerActivity::class.java))
        }

        manualToggle.setOnClickListener {
            val show = manualBox.visibility != View.VISIBLE
            manualBox.visibility = if (show) View.VISIBLE else View.GONE
            manualToggle.setText(if (show) R.string.manual_toggle_hide else R.string.manual_toggle_show)
        }

        findViewById<View>(R.id.save_button).setOnClickListener { save() }
        findViewById<View>(R.id.test_button).setOnClickListener { sendTest() }

        // Visible version so sideloaded builds are always identifiable.
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            ""
        }
        findViewById<TextView>(R.id.footer_text).text =
            getString(R.string.footer_wifi) + "  ·  v" + versionName

        statusRow.setOnClickListener {
            if (!hasCallPermissions()) requestCallPermissions()
        }

        showOemHintIfNeeded()
        requestNotificationPermissionIfNeeded()
        requestIgnoreBatteryOptimizationsOnce()
        WatchService.start(this)

        if (hasCallPermissions()) {
            refreshStatus()
        } else {
            requestCallPermissions()
        }
    }

    override fun onResume() {
        super.onResume()
        syncFieldsFromPrefs()
        refreshStatus()
    }

    // MARK: Status

    /** Mirrors prefs into the manual-entry fields; force overwrites user-visible text. */
    private fun syncFieldsFromPrefs(force: Boolean = false) {
        fun fill(field: TextView, value: String?) {
            if (force || field.text.isNullOrBlank()) field.setText(value ?: "")
        }
        fill(hostInput, prefs.getString("host", ""))
        fill(portInput, prefs.getString("port", null) ?: "8765")
        fill(secretInput, prefs.getString("secret", ""))
    }

    private fun refreshStatus(pairedHost: String? = null) {
        val host = pairedHost ?: prefs.getString("host", null)?.trim().orEmpty()
        when {
            !hasCallPermissions() -> {
                setDot(R.color.warning_dot)
                statusText.text = getString(R.string.status_permission_needed)
            }
            host.isEmpty() -> {
                setDot(R.color.neutral_dot)
                statusText.text = getString(R.string.status_not_paired)
            }
            else -> {
                setDot(R.color.primary)
                val port = prefs.getString("port", null)?.trim().takeUnless { it.isNullOrEmpty() } ?: "8765"
                statusText.text = getString(R.string.status_paired_watching, host, port)
            }
        }
    }

    private fun setDot(colorRes: Int) {
        statusDot.backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(this, colorRes))
    }

    // MARK: Actions

    private fun save() {
        val host = hostInput.text.toString().trim()
        if (host.isEmpty()) {
            hostLayout.error = getString(R.string.host_required)
            return
        }
        hostLayout.error = null
        prefs.edit()
            .putString("host", host)
            .putString("port", portInput.text.toString().trim().ifEmpty { "8765" })
            .putString("secret", secretInput.text.toString().trim())
            .apply()
        refreshStatus()
        showTestStatus(getString(R.string.status_saved), ok = true)
    }

    private fun sendTest() {
        save()
        showTestStatus(getString(R.string.status_sending), ok = null)
        thread {
            val result = ApiClient.sendEvent(this, ApiClient.EVENT_TEST)
            runOnUiThread {
                result.fold(
                    onSuccess = { showTestStatus(getString(R.string.status_test_ok), ok = true) },
                    onFailure = {
                        showTestStatus(
                            getString(R.string.status_test_failed, it.message ?: "unknown error"),
                            ok = false
                        )
                    }
                )
                refreshStatus()
            }
        }
    }

    private fun showTestStatus(text: String, ok: Boolean?) {
        testStatusText.text = text
        val colorRes = when (ok) {
            true -> R.color.primary
            false -> R.color.error_color
            null -> R.color.on_surface_variant
        }
        testStatusText.setTextColor(ContextCompat.getColor(this, colorRes))
        testStatusText.setTypeface(null, if (ok == true) Typeface.BOLD else Typeface.NORMAL)
    }

    // MARK: Permissions & battery

    private fun hasCallPermissions(): Boolean {
        return CALL_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestCallPermissions() {
        val missing = CALL_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            permissionLauncher.launch(missing.toTypedArray())
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
        }
    }

    private fun requestIgnoreBatteryOptimizationsOnce() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) return
        if (prefs.getBoolean(BATTERY_ASKED_KEY, false)) return
        prefs.edit().putBoolean(BATTERY_ASKED_KEY, true).apply()
        runCatching {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName"))
            )
        }
    }

    private fun showOemHintIfNeeded() {
        val manufacturer = Build.MANUFACTURER
        val hintRes = when {
            manufacturer.equals("vivo", ignoreCase = true) -> R.string.vivo_hint
            manufacturer.equals("oppo", ignoreCase = true) ||
                manufacturer.equals("realme", ignoreCase = true) ||
                manufacturer.equals("xiaomi", ignoreCase = true) -> R.string.generic_oem_hint
            else -> 0
        }
        if (hintRes == 0) return
        oemHintText.setText(hintRes)
        oemHintCard.visibility = View.VISIBLE
        oemHintCard.setOnClickListener {
            runCatching {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName"))
                )
            }
        }
    }

    private companion object {
        const val BATTERY_ASKED_KEY = "asked_battery_optimization"
        val CALL_PERMISSIONS = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_CONTACTS
        )
    }
}
