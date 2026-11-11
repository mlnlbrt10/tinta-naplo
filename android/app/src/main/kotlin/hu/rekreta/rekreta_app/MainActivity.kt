package hu.rekreta.rekreta_app

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "hu.rekreta.rekreta_app/dynamic_icon"
        private const val LEGACY_CHANNEL_NAME = "flutter_dynamic_icon"

        private val ALIAS_MAP = mapOf(
            "icon_normal" to ".MainActivityNormal",
            "normal" to ".MainActivityNormal",
            "default" to ".MainActivityNormal",
            ".MainActivityNormal" to ".MainActivityNormal",
            "MainActivityNormal" to ".MainActivityNormal",
            "icon_oled" to ".MainActivityOled",
            "oled" to ".MainActivityOled",
            "minimal_oled" to ".MainActivityOled",
            ".MainActivityOled" to ".MainActivityOled",
            "MainActivityOled" to ".MainActivityOled",
            "icon_christmas" to ".MainActivityChristmas",
            "christmas" to ".MainActivityChristmas",
            ".MainActivityChristmas" to ".MainActivityChristmas",
            "MainActivityChristmas" to ".MainActivityChristmas",
            "icon_christmas_oled" to ".MainActivityChristmasOled",
            "christmas_oled" to ".MainActivityChristmasOled",
            ".MainActivityChristmasOled" to ".MainActivityChristmasOled",
            "MainActivityChristmasOled" to ".MainActivityChristmasOled"
        )

        private val ALL_ALIASES = listOf(
            ".MainActivityNormal",
            ".MainActivityOled",
            ".MainActivityChristmas",
            ".MainActivityChristmasOled"
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val handler = MethodChannel.MethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_CHANNEL_NAME)
            .setMethodCallHandler(handler)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setAlternateIconName", "setAppIcon" -> {
                val rawName = when (val args = call.arguments) {
                    is Map<*, *> -> (args["iconName"] ?: args["alias"] ?: args["preset"])?.toString()
                    is String -> args
                    else -> null
                } ?: "icon_normal"

                try {
                    val appliedAlias = applyLauncherAlias(rawName)
                    result.success(appliedAlias)
                } catch (e: Exception) {
                    result.error("ICON_SWITCH_FAILED", e.message, null)
                }
            }
            "getAlternateIconName", "getAppIcon" -> {
                result.success(getCurrentEnabledAlias())
            }
            "supportsAlternateIcons" -> {
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyLauncherAlias(requestedKey: String): String {
        val targetAlias = ALIAS_MAP[requestedKey] ?: ".MainActivityNormal"
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName

        for (alias in ALL_ALIASES) {
            val component = ComponentName(pkg, "$pkg$alias")
            val desiredState = if (alias == targetAlias) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val currentState = pm.getComponentEnabledSetting(component)
            val isCurrentlyEnabled = currentState == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (currentState == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && alias == ".MainActivityNormal")
            val shouldBeEnabled = desiredState == PackageManager.COMPONENT_ENABLED_STATE_ENABLED

            if (isCurrentlyEnabled != shouldBeEnabled) {
                pm.setComponentEnabledSetting(
                    component,
                    desiredState,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
        return targetAlias
    }

    private fun getCurrentEnabledAlias(): String {
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName
        for (alias in ALL_ALIASES) {
            val component = ComponentName(pkg, "$pkg$alias")
            val state = pm.getComponentEnabledSetting(component)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias
            }
        }
        return ".MainActivityNormal"
    }
}
