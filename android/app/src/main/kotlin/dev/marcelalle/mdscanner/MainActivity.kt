package dev.marcelalle.mdscanner

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hérite de [FlutterFragmentActivity] : l'invite biométrique d'AndroidX (plugin local_auth)
 * exige une FragmentActivity.
 *
 * Expose un petit canal vers Dart (voir lib/core/services/platform_bridge.dart) pour trois
 * besoins qui ne justifient pas un plugin : protéger la fenêtre contre les captures d'écran,
 * lire l'état de la permission caméra et ouvrir les réglages système de l'application.
 */
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        setSecure(call.argument<Boolean>("secure") ?: false)
                        result.success(null)
                    }
                    "cameraPermissionStatus" -> result.success(cameraPermissionStatus())
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
    }

    /** Bloque les captures d'écran et masque l'aperçu dans les applications récentes. */
    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    /**
     * "granted", "denied" (jamais demandée ou refusée une fois : le système peut encore afficher
     * la demande) ou "rationale" (refusée, une explication est attendue avant de redemander).
     */
    private fun cameraPermissionStatus(): String {
        val permission = Manifest.permission.CAMERA
        return when {
            ContextCompat.checkSelfPermission(this, permission) ==
                PackageManager.PERMISSION_GRANTED -> "granted"
            ActivityCompat.shouldShowRequestPermissionRationale(this, permission) -> "rationale"
            else -> "denied"
        }
    }

    private fun openAppSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val PLATFORM_CHANNEL = "dev.marcelalle.mdscanner/platform"
    }
}
