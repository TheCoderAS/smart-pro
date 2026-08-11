package `in`.unisync.unisync

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Brings the keep-ready service back after a reboot or an app update.
 *
 * Without this, "always running" quietly meant "until you restart your
 * phone" — and someone who reaches for a light switch at 3am is not going
 * to remember that they rebooted three days ago and need to open the app
 * once to arm it again.
 *
 * Reads the preference straight out of Flutter's SharedPreferences file
 * rather than starting the engine to ask: the Dart side writes
 * `stayAlive.enabled`, and shared_preferences prefixes its keys with
 * `flutter.`. Defaults to on, matching the Dart side — the two must agree
 * or the service state depends on which one happened to run first.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> {
                if (!enabled(context)) return
                StayAliveService.start(context, "Keeping your switches ready")
            }
        }
    }

    private fun enabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return prefs.getBoolean("flutter.stayAlive.enabled", true)
    }
}
