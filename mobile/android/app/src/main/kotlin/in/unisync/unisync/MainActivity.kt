package `in`.unisync.unisync

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Thin host for the shared engine. All platform-channel logic lives in
 * [WifiBridge], registered on the ENGINE by [EngineHolder] — so it works
 * identically whether or not a screen is attached. This Activity only
 * lends itself to the bridge while visible, for the calls that genuinely
 * need a screen (dialogs, settings panels).
 */
class MainActivity : FlutterActivity() {
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
        // ensure() has already registered the bridge; a launch that came
        // through a cached engine created before this build's code would
        // miss it, so registering here too is a harmless belt-and-braces.
        WifiBridge.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        WifiBridge.activity = this
    }

    override fun onResume() {
        super.onResume()
        WifiBridge.activity = this
    }

    /**
     * Deliberately does *not* touch the Wi-Fi binding: the engine outlives
     * this Activity, and the transport coordinator owns bind/release.
     */
    override fun onDestroy() {
        if (WifiBridge.activity === this) WifiBridge.activity = null
        super.onDestroy()
    }
}
