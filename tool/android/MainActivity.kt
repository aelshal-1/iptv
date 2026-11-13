package com.aelshal.iptv_player

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Flutter activity with system Picture in Picture for the video player ("iptv/pip" channel). */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoPip = false
    private var ratio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iptv/pip")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supported())
                "setAuto" -> {
                    autoPip = call.argument<Boolean>("enabled") == true
                    val w = call.argument<Int>("w") ?: 16
                    val h = call.argument<Int>("h") ?: 9
                    ratio = clamp(w, h)
                    update()
                    result.success(null)
                }
                "enter" -> result.success(enter())
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    private fun supported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun clamp(w: Int, h: Int): Rational {
        if (w <= 0 || h <= 0) return Rational(16, 9)
        val r = w.toDouble() / h
        return when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val b = PictureInPictureParams.Builder().setAspectRatio(ratio)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                b.setAutoEnterEnabled(autoPip)
                b.setSeamlessResizeEnabled(true)
            }
            return b.build()
        }
        return null
    }

    private fun update() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && supported()) {
            try {
                val p = params() ?: return
                setPictureInPictureParams(p)
            } catch (_: Exception) {
            }
        }
    }

    private fun enter(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && supported()) {
            return try {
                val p = params() ?: return false
                enterPictureInPictureMode(p)
            } catch (_: Exception) {
                false
            }
        }
        return false
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    override fun onStop() {
        super.onStop()
        channel?.invokeMethod("stopped", null)
    }
}
