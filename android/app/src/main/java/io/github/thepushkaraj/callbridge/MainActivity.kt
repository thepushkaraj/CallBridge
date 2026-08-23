package io.github.thepushkaraj.callbridge

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
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

        requestPhonePermissionIfNeeded()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PHONE_PERMISSION_REQUEST) {
            statusText.text = if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                getString(R.string.status_phone_permission_granted)
            } else {
                getString(R.string.status_phone_permission_needed)
            }
        }
    }

    private fun requestPhonePermissionIfNeeded() {
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            statusText.text = getString(R.string.status_phone_permission_granted)
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_PHONE_STATE), PHONE_PERMISSION_REQUEST)
        }
    }

    private companion object {
        const val PHONE_PERMISSION_REQUEST = 1
    }
}
