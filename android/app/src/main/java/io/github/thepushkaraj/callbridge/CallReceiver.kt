package io.github.thepushkaraj.callbridge

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log
import android.widget.Toast
import kotlin.concurrent.thread

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            Log.w(TAG, "Ignoring unexpected action: $action")
            return
        }

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
        val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)?.trim().orEmpty()
        Log.w(TAG, "Phone state: $state, number present: ${incomingNumber.isNotEmpty()}")

        if (state == TelephonyManager.EXTRA_STATE_IDLE || state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
            synchronized(lock) {
                isRinging = false
                lastRingNumber = ""
            }
            return
        }

        if (state != TelephonyManager.EXTRA_STATE_RINGING) return

        val appContext = context.applicationContext
        val hasCallLogPermission = appContext.checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED

        // On Android 9+, the telephony framework delivers an initial broadcast without extras on cell paging,
        // followed shortly by the authoritative broadcast with caller ID.
        // When READ_CALL_LOG is granted, skip the preliminary numberless broadcast so we only notify with caller info.
        if (hasCallLogPermission && incomingNumber.isEmpty()) {
            Log.i(TAG, "Ignoring preliminary numberless broadcast (waiting for caller ID)")
            return
        }

        val now = System.currentTimeMillis()
        synchronized(lock) {
            if (isRinging && lastRingNumber == incomingNumber && (now - lastRingTime < DEDUP_WINDOW_MS)) {
                Log.i(TAG, "Ignoring duplicate ringing broadcast for $incomingNumber")
                return
            }
            isRinging = true
            lastRingTime = now
            lastRingNumber = incomingNumber
        }

        val pendingResult = goAsync()
        thread {
            try {
                val callerName = ContactLookup.resolveName(appContext, incomingNumber)
                Log.i(TAG, "Sending ringing event: number=$incomingNumber, caller=$callerName")
                val result = ApiClient.sendEvent(
                    appContext,
                    ApiClient.EVENT_RINGING,
                    number = incomingNumber,
                    caller = callerName
                )
                Log.i(TAG, "Send result: $result")
                showToast(appContext, result.isSuccess)
            } catch (e: Exception) {
                Log.e(TAG, "Error handling phone state broadcast", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun showToast(context: Context, isSuccess: Boolean) {
        val handler = Handler(Looper.getMainLooper())
        handler.post {
            Toast.makeText(
                context,
                context.getString(
                    R.string.receiver_toast,
                    if (isSuccess) "sent" else "failed"
                ),
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private companion object {
        const val TAG = "CallBridge"
        const val DEDUP_WINDOW_MS = 8000L

        val lock = Any()
        @Volatile var isRinging: Boolean = false
        @Volatile var lastRingTime: Long = 0L
        @Volatile var lastRingNumber: String = ""
    }
}
