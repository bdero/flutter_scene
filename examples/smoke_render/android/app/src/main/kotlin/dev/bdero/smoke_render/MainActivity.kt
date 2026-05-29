package dev.bdero.smoke_render

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.bdero.smoke_render/android_manifest",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getApplicationMetadataValue") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val name = call.arguments as? String
            if (name == null) {
                result.error("bad-argument", "Expected metadata key string.", null)
                return@setMethodCallHandler
            }

            result.success(applicationMetadataValue(name))
        }
    }

    private fun applicationMetadataValue(name: String): String? {
        val applicationInfo =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(
                    packageName,
                    PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            }
        return applicationInfo.metaData?.get(name)?.toString()
    }
}
