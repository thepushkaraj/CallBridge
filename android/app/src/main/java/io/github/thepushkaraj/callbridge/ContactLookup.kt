package io.github.thepushkaraj.callbridge

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.util.Log

/** Resolves a phone number to a contact display name when contacts access is granted. */
object ContactLookup {
    private const val TAG = "CallBridge"

    fun resolveName(context: Context, number: String): String {
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
}
