package `in`.unisync.unisync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi join/read platform channel. Exists because wifi_iot's Android
 * build is incompatible with modern AGP (jcenter + legacy DSL) and no
 * maintained plugin covers app-scoped AP joining.
 *
 * join: API 29+ uses WifiNetworkSpecifier + requestNetwork, which is
 * app-scoped (exactly right for an internet-less device AP) and the
 * network is bound to the process so all sockets route to it —
 * replacing wifi_iot's forceWifiUsage. API 24-28 falls back to the
 * legacy WifiManager path.
 */
class MainActivity : FlutterActivity() {
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "in.unisync.unisync/wifi",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "join" -> {
                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")
                    if (ssid == null || password == null) {
                        result.error("args", "ssid and password required", null)
                    } else {
                        join(ssid, password, result)
                    }
                }
                "currentSsid" -> result.success(currentSsid())
                "startStayAlive" -> {
                    StayAliveService.start(
                        this,
                        call.argument<String>("text") ?: "Keeping your switches ready",
                    )
                    result.success(true)
                }
                "stopStayAlive" -> {
                    StayAliveService.stop(this)
                    result.success(true)
                }
                "openBatterySettings" -> {
                    // Several vendors kill foreground services regardless of
                    // what Android says. Only the user can exempt the app,
                    // and only in their own settings.
                    result.success(openBatterySettings())
                }
                "bindToWifi" -> result.success(bindToCurrentWifi())
                "release" -> {
                    releaseJoin()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun join(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                // The master's AP has no internet; do not require it.
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            releaseJoin()
            var answered = false
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // Route this app's traffic to the AP even though it
                    // has no internet (the forceWifiUsage replacement).
                    cm.bindProcessToNetwork(network)
                    if (!answered) {
                        answered = true
                        runOnUiThread { result.success(true) }
                    }
                }

                override fun onUnavailable() {
                    if (!answered) {
                        answered = true
                        runOnUiThread { result.success(false) }
                    }
                }
            }
            joinCallback = callback
            cm.requestNetwork(request, callback, 30_000)
        } else {
            // Legacy path for API 24-28.
            @Suppress("DEPRECATION")
            run {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val conf = WifiConfiguration().apply {
                    SSID = "\"" + ssid + "\""
                    preSharedKey = "\"" + password + "\""
                }
                val netId = wm.addNetwork(conf)
                if (netId == -1) {
                    result.success(false)
                    return
                }
                wm.disconnect()
                val enabled = wm.enableNetwork(netId, true)
                wm.reconnect()
                result.success(enabled)
            }
        }
    }

    /**
     * Route this app's traffic to the Wi-Fi the phone is already on.
     *
     * The story's normal setup path is the user joining the master's
     * network from Android's own settings, not through the app. Android
     * sees a network with no internet and silently sends app traffic back
     * to mobile data, so every request to 192.168.4.1 fails in a way that
     * looks like broken hardware. Binding only inside join() covered the
     * app-initiated case and missed the common one.
     *
     * Deliberately does NOT require NET_CAPABILITY_INTERNET: that is the
     * whole point. Callers must release before fetching anything from the
     * internet, because this binding is process-wide.
     */
    private fun bindToCurrentWifi(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val networks = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cm.allNetworks
        } else {
            @Suppress("DEPRECATION")
            cm.allNetworks
        }
        for (n in networks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            return cm.bindProcessToNetwork(n)
        }
        return false
    }

    /** Sends the user to the battery-optimisation screen, best effort. */
    private fun openBatterySettings(): Boolean {
        val intents = listOf(
            Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.parse("package:$packageName")),
        )
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return true
            } catch (_: Exception) {
                // try the next one
            }
        }
        return false
    }

    private fun releaseJoin() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        joinCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // already unregistered
            }
        }
        joinCallback = null
        cm.bindProcessToNetwork(null)
    }

    private fun currentSsid(): String? {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val ssid = wm.connectionInfo?.ssid ?: return null
        if (ssid == WifiManager.UNKNOWN_SSID || ssid == "<unknown ssid>") return null
        return ssid.removePrefix("\"").removeSuffix("\"").ifEmpty { null }
    }

    override fun onDestroy() {
        releaseJoin()
        super.onDestroy()
    }
}
