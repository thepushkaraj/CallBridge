package io.github.thepushkaraj.callbridge

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import kotlin.concurrent.thread

class MainActivity : Activity() {
    private lateinit var statusText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val hostInput = findViewById<EditText>(R.id.host_input)
        val portInput = findViewById<EditText>(R.id.port_input)
        val secretInput = findViewById<EditText>(R.id.secret_input)
        val saveButton = findViewById<Button>(R.id.save_button)
        val testButton = findViewById<Button>(R.id.test_button)
        val oemHint = findViewById<TextView>(R.id.oem_hint_text)
        statusText = findViewById(R.id.status_text)

        val prefs = getSharedPreferences("callbridge", Context.MODE_PRIVATE)
        hostInput.setText(prefs.getString("host", ""))
        portInput.setText(prefs.getString("port", "8765"))
        secretInput.setText(prefs.getString("secret", ""))

        saveButton.setOnClickListener {
            prefs.edit()
                .putString("host", hostInput.text.toString().trim())
                .putString("port", portInput.text.toString().trim().ifEmpty { "8765" })
                .putString("secret", secretInput.text.toString().trim())
                .apply()
            statusText.text = getString(R.string.status_saved)
        }

        testButton.setOnClickListener {
            saveButton.performClick()
            statusText.text = getString(R.string.status_sending)
            thread {
                val result = ApiClient.sendEvent(this, ApiClient.EVENT_TEST)
                runOnUiThread {
                    statusText.text = result.fold(
                        onSuccess = { getString(R.string.status_test_ok) },
                        onFailure = { getString(R.string.status_test_failed, it.message ?: "unknown error") }
                    )
                }
            }
        }

        if (Build.MANUFACTURER.equals("vivo", ignoreCase = true)) {
            oemHint.text = getString(R.string.vivo_hint)
            oemHint.setOnClickListener { openAppSettings() }
        } else if (Build.MANUFACTURER.equals("oppo", ignoreCase = true) ||
            Build.MANUFACTURER.equals("realme", ignoreCase = true) ||
            Build.MANUFACTURER.equals("xiaomi", ignoreCase = true)
        ) {
            oemHint.text = getString(R.string.generic_oem_hint)
            oemHint.setOnClickListener { openAppSettings() }
        }

        requestCallPermissionsIfNeeded()
        requestNotificationPermissionIfNeeded()
        requestIgnoreBatteryOptimizationsOnce(prefs)
        WatchService.start(this)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            PHONE_PERMISSION_REQUEST -> statusText.text =
                if (hasCallPermissions()) {
                    getString(R.string.status_phone_permission_granted)
                } else {
                    getString(R.string.status_phone_permission_needed)
                }
        }
    }

    private fun hasCallPermissions(): Boolean {
        return CALL_PERMISSIONS.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }

    private fun requestCallPermissionsIfNeeded() {
        val missing = CALL_PERMISSIONS.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) {
            statusText.text = getString(R.string.status_phone_permission_granted)
        } else {
            requestPermissions(missing.toTypedArray(), PHONE_PERMISSION_REQUEST)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        }
    }

    private fun requestIgnoreBatteryOptimizationsOnce(prefs: android.content.SharedPreferences) {
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

    private fun openAppSettings() {
        runCatching {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:$packageName"))
            )
        }
    }

    private companion object {
        const val PHONE_PERMISSION_REQUEST = 1
        const val NOTIFICATION_PERMISSION_REQUEST = 2
        const val BATTERY_ASKED_KEY = "asked_battery_optimization"
        val CALL_PERMISSIONS = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_CONTACTS
        )
    }
}
