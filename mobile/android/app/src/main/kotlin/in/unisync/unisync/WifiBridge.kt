package `in`.unisync.unisync

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The `in.unisync.unisync/wifi` platform channel, registered on the
 * ENGINE rather than the Activity.
 *
 * It used to live in MainActivity.configureFlutterEngine, which meant the
 * channel only existed while a screen was attached. The whole design of
 * this app is that the engine outlives the screen (EngineHolder + the
 * keep-ready service) — and in exactly that background state every Wi-Fi
 * call died with MissingPluginException: no re-pinning after missed
 * heartbeats, no release on transport flips, no notification updates.
 * The background self-healing was wired to a bridge that was not there.
 *
 * Context-only operations (bind, release, radio/status reads, the
 * foreground service) use the application context and work always.
 * Screen operations (dialogs, settings panels) prefer the live Activity
 * and fall back to a NEW_TASK launch from the app context; if even that
 * fails they report false rather than throwing.
 */
object WifiBridge {
    private const val CHANNEL = "in.unisync.unisync/wifi"

    private var registered = false
    private lateinit var appContext: Context

    /** The visible screen, when there is one. */
    @Volatile
    var activity: Activity? = null

    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    /** The network the whole process is currently bound to, if any. */
    private var boundNetwork: Network? = null
    private var lossWatcher: ConnectivityManager.NetworkCallback? = null

    @Synchronized
    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        if (registered) return
        registered = true
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
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
                        appContext,
                        call.argument<String>("text") ?: "Keeping your switches ready",
                    )
                    result.success(true)
                }
                "stopStayAlive" -> {
                    StayAliveService.stop(appContext)
                    result.success(true)
                }
                "requestBatteryExemption" -> result.success(requestBatteryExemption())
                "isBatteryExempt" -> result.success(isBatteryExempt())
                "openBatterySettings" -> result.success(openBatterySettings())
                "bindToWifi" -> result.success(bindToCurrentWifi())
                "isBluetoothOn" -> result.success(isBluetoothOn())
                "requestEnableBluetooth" ->
                    result.success(launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)))
                "isWifiOn" -> result.success(isWifiOn())
                "requestEnableWifi" -> result.success(requestEnableWifi())
                "isLocationOn" -> result.success(isLocationOn())
                "openWifiSettings" -> result.success(openWifiSettings())
                "openLocationSettings" ->
                    result.success(launch(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)))
                "release" -> {
                    releaseJoin()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Screen launches prefer the live Activity; with none, a NEW_TASK
     * launch from the app context. False, never a throw, when both fail.
     */
    private fun launch(intent: Intent): Boolean {
        return try {
            val a = activity
            if (a != null) {
                a.startActivity(intent)
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Clears the process binding the moment the bound network dies.
     * bindProcessToNetwork pins every socket in the process to one
     * network; a binding held past the network's death fails everything
     * with errno 64 until something lets go.
     */
    private fun watchBoundNetwork(cm: ConnectivityManager) {
        if (lossWatcher != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onLost(network: Network) {
                if (network == boundNetwork) {
                    cm.bindProcessToNetwork(null)
                    boundNetwork = null
                }
            }
        }
        cm.registerNetworkCallback(
            NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build(),
            cb,
        )
        lossWatcher = cb
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
            val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            releaseJoin()
            var answered = false
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // Route this app's traffic to the AP even though it
                    // has no internet.
                    cm.bindProcessToNetwork(network)
                    boundNetwork = network
                    watchBoundNetwork(cm)
                    if (!answered) {
                        answered = true
                        Handler(Looper.getMainLooper()).post { result.success(true) }
                    }
                }

                override fun onUnavailable() {
                    if (!answered) {
                        answered = true
                        Handler(Looper.getMainLooper()).post { result.success(false) }
                    }
                }
            }
            joinCallback = callback
            cm.requestNetwork(request, callback, 30_000)
        } else {
            // Legacy path for API 24-28.
            @Suppress("DEPRECATION")
            run {
                val wm = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
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
     * Deliberately does NOT require internet — the master's AP has none,
     * and Android silently routing app traffic back to mobile data is the
     * single most likely field failure of the whole flow.
     */
    private fun bindToCurrentWifi(): Boolean {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            val ok = cm.bindProcessToNetwork(n)
            if (ok) {
                boundNetwork = n
                watchBoundNetwork(cm)
            }
            return ok
        }
        // No Wi-Fi at all: clear any stale binding rather than keeping the
        // process pinned to a network that is gone.
        cm.bindProcessToNetwork(null)
        boundNetwork = null
        return false
    }

    private fun isBluetoothOn(): Boolean {
        val bm = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter?.isEnabled == true
    }

    private fun isWifiOn(): Boolean {
        val wm = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        return wm.isWifiEnabled
    }

    /**
     * API 29+ apps cannot flip Wi-Fi themselves; the Settings panel is
     * the sanctioned prompt. Below 29 the app may enable it directly.
     */
    private fun requestEnableWifi(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            launch(Intent(Settings.Panel.ACTION_WIFI))
        } else {
            try {
                @Suppress("DEPRECATION")
                run {
                    val wm = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    wm.isWifiEnabled = true
                }
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /** The phone's own Wi-Fi picker (panel on 29+, settings before). */
    private fun openWifiSettings(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            launch(Intent(Settings.Panel.ACTION_WIFI))
        } else {
            launch(Intent(Settings.ACTION_WIFI_SETTINGS))
        }
    }

    /**
     * Android ties Wi-Fi scanning to the Location service: with it off,
     * scans — including the system's own network dialogs — silently see
     * nothing.
     */
    private fun isLocationOn(): Boolean {
        return try {
            val lm = appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                lm.isLocationEnabled
            } else {
                @Suppress("DEPRECATION")
                (lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))
            }
        } catch (_: Exception) {
            true // unknown must not trigger a prompt
        }
    }

    /** True when the system has already agreed not to doze us. */
    private fun isBatteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(appContext.packageName)
    }

    private fun requestBatteryExemption(): Boolean {
        if (isBatteryExempt()) return true
        val direct = launch(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${appContext.packageName}")),
        )
        return direct || openBatterySettings()
    }

    private fun openBatterySettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${appContext.packageName}")),
        )
        for (i in intents) {
            if (launch(i)) return true
        }
        return false
    }

    private fun releaseJoin() {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        joinCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // already unregistered
            }
        }
        joinCallback = null
        cm.bindProcessToNetwork(null)
        boundNetwork = null
    }

    private fun currentSsid(): String? {
        val wm = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val ssid = wm.connectionInfo?.ssid ?: return null
        if (ssid == WifiManager.UNKNOWN_SSID || ssid == "<unknown ssid>") return null
        return ssid.removePrefix("\"").removeSuffix("\"").ifEmpty { null }
    }
}
