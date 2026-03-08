package com.blackfabricsecurity.crossplatformblackfabric

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createLocationNotificationChannel()
    }

    /**
     * Creates the notification channel required by flutter_background_service
     * before the foreground service starts. Without this, Android 8+ throws
     * "Bad notification for startForeground" and crashes.
     *
     * Channel ID must match notificationChannelId in BackgroundLocation_Service.dart.
     */
    private fun createLocationNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "bfs_location",                          // must match Dart config
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW       // LOW = no sound, stays quiet
            ).apply {
                description = "Shows while Black Fabric Security is tracking your location during a shift."
                setShowBadge(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
