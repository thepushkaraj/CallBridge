package io.github.thepushkaraj.callbridge

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
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

        if (state != TelephonyManager.EXTRA_STATE_RINGING) return

        val now = System.currentTimeMillis()
        val pendingResult = goAsync()

        thread {
            try {
                val appContext = context.applicationContext

                if (incomingNumber.isNotEmpty()) {
                    synchronized(lock) {
                        if (now - lastRingTime < DEDUP_WINDOW_MS && lastRingNumber == incomingNumber) {
                            Log.i(TAG, "Ignoring duplicate ringing broadcast for $incomingNumber")
                            return@thread
                        }
                        lastRingTime = now
                        lastRingNumber = incomingNumber
                    }

                    val callerName = resolveCallerName(appContext, incomingNumber)
                    Log.i(TAG, "Sending ringing event: number=$incomingNumber, caller=$callerName")
                    val result = ApiClient.sendEvent(
                        appContext,
                        ApiClient.EVENT_RINGING,
                        number = incomingNumber,
                        caller = callerName
                    )
                    Log.i(TAG, "Send result: $result")
                    showToast(appContext, result.isSuccess)
                } else {
                    if (appContext.checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                        Thread.sleep(EMPTY_NUMBER_DELAY_MS)
                    }
                    synchronized(lock) {
                        if (System.currentTimeMillis() - lastRingTime < DEDUP_WINDOW_MS) {
                            Log.i(TAG, "Ignoring duplicate/superseded empty ringing broadcast")
                            return@thread
                        }
                        lastRingTime = System.currentTimeMillis()
                        lastRingNumber = ""
                    }

                    Log.i(TAG, "Sending ringing event with unknown number")
                    val result = ApiClient.sendEvent(
                        appContext,
                        ApiClient.EVENT_RINGING,
                        number = "",
                        caller = ""
                    )
                    Log.i(TAG, "Send result: $result")
                    showToast(appContext, result.isSuccess)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling phone state broadcast", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun resolveCallerName(context: Context, number: String): String {
        if (number.isBlank()) return ""
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return ""
        }
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(number)
        )
        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
        return try {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (nameIndex != -1) cursor.getString(nameIndex).orEmpty() else ""
                } else ""
            } ?: ""
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve contact name for $number", e)
            ""
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
        const val DEDUP_WINDOW_MS = 4000L
        const val EMPTY_NUMBER_DELAY_MS = 400L

        val lock = Any()
        @Volatile var lastRingTime: Long = 0L
        @Volatile var lastRingNumber: String = ""
    }
}
