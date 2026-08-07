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
