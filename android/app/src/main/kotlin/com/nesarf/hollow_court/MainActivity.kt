package com.nesarf.hollow_court

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of `openInBrowser`.
 *
 * **Dart cannot start an activity, so this is the one place a platform seam is unavoidable** — and it is
 * answered with the framework's own `MethodChannel` rather than with a package. The Kotlin is deliberately
 * short: it takes a URL, hands it to whichever browser the reader has chosen, and reports whether Android
 * agreed to do so.
 *
 * The scheme check is repeated here even though Dart performs it, because this is the side that can actually
 * start an intent: a method channel is reachable from anywhere in the application, and an `ACTION_VIEW` with a
 * hostile URI is a capability rather than a mistake.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nesarf.hollow_court/open_url")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.arguments as? String
                if (url == null || !(url.startsWith("https://") || url.startsWith("http://"))) {
                    result.error("bad-argument", "only http and https are opened", null)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    result.success(null)
                } catch (missing: android.content.ActivityNotFoundException) {
                    // A device with no browser at all. The reader is told by the screen, not by a crash.
                    result.error("no-browser", "no activity could open this address", null)
                }
            }
    }
}
