package com.example.healthysms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ==========================================
// 1. MAIN ACTIVITY (FLUTTER UI BRIDGE)
// ==========================================
class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.example.smshealth/sms"
    private val NOTIFY_CHANNEL = "com.example.smshealth/notify"
    private var eventSink: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver? = null

    companion object {
        var isAppInForeground = false
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerSmsReceiver()
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "showNotification") {
                val sender = call.argument<String>("sender") ?: "Unknown"
                val body = call.argument<String>("body") ?: ""
                val category = call.argument<String>("category") ?: "High Risk"
                showThreatNotification(context, sender, body, category)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        registerSmsReceiver()
    }

    private fun registerSmsReceiver() {
        if (smsReceiver == null) {
            smsReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
                        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                        if (messages.isEmpty()) return
                        val fullMessage = StringBuilder()
                        for (sms in messages) {
                            fullMessage.append(sms.displayMessageBody)
                        }
                        val smsText = fullMessage.toString()
                        val rawSender = messages[0]?.displayOriginatingAddress ?: "Unknown"
                        val senderName = getContactName(context!!, rawSender)

                        if (eventSink != null) {
                            val payload = mapOf("sender" to senderName, "body" to smsText)
                            eventSink?.success(payload)
                        }
                    }
                }
            }
            registerReceiver(smsReceiver, IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION))
        }
    }

    private fun getContactName(context: Context, phoneNumber: String): String {
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phoneNumber))
            val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME))
                    "$name ($phoneNumber)"
                } else phoneNumber
            } ?: phoneNumber
        } catch (e: Exception) { phoneNumber }
    }
}

// ==========================================
// 2. BACKGROUND RECEIVER (HANDLES ALL MSG)
// ==========================================
// ... (Keep your MainActivity class as is)

class SmsBackgroundReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Log to Logcat so you can see it working in Android Studio
        android.util.Log.d("LinkGuard", "SMS Received in Background!")

        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isEmpty()) return

            val fullMessage = StringBuilder()
            for (sms in messages) {
                fullMessage.append(sms.displayMessageBody)
            }
            val smsText = fullMessage.toString()
            val sender = messages[0].displayOriginatingAddress ?: "Unknown"

            // Simplified detection for background to ensure it triggers
            val lowerText = smsText.lowercase()
            val hasUrl = lowerText.contains("http") || lowerText.contains("https") || lowerText.contains("www.")

            // Trigger notification for ALL messages in background as you requested
            if (hasUrl) {
                showThreatNotification(context, sender, smsText, "Threat Detected")
            } else {
                showSafeNotification(context, sender, smsText)
            }
        }
    }
}

// ==========================================
// 3. NOTIFICATION UTILITIES
// ==========================================

// Standard Notification for Normal Messages
fun showSafeNotification(context: Context, sender: String, message: String) {
    val channelId = "SAFE_MSGS"
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(channelId, "Safe Messages", NotificationManager.IMPORTANCE_DEFAULT)
        manager.createNotificationChannel(channel)
    }

    val builder = NotificationCompat.Builder(context, channelId)
        .setSmallIcon(android.R.drawable.ic_menu_send)
        .setContentTitle("🛡️ LinkGuard Secure Inbox: $sender")
        .setContentText(message)
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setAutoCancel(true)

    manager.notify(System.currentTimeMillis().toInt(), builder.build())
}

// Red Alert Notification for Phishing
fun showThreatNotification(context: Context, sender: String, message: String, category: String) {
    val channelId = "LINKGUARD_ALERTS"
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(channelId, "Security Alerts", NotificationManager.IMPORTANCE_HIGH)
        manager.createNotificationChannel(channel)
    }

    val builder = NotificationCompat.Builder(context, channelId)
        .setSmallIcon(android.R.drawable.ic_dialog_alert)
        .setContentTitle("🚨 $category: $sender")
        .setContentText("Suspicious link detected and blocked.")
        .setStyle(NotificationCompat.BigTextStyle().bigText("Blocked Message from $sender:\n$message"))
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setDefaults(NotificationCompat.DEFAULT_ALL)
        .setAutoCancel(true)

    manager.notify(System.currentTimeMillis().toInt(), builder.build())
}