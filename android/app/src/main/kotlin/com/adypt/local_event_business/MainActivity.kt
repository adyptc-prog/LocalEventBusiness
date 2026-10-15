package com.adypt.local_event_business

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cine a instalat aplicația — citit de `InstallActivation` (Dart) la
        // prima pornire, ca să decidă dacă telefonul e activat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "local_event_business/install_source")
            .setMethodCallHandler { call, result ->
                if (call.method == "getInstallSource") {
                    try {
                        result.success(installSource())
                    } catch (e: Exception) {
                        result.error("install_source", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun installSource(): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        return if (sdk >= Build.VERSION_CODES.R) {
            val info = packageManager.getInstallSourceInfo(packageName)
            mapOf(
                "installer" to info.installingPackageName,
                "initiator" to info.initiatingPackageName,
                "sdk" to sdk,
            )
        } else {
            @Suppress("DEPRECATION")
            mapOf(
                "installer" to packageManager.getInstallerPackageName(packageName),
                "initiator" to null,
                "sdk" to sdk,
            )
        }
    }
}
