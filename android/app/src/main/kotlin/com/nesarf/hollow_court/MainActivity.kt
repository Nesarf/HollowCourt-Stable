package com.nesarf.hollow_court

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of `openInBrowser`, and of the camera permission.
 *
 * **Dart cannot start an activity, so this is the one place a platform seam is unavoidable** — and it is
 * answered with the framework's own `MethodChannel` rather than with a package. The Kotlin is deliberately
 * short: it takes a URL, hands it to whichever browser the reader has chosen, and reports whether Android
 * agreed to do so.
 *
 * The scheme check is repeated here even though Dart performs it, because this is the side that can actually
 * start an intent: a method channel is reachable from anywhere in the application, and an `ACTION_VIEW` with a
 * hostile URI is a capability rather than a mistake.
 *
 * **The permission seam is here for a reason that is worth recording.** `permission_handler` was the obvious
 * answer, it was added, and the Android build refused it: `permission_handler_android` requires a compileSdk of
 * 37 while this project builds against 36, and the Android Gradle plugin in use recommends 36 as its maximum.
 * Upgrading the whole toolchain to ask one question is a poor trade, and this file is the alternative — twenty
 * lines against `ActivityCompat`, which the Android framework already provides.
 */
class MainActivity : FlutterActivity() {
    /** The reply to a request that is waiting on the reader, answered from `onRequestPermissionsResult`. */
    private var pendingPermission: MethodChannel.Result? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nesarf.hollow_court/camera_permission")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                requestCameraPermission(result)
            }
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        // **One request at a time, and the second caller is told no rather than left hanging.** A `Result` may be
        // answered exactly once; holding two and answering both with one dialog's outcome would reply to a caller
        // that never saw a prompt.
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private companion object {
        const val CAMERA_REQUEST = 4711
    }
}
