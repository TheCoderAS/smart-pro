package `in`.unisync.unisync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps the app's process alive so the Bluetooth link to the master stays
 * up between uses.
 *
 * The point is the first tap, not the first frame. Painting the dashboard
 * instantly is handled by the snapshot cache; this is what makes the switch
 * actually fire the moment it is tapped, instead of after a scan and a
 * connect. For lighting you reach for in the dark, that difference is the
 * whole feature.
 *
 * Android will not let an app hold a radio connection in the background
 * without a foreground service and a notification the user can see. That is
 * the deal, and it is a fair one — so the notification says something worth
 * reading (which master, connected or not) rather than "app is running".
 *
 * stopWithTask=false in the manifest is what survives a swipe from recents.
 * START_STICKY asks the system to bring us back if it kills us anyway.
 *
 * Not a guarantee. Several Android vendors — Xiaomi, Oppo, Vivo, Huawei —
 * kill foreground services regardless unless the user exempts the app in
 * their own battery settings. No amount of code fixes that; the app has to
 * ask, which is why openBatterySettings exists.
 */
class StayAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "unisync_link"
        const val NOTIFICATION_ID = 1
        const val EXTRA_TEXT = "text"

        fun start(context: Context, text: String) {
            val intent = Intent(context, StayAliveService::class.java)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, StayAliveService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Keeping your switches ready"
        createChannel()
        val notification = buildNotification(text)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14 requires the service type to be declared at start
            // as well as in the manifest, and CONNECTED_DEVICE is the one
            // that covers holding a BLE link.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Restart us if the system reclaims the process; the intent is not
        // worth redelivering, the app re-states its text on next launch.
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Switch connection",
            // LOW: present and readable, but never makes a sound or peeks.
            // This notification is a status line, not an alert.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps your switches reachable the moment you open the app."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Unisync")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
