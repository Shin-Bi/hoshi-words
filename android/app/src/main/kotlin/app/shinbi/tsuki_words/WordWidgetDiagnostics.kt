package app.shinbi.tsuki_words

import android.app.KeyguardManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.UserManager

/** Read-only health information for the two AppWidget provider components. */
internal object WordWidgetDiagnostics {
    fun status(context: Context): Map<String, Any> {
        val packageManager = context.packageManager
        val lockscreenComponent =
            ComponentName(context, StarlightWordWidgetProvider::class.java)
        val homeComponent =
            ComponentName(context, StarlightHomeWordWidgetProvider::class.java)
        val lockscreenInfo = packageManager.receiverInfoOrNull(lockscreenComponent)
        val homeInfo = packageManager.receiverInfoOrNull(homeComponent)
        val widgetManager = AppWidgetManager.getInstance(context)
        val lockscreenWidgetIds = widgetManager.getAppWidgetIds(lockscreenComponent)
        val homeWidgetIds = widgetManager.getAppWidgetIds(homeComponent)
        val widgetIds = lockscreenWidgetIds + homeWidgetIds
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        val userManager = context.getSystemService(UserManager::class.java)

        return mapOf(
            "schemaVersion" to 2,
            "checkedAtMillis" to System.currentTimeMillis(),
            "requiredPermissions" to emptyList<String>(),
            "missingPermissions" to emptyList<String>(),
            // Legacy aliases remain for platform-map compatibility.
            "widgetProviderDeclared" to (lockscreenInfo != null),
            "widgetProviderEnabled" to lockscreenInfo.isComponentEnabled(
                packageManager,
                lockscreenComponent,
            ),
            "lockscreenWidgetProviderDeclared" to (lockscreenInfo != null),
            "lockscreenWidgetProviderEnabled" to lockscreenInfo.isComponentEnabled(
                packageManager,
                lockscreenComponent,
            ),
            "homeWidgetProviderDeclared" to (homeInfo != null),
            "homeWidgetProviderEnabled" to homeInfo.isComponentEnabled(
                packageManager,
                homeComponent,
            ),
            // This is launch delegation, not a runtime or manifest permission.
            "backgroundLaunchOptIn" to (Build.VERSION.SDK_INT < 34 || creatorBalDelegated()),
            "creatorBalMode" to if (Build.VERSION.SDK_INT < 34) "not_required" else "allowed",
            "senderBalMode" to "host_controlled",
            "deviceLocked" to (keyguard?.isDeviceLocked == true),
            "deviceSecure" to (keyguard?.isDeviceSecure == true),
            "keyguardLocked" to (keyguard?.isKeyguardLocked == true),
            "keyguardSecure" to (keyguard?.isKeyguardSecure == true),
            "userUnlocked" to (userManager?.isUserUnlocked != false),
            "showWhenLockedRequested" to false,
            "turnScreenOnRequested" to false,
            "detailsOpenAfterUnlock" to true,
            "deviceProtectedDeckAvailable" to
                LiveWallpaperPreferences.read(context).deck.isNotEmpty(),
            "widgetCount" to widgetIds.size,
            "lockscreenWidgetCount" to lockscreenWidgetIds.size,
            "homeWidgetCount" to homeWidgetIds.size,
            "widgetHostCategories" to widgetIds.map { id ->
                widgetManager.getAppWidgetOptions(id)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, -1)
            },
            "widgetInstances" to (
                lockscreenWidgetIds.map { id ->
                    widgetInstanceStatus(widgetManager, id, "lockscreen")
                } + homeWidgetIds.map { id ->
                    widgetInstanceStatus(widgetManager, id, "home")
                }
                ),
            "hostPolicyVerifiable" to false,
            "limitations" to listOf(
                "lockscreen_widget_activity_deferred_until_unlock",
                "widget_host_category_not_authoritative_on_one_ui",
            ),
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
        )
    }

    /** Kept separate so the source contract can pin the target-35 opt-in. */
    private fun creatorBalDelegated(): Boolean = true

    private fun widgetInstanceStatus(
        manager: AppWidgetManager,
        appWidgetId: Int,
        componentMode: String,
    ): Map<String, Any> {
        val options = manager.getAppWidgetOptions(appWidgetId)
        return mapOf(
            "appWidgetId" to appWidgetId,
            "componentMode" to componentMode,
            "detailRoute" to "app_full_details_after_unlock",
            "reportedHostCategory" to options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY,
                -1,
            ),
            "minWidthDp" to options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            "minHeightDp" to options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
        )
    }

    private fun <T : android.content.pm.ComponentInfo> T?.isComponentEnabled(
        packageManager: PackageManager,
        component: ComponentName,
    ): Boolean {
        this ?: return false
        return when (packageManager.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED,
            -> false
            else -> enabled && applicationInfo.enabled
        }
    }

    @Suppress("DEPRECATION")
    private fun PackageManager.receiverInfoOrNull(
        component: ComponentName,
    ): android.content.pm.ActivityInfo? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getReceiverInfo(component, PackageManager.ComponentInfoFlags.of(0))
        } else {
            getReceiverInfo(component, 0)
        }
    }.getOrNull()
}
