package io.github.thepushkaraj.callbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import kotlin.concurrent.thread

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        if (state != TelephonyManager.EXTRA_STATE_RINGING) return

        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER).orEmpty()

        val pendingResult = goAsync()
        thread {
            try {
                ApiClient.sendEvent(
                    context.applicationContext,
                    ApiClient.EVENT_RINGING,
                    number
                )
            } finally {
                pendingResult.finish()
            }
        }
    }
}
