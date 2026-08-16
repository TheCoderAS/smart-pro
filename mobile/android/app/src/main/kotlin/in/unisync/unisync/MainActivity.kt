package `in`.unisync.unisync

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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

    /** The network the whole process is currently bound to, if any. */
    private var boundNetwork: Network? = null
    private var lossWatcher: ConnectivityManager.NetworkCallback? = null

    /**
     * Clears the process binding the moment the bound network dies.
     *
     * Nothing did this before, and it was the worst failure in the app:
     * bindProcessToNetwork pins every socket in the process to one
     * network, and when the master's AP vanished -- power cycle, out of
     * range -- the binding stayed. Every request from then on failed with
     * "Machine is not on the network" (errno 64), heartbeats and relay
     * commands timing out forever, even after the phone was back on a
     * perfectly good network. Recovery required killing the app.
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

    /**
     * Use the shared engine rather than building a throwaway one, so the
     * Dart isolate — and the Bluetooth link living inside it — survives
     * this Activity being destroyed.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        EngineHolder.ensure(context)

    /**
     * Never destroy it with the Activity. This is the line that makes a
     * swipe from recents survivable; without it the cache holds an engine
     * that has already been torn down.
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

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
                    // applicationContext, not the Activity: the engine
                    // outlives this Activity now, so Dart can still call
                    // here after it has been destroyed.
                    StayAliveService.start(
                        applicationContext,
                        call.argument<String>("text") ?: "Keeping your switches ready",
                    )
                    result.success(true)
                }
                "stopStayAlive" -> {
                    StayAliveService.stop(applicationContext)
                    result.success(true)
                }
                "requestBatteryExemption" -> {
                    result.success(requestBatteryExemption())
                }
                "isBatteryExempt" -> result.success(isBatteryExempt())
                "openBatterySettings" -> {
                    // Several vendors kill foreground services regardless of
                    // what Android says. Only the user can exempt the app,
                    // and only in their own settings.
                    result.success(openBatterySettings())
                }
                "bindToWifi" -> result.success(bindToCurrentWifi())
                "isBluetoothOn" -> result.success(isBluetoothOn())
                "requestEnableBluetooth" -> result.success(requestEnableBluetooth())
                "isWifiOn" -> result.success(isWifiOn())
                "requestEnableWifi" -> result.success(requestEnableWifi())
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
                    boundNetwork = network
                    watchBoundNetwork(cm)
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
            val ok = cm.bindProcessToNetwork(n)
            if (ok) {
                boundNetwork = n
                watchBoundNetwork(cm)
            }
            return ok
        }
        // No Wi-Fi at all. Clear any stale binding rather than keeping the
        // process pinned to a network that is gone -- a held corpse routes
        // every socket to errno 64 until something lets go.
        cm.bindProcessToNetwork(null)
        boundNetwork = null
        return false
    }

    private fun isBluetoothOn(): Boolean {
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter?.isEnabled == true
    }

    /**
     * The system "turn on Bluetooth?" dialog. Needs BLUETOOTH_CONNECT on
     * API 31+ — the Dart side requests the permission batch first, and a
     * refusal here just means no dialog, never a crash.
     */
    private fun requestEnableBluetooth(): Boolean {
        return try {
            startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isWifiOn(): Boolean {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        return wm.isWifiEnabled
    }

    /**
     * API 29+ apps cannot flip Wi-Fi themselves; the Settings panel is the
     * sanctioned prompt (slides up over the app, one tap to enable).
     * Below 29 the app may still enable it directly.
     */
    private fun requestEnableWifi(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startActivity(Intent(Settings.Panel.ACTION_WIFI))
            } else {
                @Suppress("DEPRECATION")
                run {
                    val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    wm.isWifiEnabled = true
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** True when the system has already agreed not to doze us. */
    private fun isBatteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Asks the system directly for a battery exemption — one dialog rather
     * than a trip through Settings. A foreground service alone does not stop
     * Doze from throttling the process, and for a switch someone reaches for
     * at night that throttling is the difference between instant and not.
     */
    private fun requestBatteryExemption(): Boolean {
        if (isBatteryExempt()) return true
        return try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
            true
        } catch (_: Exception) {
            // Some builds refuse the direct request; the settings screen
            // route still works.
            openBatterySettings()
        }
    }

    /** Sends the user to the battery-optimisation screen, best effort. */
    private fun openBatterySettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
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
        boundNetwork = null
    }

    private fun currentSsid(): String? {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val ssid = wm.connectionInfo?.ssid ?: return null
        if (ssid == WifiManager.UNKNOWN_SSID || ssid == "<unknown ssid>") return null
        return ssid.removePrefix("\"").removeSuffix("\"").ifEmpty { null }
    }

    /**
     * Deliberately does *not* release the Wi-Fi binding.
     *
     * It used to, back when this Activity dying meant the whole app died
     * with it. Now the engine outlives the Activity, so tearing the
     * binding down here would route the still-running app back to mobile
     * data the moment it was swiped away — every request to the master
     * failing in the background exactly as if the hardware were dead.
     *
     * The coordinator binds and releases explicitly when the transport
     * changes, which is the only place that decision belongs.
     */
    override fun onDestroy() {
        super.onDestroy()
    }
}
