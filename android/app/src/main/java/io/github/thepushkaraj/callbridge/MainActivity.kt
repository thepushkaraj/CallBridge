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
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
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
    private lateinit var updateBanner: View
    private lateinit var updateBannerTitle: TextView
    private lateinit var updateButton: com.google.android.material.button.MaterialButton
    private var appVersionName = ""
    private var pendingUpdate: UpdateChecker.Update? = null
    private var availableUpdate: UpdateChecker.Update? = null
    private var updateDialogShown = false
    private var updateApkReady = false
    private var updateCheckRunning = false
    private var activityResumed = false
    private lateinit var smsSwitch: com.google.android.material.materialswitch.MaterialSwitch
    private var pendingSmsEnable = false

    private val prefs by lazy { getSharedPreferences("callbridge", Context.MODE_PRIVATE) }

    private val unknownSourcesLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val update = pendingUpdate
            if (update != null && packageManager.canRequestPackageInstalls()) {
                pendingUpdate = null
                downloadUpdateApk(update.apkUrl)
            }
        }

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
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
            val wasSmsRequest = pendingSmsEnable
            if (pendingSmsEnable) {
                pendingSmsEnable = false
                val granted = grants[Manifest.permission.RECEIVE_SMS] == true
                prefs.edit().putBoolean(SMS_ENABLED_KEY, granted).apply()
                smsSwitch.isChecked = granted
                if (!granted) {
                    showTestStatus(getString(R.string.sms_permission_needed), ok = false)
                }
            }
            refreshStatus()
            // Ask about battery only after the phone-permission dialog has closed.
            if (!wasSmsRequest && hasCallPermissions()) {
                requestIgnoreBatteryOptimizationsOnce()
            }
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

        updateBanner = findViewById(R.id.update_banner)
        updateBannerTitle = findViewById(R.id.update_banner_title)
        updateButton = findViewById(R.id.update_button)

        appVersionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            ""
        }

        smsSwitch = findViewById(R.id.sms_switch)
        smsSwitch.isChecked = prefs.getBoolean(SMS_ENABLED_KEY, false)
        smsSwitch.setOnCheckedChangeListener { _, checked ->
            when {
                !checked -> prefs.edit().putBoolean(SMS_ENABLED_KEY, false).apply()
                ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) ==
                    PackageManager.PERMISSION_GRANTED ->
                    prefs.edit().putBoolean(SMS_ENABLED_KEY, true).apply()

                else -> {
                    pendingSmsEnable = true
                    permissionLauncher.launch(arrayOf(Manifest.permission.RECEIVE_SMS))
                }
            }
        }

        // Visible version so sideloaded builds are always identifiable.
        findViewById<TextView>(R.id.footer_text).text =
            getString(R.string.footer_wifi) + "  ·  v" + appVersionName

        findViewById<View>(R.id.update_button).setOnClickListener {
            when {
                updateApkReady -> openUpdateInstaller()
                availableUpdate != null -> availableUpdate?.let { startUpdate(it) }
            }
        }
        findViewById<View>(R.id.check_updates_button).setOnClickListener {
            if (updateCheckRunning) return@setOnClickListener
            it.isEnabled = false
            checkForAppUpdate(manual = true)
        }

        statusRow.setOnClickListener {
            if (!hasCallPermissions()) requestCallPermissions()
        }

        showOemHintIfNeeded()
        WatchService.start(this)
        checkForAppUpdate()
        refreshStatus()
        requestStartupPermissions()
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        syncFieldsFromPrefs()
        refreshStatus()
    }

    override fun onPause() {
        super.onPause()
        activityResumed = false
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

    private fun save(): Boolean {
        val host = hostInput.text.toString().trim()
        if (host.isEmpty()) {
            hostLayout.error = getString(R.string.host_required)
            return false
        }
        if (!LanAddress.isPrivateIPv4(host)) {
            hostLayout.error = getString(R.string.host_not_local)
            return false
        }
        hostLayout.error = null
        prefs.edit()
            .putString("host", host)
            .putString("port", portInput.text.toString().trim().ifEmpty { "8765" })
            .putString("secret", secretInput.text.toString().trim())
            .apply()
        refreshStatus()
        showTestStatus(getString(R.string.status_saved), ok = true)
        return true
    }

    private fun sendTest() {
        if (!save()) return
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
        return REQUIRED_CALL_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** Phone permissions, plus contacts and notifications the first time they are missing. */
    private fun requestStartupPermissions() {
        val missing = missingCallPermissions(includeContacts = !prefs.getBoolean(CONTACTS_ASKED_KEY, false))
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            missing += Manifest.permission.POST_NOTIFICATIONS
        }
        if (missing.isEmpty()) {
            if (hasCallPermissions()) requestIgnoreBatteryOptimizationsOnce()
            return
        }
        if (missing.contains(Manifest.permission.READ_CONTACTS)) {
            prefs.edit().putBoolean(CONTACTS_ASKED_KEY, true).apply()
        }
        permissionLauncher.launch(missing.toTypedArray())
    }

    private fun requestCallPermissions() {
        val missing = missingCallPermissions(includeContacts = !prefs.getBoolean(CONTACTS_ASKED_KEY, false))
        if (missing.isEmpty()) return
        if (missing.contains(Manifest.permission.READ_CONTACTS)) {
            prefs.edit().putBoolean(CONTACTS_ASKED_KEY, true).apply()
        }
        permissionLauncher.launch(missing.toTypedArray())
    }

    private fun missingCallPermissions(includeContacts: Boolean): MutableList<String> {
        val missing = REQUIRED_CALL_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }.toMutableList()
        if (includeContacts &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            missing += Manifest.permission.READ_CONTACTS
        }
        return missing
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

    // MARK: App update

    private fun checkForAppUpdate(manual: Boolean = false) {
        if (updateCheckRunning) return
        updateCheckRunning = true
        thread {
            val result = UpdateChecker.check(appVersionName)
            runOnUiThread {
                updateCheckRunning = false
                if (manual) {
                    findViewById<View>(R.id.check_updates_button).isEnabled = true
                }
                when (result) {
                    is UpdateChecker.CheckResult.Available -> {
                        availableUpdate = result.update
                        showUpdateBanner()
                        if (!updateDialogShown) {
                            updateDialogShown = true
                            MaterialAlertDialogBuilder(this)
                                .setTitle(getString(R.string.update_available_title, result.update.version))
                                .setMessage(getString(R.string.update_available_message))
                                .setPositiveButton(getString(R.string.update_action)) { _, _ -> startUpdate(result.update) }
                                .setNegativeButton(getString(R.string.update_later), null)
                                .show()
                        }
                    }
                    UpdateChecker.CheckResult.UpToDate ->
                        if (manual) {
                            Toast.makeText(
                                this,
                                getString(R.string.up_to_date, appVersionName),
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    UpdateChecker.CheckResult.Failed ->
                        if (manual) {
                            Toast.makeText(this, R.string.update_check_failed, Toast.LENGTH_SHORT).show()
                        }
                }
            }
        }
    }

    private fun showUpdateBanner() {
        val update = availableUpdate ?: return
        updateBanner.visibility = View.VISIBLE
        findViewById<TextView>(R.id.update_banner_title).text =
            getString(R.string.update_banner_title, update.version)

        // Programmatic colors: the Material style would otherwise paint the
        // label colorPrimary-on-onPrimaryContainer (unreadable on this tint).
        updateButton.setTextColor(ContextCompat.getColor(this, R.color.primary_container))
        updateButton.backgroundTintList =
            ColorStateList.valueOf(ContextCompat.getColor(this, R.color.on_primary_container))
        updateButton.text = getString(R.string.update_button_download)
    }

    private fun startUpdate(update: UpdateChecker.Update) {
        if (!packageManager.canRequestPackageInstalls()) {
            pendingUpdate = update
            unknownSourcesLauncher.launch(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
            )
            return
        }
        downloadUpdateApk(update.apkUrl)
    }

    private fun downloadUpdateApk(apkUrl: String) {
        // The label becomes a bare percentage; pin the laid-out width so the
        // button doesn't visibly shrink when the text gets short.
        updateButton.minWidth = updateButton.width
        updateButton.isEnabled = false
        updateButton.text = "0%"
        thread {
            val destination = File(
                getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                "CallBridge-update.apk"
            )
            var connection: HttpURLConnection? = null
            try {
                connection = URL(apkUrl).openConnection() as HttpURLConnection
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.connect()
                val status = connection.responseCode
                if (status !in 200..299) {
                    error("HTTP $status")
                }
                val total = connection.contentLengthLong
                connection.inputStream.use { input ->
                    FileOutputStream(destination).use { output ->
                        val buffer = ByteArray(8192)
                        var read: Int
                        var written = 0L
                        var lastReported = 0L
                        var checkedMagic = false
                        while (input.read(buffer).also { read = it } != -1) {
                            if (!checkedMagic) {
                                if (read < 2 || buffer[0] != 0x50.toByte() || buffer[1] != 0x4B.toByte()) {
                                    error("Downloaded file is not an APK")
                                }
                                checkedMagic = true
                            }
                            output.write(buffer, 0, read)
                            written += read
                            if (total > 0 && written - lastReported > total / 20) {
                                lastReported = written
                                runOnUiThread {
                                    if (!isFinishing) {
                                        updateButton.text = "${written * 100 / total}%"
                                    }
                                }
                            }
                        }
                        if (!checkedMagic) error("Downloaded file is not an APK")
                    }
                }
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    updateApkReady = true
                    updateButton.isEnabled = true
                    updateButton.text = getString(R.string.update_button_install)
                    openUpdateInstaller()
                }
            } catch (e: Exception) {
                destination.delete()
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    updateButton.isEnabled = true
                    updateButton.text = getString(R.string.update_button_download)
                    Toast.makeText(this, R.string.update_download_failed, Toast.LENGTH_SHORT).show()
                }
            } finally {
                connection?.disconnect()
            }
        }
    }

    private fun openUpdateInstaller() {
        val apk = File(
            getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "CallBridge-update.apk"
        )
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        val install = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(install)
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
        const val CONTACTS_ASKED_KEY = "asked_contacts"
        const val SMS_ENABLED_KEY = "sms_enabled"
        val REQUIRED_CALL_PERMISSIONS = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG
        )
    }
}
