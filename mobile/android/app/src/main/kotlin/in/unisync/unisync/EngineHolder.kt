package `in`.unisync.unisync

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The app's one long-lived FlutterEngine.
 *
 * This is what makes the keep-ready service mean anything. A plain
 * FlutterActivity builds its own engine and destroys it in onDestroy, so
 * swiping the app out of recents tore down the Dart isolate — and with it
 * the session token, every provider, and the Bluetooth link itself, since
 * the GATT connection is held by a Dart plugin. The foreground service
 * kept the *process* alive around an empty shell: reopening the app still
 * re-ran main(), re-probed, re-scanned and re-connected.
 *
 * Cached here instead, the isolate outlives the Activity. Reopening
 * attaches a new Activity to an engine that is already connected, which is
 * the difference between a switch that fires on the first tap and one that
 * fires after a scan.
 *
 * Created by whoever needs it first — the Activity on a normal launch, the
 * service when it comes up after a reboot without anyone opening the app.
 */
object EngineHolder {
    const val ID = "unisync"

    /** The cached engine, building and starting it on first use. */
    @Synchronized
    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        // The constructor registers the generated plugins for us, so the
        // channels main() reaches for are live before it runs.
        val engine = FlutterEngine(context.applicationContext)
        // The wifi bridge is engine-level, not Activity-level: register it
        // BEFORE Dart runs, so a headless start (boot receiver, keep-ready
        // service) has a working channel from the first call. Registering
        // in the Activity was why every background Wi-Fi call died with
        // MissingPluginException.
        WifiBridge.register(
            context.applicationContext,
            engine.dartExecutor.binaryMessenger,
        )
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }
}
