package io.github.thepushkaraj.callbridge

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import kotlin.concurrent.thread

/**
 * Forwards received SMS messages to the Mac as `sms` events. Fully opt-in:
 * the receiver is manifest-registered (system broadcasts wake it even when
 * the app is dead) but does nothing unless the user enabled SMS forwarding
 * and granted [Manifest.permission.RECEIVE_SMS].
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            Log.w(TAG, "Ignoring unexpected action: $action")
            return
        }

        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(SMS_ENABLED_KEY, false)) return
        if (appContext.checkSelfPermission(Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
            Log.i(TAG, "SMS forwarding enabled but RECEIVE_SMS not granted; ignoring")
            return
        }

        val messages: Array<SmsMessage?> = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val sender = messages.firstOrNull { it != null }?.originatingAddress.orEmpty()
        // A single long SMS can arrive split across several PDUs in one intent.
        val body = messages.joinToString("") { it?.displayMessageBody.orEmpty() }.trim()
        if (sender.isEmpty() && body.isEmpty()) {
            Log.i(TAG, "Ignoring SMS broadcast with no sender and no body")
            return
        }

        val now = System.currentTimeMillis()
        synchronized(lock) {
            val key = "$sender|$body"
            // Some dual-SIM devices deliver the same message twice.
            if (key == lastSmsKey && now - lastSmsTime < DEDUP_WINDOW_MS) {
                Log.i(TAG, "Ignoring duplicate SMS broadcast")
                return
            }
            lastSmsKey = key
            lastSmsTime = now
        }

        val pendingResult = goAsync()
        thread {
            try {
                val callerName = ContactLookup.resolveName(appContext, sender)
                Log.i(TAG, "Sending sms event: sender=$sender, caller=$callerName, body=${body.length} chars")
                ApiClient.sendEvent(
                    appContext,
                    ApiClient.EVENT_SMS,
                    number = sender,
                    caller = callerName,
                    body = body
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error handling SMS broadcast", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "CallBridge"
        const val PREFS = "callbridge"
        const val SMS_ENABLED_KEY = "sms_enabled"
        const val DEDUP_WINDOW_MS = 4000L

        val lock = Any()
        @Volatile var lastSmsTime: Long = 0L
        @Volatile var lastSmsKey: String = ""
    }
}
