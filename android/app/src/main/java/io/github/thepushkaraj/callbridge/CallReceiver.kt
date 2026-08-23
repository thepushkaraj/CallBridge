package io.github.thepushkaraj.callbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
        Log.w(TAG, "Phone state: $state, number present: ${!number.isNullOrEmpty()}")

        if (state != TelephonyManager.EXTRA_STATE_RINGING) return

        if (number == null) {
            Log.w(TAG, "No incoming number - READ_PHONE_STATE permission is likely missing")
        }

        val pendingResult = goAsync()
        thread {
            try {
                val result = ApiClient.sendEvent(
                    context.applicationContext,
                    ApiClient.EVENT_RINGING,
                    number ?: ""
                )
                Log.w(TAG, "Send result: $result")
                val handler = Handler(Looper.getMainLooper())
                handler.post {
                    Toast.makeText(
                        context,
                        context.getString(
                            R.string.receiver_toast,
                            if (result.isSuccess) "sent" else "failed"
                        ),
                        Toast.LENGTH_LONG
                    ).show()
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "CallBridge"
    }
}
