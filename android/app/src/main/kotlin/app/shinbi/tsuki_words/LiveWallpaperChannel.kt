package app.shinbi.tsuki_words

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.WallpaperInfo
import android.app.WallpaperManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Native bridge used to configure and open the system live-wallpaper preview.
 *
 * Wallpaper assignment itself is intentionally left to Android's trusted
 * picker. Samsung firmware may offer Home, Lock, or both targets depending on
 * device/One UI version; the app never assumes that a lock-only target exists.
 */
internal class LiveWallpaperChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "app.shinbi.tsuki_words/live_wallpaper"
        const val ACTION_OPEN_WORD_DETAILS =
            "app.shinbi.tsuki_words.action.OPEN_LIVE_WALLPAPER_WORD"
        const val EXTRA_WORD_ID = "liveWallpaperWordId"
        const val EXTRA_REVEAL_EXAMPLES = "revealWordExamples"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingLaunchDetails: LaunchDetails? = extractLaunchDetails(activity.intent)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncConfig" -> syncConfig(call, result)
            "getStatus" -> result.success(statusMap(activity))
            "openPicker" -> openPicker(result)
            "getWidgetStatus" -> result.success(widgetStatusMap(activity))
            "openWidgetPicker" -> openWidgetPicker(result)
            "openExactAlarmSettings" -> openExactAlarmSettings(result)
            "drainPendingActions", "drainActions" ->
                result.success(LiveWallpaperPreferences.pendingActions(activity))
            "ackPendingActions", "ackActions" -> ackPendingActions(call, result)
            "consumeLaunchWordId" -> {
                val launchDetails = pendingLaunchDetails
                pendingLaunchDetails = null
                activity.intent?.removeExtra(EXTRA_WORD_ID)
                activity.intent?.removeExtra(EXTRA_REVEAL_EXAMPLES)
                result.success(launchDetails?.toMap())
            }
            else -> result.notImplemented()
        }
    }

    fun handleIntent(intent: Intent) {
        val launchDetails = extractLaunchDetails(intent) ?: return
        pendingLaunchDetails = launchDetails
    }

    private fun extractLaunchDetails(intent: Intent?): LaunchDetails? {
        if (intent?.action != ACTION_OPEN_WORD_DETAILS) return null
        val wordId = intent.getStringExtra(EXTRA_WORD_ID)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        return LaunchDetails(
            wordId = wordId,
            revealExamples = intent.getBooleanExtra(EXTRA_REVEAL_EXAMPLES, false),
        )
    }

    private data class LaunchDetails(
        val wordId: String,
        val revealExamples: Boolean,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "wordId" to wordId,
            "revealExamples" to revealExamples,
        )
    }

    private fun ackPendingActions(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val actionIds = (arguments["actionIds"] as? List<*>)
            ?.mapNotNull { it?.toString()?.takeIf(String::isNotBlank) }
            .orEmpty()
        if (LiveWallpaperPreferences.ackPendingActions(activity, actionIds.toSet())) {
            result.success(null)
        } else {
            result.error("wallpaper_ack_failed", "배경화면 동작을 확인 처리하지 못했습니다.", null)
        }
    }

    private fun syncConfig(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val preferences = LiveWallpaperPreferences.preferences(activity)
        val editor = preferences.edit()

        (arguments[LiveWallpaperPreferences.KEY_ENABLED] as? Boolean)?.let {
            editor.putBoolean(LiveWallpaperPreferences.KEY_ENABLED, it)
        }
        (arguments[LiveWallpaperPreferences.KEY_SHOW_READING] as? Boolean)?.let {
            editor.putBoolean(LiveWallpaperPreferences.KEY_SHOW_READING, it)
        }
        (arguments[LiveWallpaperPreferences.KEY_SHOW_MEANING] as? Boolean)?.let {
            editor.putBoolean(LiveWallpaperPreferences.KEY_SHOW_MEANING, it)
        }
        (arguments[LiveWallpaperPreferences.KEY_EXCLUDE_KNOWN] as? Boolean)?.let {
            editor.putBoolean(LiveWallpaperPreferences.KEY_EXCLUDE_KNOWN, it)
        }
        (arguments[LiveWallpaperPreferences.KEY_INTERVAL_MINUTES] as? Number)?.let {
            editor.putInt(
                LiveWallpaperPreferences.KEY_INTERVAL_MINUTES,
                it.toInt().coerceIn(
                    LiveWallpaperPreferences.MIN_INTERVAL_MINUTES,
                    LiveWallpaperPreferences.MAX_INTERVAL_MINUTES,
                ),
            )
        }

        if (arguments.containsKey(LiveWallpaperPreferences.KEY_DECK)) {
            val encodedDeck = encodeDeck(arguments[LiveWallpaperPreferences.KEY_DECK])
            editor.putString(LiveWallpaperPreferences.KEY_DECK, encodedDeck.toString())
        }
        if (arguments.containsKey(LiveWallpaperPreferences.KEY_LEVELS)) {
            val levels = encodeLevels(arguments[LiveWallpaperPreferences.KEY_LEVELS])
            editor.putString(LiveWallpaperPreferences.KEY_LEVELS, levels.toString())
        }

        // apply() updates this process' in-memory SharedPreferences immediately;
        // a running WallpaperService receives its registered change callback.
        editor.apply()
        StarlightWordWidgetProvider.updateAll(activity)
        // Flutter's gateway intentionally treats synchronization as a void call.
        result.success(null)
    }

    private fun encodeDeck(value: Any?): JSONArray {
        val result = JSONArray()
        val rawItems = value as? List<*> ?: return result
        rawItems.take(LiveWallpaperPreferences.MAX_DECK_SIZE).forEach { rawItem ->
            val item = rawItem as? Map<*, *> ?: return@forEach
            val word = cleanText(item["word"], LiveWallpaperPreferences.MAX_WORD_LENGTH)
            val id = cleanText(item["id"], LiveWallpaperPreferences.MAX_ID_LENGTH)
            if (id.isEmpty() || word.isEmpty()) return@forEach
            val previewBudget = TextBudget(
                LiveWallpaperPreferences.MAX_PREVIEW_DETAIL_CHARS_PER_WORD,
            )
            val quizAttempts = cleanCount(item["quizAttempts"])
            val quizCorrect = cleanCount(item["quizCorrect"]).coerceAtMost(quizAttempts)
            result.put(
                JSONObject().apply {
                    put("id", id)
                    put("word", word)
                    put(
                        "reading",
                        cleanText(item["reading"], LiveWallpaperPreferences.MAX_READING_LENGTH),
                    )
                    put(
                        "readings",
                        encodeTextList(
                            item["readings"],
                            LiveWallpaperPreferences.MAX_READING_COUNT,
                            LiveWallpaperPreferences.MAX_SINGLE_READING_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "alternativeReadings",
                        encodeTextList(
                            item["alternativeReadings"],
                            LiveWallpaperPreferences.MAX_READING_COUNT,
                            LiveWallpaperPreferences.MAX_SINGLE_READING_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "meaning",
                        cleanText(item["meaning"], LiveWallpaperPreferences.MAX_MEANING_LENGTH),
                    )
                    put(
                        "partOfSpeech",
                        cleanPreviewText(
                            item["partOfSpeech"],
                            LiveWallpaperPreferences.MAX_PART_OF_SPEECH_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "conjugationClass",
                        cleanPreviewText(
                            item["conjugationClass"],
                            LiveWallpaperPreferences.MAX_CONJUGATION_CLASS_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "meanings",
                        encodeTextList(
                            item["meanings"],
                            LiveWallpaperPreferences.MAX_MEANING_COUNT,
                            LiveWallpaperPreferences.MAX_PREVIEW_MEANING_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "usageNotes",
                        encodeTextList(
                            item["usageNotes"],
                            LiveWallpaperPreferences.MAX_USAGE_NOTE_COUNT,
                            LiveWallpaperPreferences.MAX_USAGE_NOTE_LENGTH,
                            previewBudget,
                        ),
                    )
                    put(
                        "note",
                        cleanPreviewText(
                            item["note"],
                            LiveWallpaperPreferences.MAX_WORD_NOTE_LENGTH,
                            previewBudget,
                        ),
                    )
                    put("quizAttempts", quizAttempts)
                    put("quizCorrect", quizCorrect)
                    put("forms", encodeForms(item["forms"], previewBudget))
                    put("examples", encodeExamples(item["examples"], previewBudget))
                    put(
                        "example",
                        cleanText(item["example"], LiveWallpaperPreferences.MAX_EXAMPLE_LENGTH),
                    )
                    put(
                        "exampleMeaning",
                        cleanText(
                            item["exampleMeaning"],
                            LiveWallpaperPreferences.MAX_EXAMPLE_MEANING_LENGTH,
                        ),
                    )
                    put("level", cleanLevel(item["level"]))
                    put(
                        "bookmark",
                        item["bookmark"] as? Boolean
                            ?: item["bookmarked"] as? Boolean
                            ?: false,
                    )
                    put(
                        "known",
                        item["known"] as? Boolean
                            ?: item["isKnown"] as? Boolean
                            ?: false,
                    )
                },
            )
        }
        return result
    }

    private fun encodeLevels(value: Any?): JSONArray {
        val result = JSONArray()
        val seen = mutableSetOf<String>()
        (value as? List<*>)?.forEach { rawLevel ->
            val level = cleanLevel(rawLevel)
            if (level.isNotEmpty() && seen.add(level)) result.put(level)
        }
        return result
    }

    private fun cleanLevel(value: Any?): String {
        val normalized = value?.toString()?.trim()?.lowercase().orEmpty()
        return if (normalized.matches(Regex("n[1-5]"))) normalized else ""
    }

    private fun cleanText(value: Any?, maxLength: Int): String =
        value?.toString()?.trim()?.take(maxLength).orEmpty()

    private class TextBudget(var remaining: Int)

    private fun cleanPreviewText(value: Any?, maxLength: Int, budget: TextBudget): String {
        if (budget.remaining <= 0) return ""
        val result = cleanText(value, minOf(maxLength, budget.remaining))
        budget.remaining -= result.length
        return result
    }

    private fun encodeTextList(
        value: Any?,
        maxItems: Int,
        maxLength: Int,
        budget: TextBudget,
    ): JSONArray = JSONArray().apply {
        (value as? List<*>)?.take(maxItems)?.forEach { rawText ->
            val cleaned = cleanPreviewText(rawText, maxLength, budget)
            if (cleaned.isNotEmpty()) put(cleaned)
        }
    }

    private fun encodeForms(value: Any?, budget: TextBudget): JSONArray = JSONArray().apply {
        (value as? List<*>)
            ?.take(LiveWallpaperPreferences.MAX_FORM_COUNT)
            ?.forEach { rawForm ->
                val form = rawForm as? Map<*, *> ?: return@forEach
                val surface = cleanPreviewText(
                    form["surface"],
                    LiveWallpaperPreferences.MAX_FORM_SURFACE_LENGTH,
                    budget,
                )
                if (surface.isEmpty()) return@forEach
                put(
                    JSONObject().apply {
                        put(
                            "label",
                            cleanPreviewText(
                                form["label"],
                                LiveWallpaperPreferences.MAX_FORM_LABEL_LENGTH,
                                budget,
                            ),
                        )
                        put("surface", surface)
                        put(
                            "reading",
                            cleanPreviewText(
                                form["reading"],
                                LiveWallpaperPreferences.MAX_FORM_READING_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "note",
                            cleanPreviewText(
                                form["note"],
                                LiveWallpaperPreferences.MAX_FORM_NOTE_LENGTH,
                                budget,
                            ),
                        )
                    },
                )
            }
    }

    private fun encodeExamples(value: Any?, budget: TextBudget): JSONArray = JSONArray().apply {
        (value as? List<*>)
            ?.take(LiveWallpaperPreferences.MAX_PREVIEW_EXAMPLE_COUNT)
            ?.forEach { rawExample ->
                val example = rawExample as? Map<*, *> ?: return@forEach
                val original = cleanPreviewText(
                    example["original"],
                    LiveWallpaperPreferences.MAX_PREVIEW_EXAMPLE_ORIGINAL_LENGTH,
                    budget,
                )
                if (original.isEmpty()) return@forEach
                put(
                    JSONObject().apply {
                        put("original", original)
                        put(
                            "ruby",
                            cleanPreviewText(
                                example["ruby"],
                                LiveWallpaperPreferences.MAX_PREVIEW_EXAMPLE_RUBY_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "literalTranslation",
                            cleanPreviewText(
                                example["literalTranslation"],
                                LiveWallpaperPreferences.MAX_PREVIEW_TRANSLATION_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "naturalTranslation",
                            cleanPreviewText(
                                example["naturalTranslation"],
                                LiveWallpaperPreferences.MAX_PREVIEW_TRANSLATION_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "focusSurface",
                            cleanPreviewText(
                                example["focusSurface"],
                                LiveWallpaperPreferences.MAX_EXAMPLE_FOCUS_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "formKind",
                            cleanPreviewText(
                                example["formKind"],
                                LiveWallpaperPreferences.MAX_EXAMPLE_FORM_KIND_LENGTH,
                                budget,
                            ),
                        )
                        put(
                            "note",
                            cleanPreviewText(
                                example["note"],
                                LiveWallpaperPreferences.MAX_EXAMPLE_NOTE_LENGTH,
                                budget,
                            ),
                        )
                    },
                )
            }
    }

    private fun cleanCount(value: Any?): Int = when (value) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull() ?: 0
        else -> 0
    }.coerceIn(0, LiveWallpaperPreferences.MAX_QUIZ_COUNT)

    private fun openPicker(result: MethodChannel.Result) {
        val status = statusMap(activity)
        if (status["isSupported"] != true || status["isSetAllowed"] != true) {
            result.error(
                "live_wallpaper_unavailable",
                "이 기기에서는 라이브 배경화면을 설정할 수 없습니다.",
                status,
            )
            return
        }

        val component = ComponentName(activity, StarlightWordWallpaperService::class.java)
        val directPreview = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
        }
        val genericPicker = Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)

        try {
            activity.startActivity(directPreview)
            result.success(null)
        } catch (_: RuntimeException) {
            try {
                activity.startActivity(genericPicker)
                result.success(null)
            } catch (error: RuntimeException) {
                result.error(
                    "live_wallpaper_picker_unavailable",
                    "시스템 라이브 배경화면 선택 화면을 열 수 없습니다.",
                    error.javaClass.simpleName,
                )
            }
        }
    }

    private fun openWidgetPicker(result: MethodChannel.Result) {
        val before = widgetStatusMap(activity)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || before["pinRequestSupported"] != true) {
            result.success(
                before + mapOf(
                    "pinRequestLaunched" to false,
                    "message" to
                        "이 홈 화면은 앱에서 위젯 추가 창을 열 수 없어요. 홈 화면을 길게 눌러 위젯 목록에서 ‘별빛 단어 · 홈 화면’을 추가해 주세요.",
                ),
            )
            return
        }

        val manager = AppWidgetManager.getInstance(activity)
        // Android's pin API targets the launcher, so it must request the home
        // component. LockStar users add the separately labelled lock component
        // from Good Lock and existing legacy bindings remain untouched.
        val provider = ComponentName(activity, StarlightHomeWordWidgetProvider::class.java)
        val successCallback = PendingIntent.getBroadcast(
            activity,
            31_702,
            Intent(activity, StarlightHomeWordWidgetProvider::class.java).apply {
                action = StarlightWordWidgetProvider.ACTION_PINNED
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val accepted = runCatching {
            manager.requestPinAppWidget(provider, null, successCallback)
        }.getOrDefault(false)
        result.success(
            widgetStatusMap(activity) + mapOf(
                // Android returns whether the launcher accepted the request,
                // not whether the user ultimately placed the widget.
                "pinRequestLaunched" to accepted,
                "message" to if (accepted) {
                    "시스템 위젯 추가 창에서 ‘별빛 단어 · 홈 화면’의 위치를 선택해 주세요. 잠금화면은 LockStar에서 ‘별빛 단어 · 잠금화면’을 선택해 주세요."
                } else {
                    "홈 화면을 길게 눌러 위젯 목록에서 ‘별빛 단어 · 홈 화면’을 추가해 주세요."
                },
            ),
        )
    }

    private fun openExactAlarmSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(
                mapOf(
                    "opened" to false,
                    "message" to "이 Android 버전에서는 별도의 알람 및 리마인더 설정이 필요하지 않아요.",
                ),
            )
            return
        }
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        try {
            activity.startActivity(intent)
            result.success(mapOf("opened" to true))
        } catch (error: RuntimeException) {
            result.success(
                mapOf(
                    "opened" to false,
                    "message" to "시스템의 알람 및 리마인더 설정을 열 수 없어요.",
                    "reason" to error.javaClass.simpleName,
                ),
            )
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun statusMap(context: Context): Map<String, Any> {
        val manager = WallpaperManager.getInstance(context)
        val isSupported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            runCatching { manager.isWallpaperSupported }.getOrDefault(false)
        } else {
            true
        }
        val isSetAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            runCatching { manager.isSetWallpaperAllowed }.getOrDefault(false)
        } else {
            true
        }
        val expectedComponent = ComponentName(context, StarlightWordWallpaperService::class.java)
        val isActive = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                listOf(WallpaperManager.FLAG_SYSTEM, WallpaperManager.FLAG_LOCK).any { target ->
                    isExpectedWallpaper(manager.getWallpaperInfo(target), expectedComponent)
                }
            } else {
                isExpectedWallpaper(manager.wallpaperInfo, expectedComponent)
            }
        }.getOrDefault(false)
        val config = LiveWallpaperPreferences.read(context)
        val state = when {
            !isSupported || !isSetAllowed -> "unavailable"
            isActive -> "active"
            config.enabled && config.deck.isNotEmpty() -> "ready"
            config.enabled -> "empty"
            else -> "disabled"
        }
        val isSamsung = Build.MANUFACTURER.equals("samsung", ignoreCase = true) ||
            Build.BRAND.equals("samsung", ignoreCase = true)
        val placementMessage = when {
            !isSupported || !isSetAllowed ->
                "이 기기 또는 현재 사용자 설정에서는 라이브 배경화면을 적용할 수 없습니다."
            isActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                "별빛 단어가 홈 화면 또는 잠금화면에 적용되어 있습니다."
            isActive ->
                "별빛 단어가 적용되어 있습니다. Android 버전 제한으로 홈·잠금화면은 따로 확인할 수 없습니다."
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                "이 Android 버전에서는 잠금화면 전용 적용 상태를 자동 확인할 수 없어요. 시스템 배경화면 설정에서 확인해 주세요."
            else ->
                "시스템 미리보기에서 홈 화면·잠금화면 중 기기가 제공하는 적용 대상을 선택해 주세요."
        }
        return mapOf(
            "status" to state,
            "isSupported" to isSupported,
            "supported" to isSupported,
            "isSetAllowed" to isSetAllowed,
            "isActive" to isActive,
            "active" to isActive,
            "isSamsung" to isSamsung,
            "enabled" to config.enabled,
            "configured" to (config.enabled && config.deck.isNotEmpty()),
            "deckSize" to config.deck.size,
            "intervalMinutes" to config.intervalMinutes,
            "showReading" to config.showReading,
            "showMeaning" to config.showMeaning,
            "excludeKnown" to config.excludeKnown,
            "levels" to config.levels,
            "placement" to "system_picker_dependent",
            "message" to placementMessage,
            "pendingActionCount" to LiveWallpaperPreferences.pendingActions(context).size,
            "supportsInteractiveControls" to false,
            "touchDelivery" to "disabled",
            "widgetControlsAvailable" to true,
        ) + widgetStatusMap(context)
    }

    private fun widgetStatusMap(context: Context): Map<String, Any> {
        val manager = AppWidgetManager.getInstance(context)
        val lockscreenComponent =
            ComponentName(context, StarlightWordWidgetProvider::class.java)
        val homeComponent =
            ComponentName(context, StarlightHomeWordWidgetProvider::class.java)
        val lockscreenWidgetIds = manager.getAppWidgetIds(lockscreenComponent)
        val homeWidgetIds = manager.getAppWidgetIds(homeComponent)
        val widgetIds = lockscreenWidgetIds + homeWidgetIds
        val pinSupported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            runCatching { manager.isRequestPinAppWidgetSupported }.getOrDefault(false)
        } else {
            false
        }
        // Some OEMs omit the optional feature flag despite shipping a widget
        // host, so an existing instance or pin support is also sufficient.
        val featureDeclared = context.packageManager.hasSystemFeature(
            "android.software.app_widgets",
        )
        val supported = featureDeclared || pinSupported || widgetIds.isNotEmpty()
        val exactTimerSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        val exactTimerGranted = if (exactTimerSupported) {
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            alarmManager != null && runCatching {
                alarmManager.canScheduleExactAlarms()
            }.getOrDefault(false)
        } else {
            true
        }
        return mapOf(
            "widgetSupported" to supported,
            "widgetPinned" to widgetIds.isNotEmpty(),
            "widgetCount" to widgetIds.size,
            "lockscreenWidgetPinned" to lockscreenWidgetIds.isNotEmpty(),
            "lockscreenWidgetCount" to lockscreenWidgetIds.size,
            "homeWidgetPinned" to homeWidgetIds.isNotEmpty(),
            "homeWidgetCount" to homeWidgetIds.size,
            "pinRequestSupported" to pinSupported,
            "exactTimerSupported" to exactTimerSupported,
            "exactTimerGranted" to exactTimerGranted,
            "canScheduleExactAlarms" to exactTimerGranted,
            "widgetPlacement" to "separate_home_and_lockstar_providers",
            "widgetMessage" to if (widgetIds.isNotEmpty()) {
                "별빛 단어 위젯 ${widgetIds.size}개(홈 ${homeWidgetIds.size}개, 잠금화면 ${lockscreenWidgetIds.size}개)가 추가되어 있어요."
            } else {
                "홈에서는 ‘별빛 단어 · 홈 화면’, LockStar에서는 ‘별빛 단어 · 잠금화면’을 추가해 주세요."
            },
            "lockscreenDiagnostics" to WordWidgetDiagnostics.status(context),
        )
    }

    private fun isExpectedWallpaper(
        wallpaperInfo: WallpaperInfo?,
        expectedComponent: ComponentName,
    ): Boolean = wallpaperInfo?.let {
        ComponentName(it.packageName, it.serviceName) == expectedComponent
    } ?: false
}

internal data class LiveWallpaperConjugationForm(
    val label: String,
    val surface: String,
    val reading: String,
    val note: String,
)

internal data class LiveWallpaperExampleSentence(
    val original: String,
    val ruby: String,
    val literalTranslation: String,
    val naturalTranslation: String,
    val focusSurface: String,
    val formKind: String,
    val note: String,
)

internal data class LiveWallpaperWord(
    val id: String,
    val word: String,
    val reading: String,
    val readings: List<String>,
    val alternativeReadings: List<String>,
    val meaning: String,
    val partOfSpeech: String,
    val conjugationClass: String,
    val meanings: List<String>,
    val usageNotes: List<String>,
    val note: String,
    val quizAttempts: Int,
    val quizCorrect: Int,
    val forms: List<LiveWallpaperConjugationForm>,
    val examples: List<LiveWallpaperExampleSentence>,
    val example: String,
    val exampleMeaning: String,
    val level: String,
    val bookmark: Boolean,
    val known: Boolean,
)

internal data class LiveWallpaperPlayback(
    val wordId: String,
    val deadlineMillis: Long,
    val intervalMinutes: Int,
)

/**
 * A short, device-protected undo window owned by the Android widget.
 *
 * The known state itself is deliberately not committed until this deadline.
 * That keeps a second tap lossless: it can cancel the pending transition
 * without having to race Flutter's acknowledgement of a temporary state.
 */
internal data class WidgetKnownCountdown(
    val wordId: String,
    val deadlineMillis: Long,
)

internal data class LiveWallpaperConfig(
    val enabled: Boolean,
    val intervalMinutes: Int,
    val showReading: Boolean,
    val showMeaning: Boolean,
    val excludeKnown: Boolean,
    val levels: List<String>,
    val deck: List<LiveWallpaperWord>,
)

internal object LiveWallpaperPreferences {
    const val PREFERENCES_NAME = "starlight_live_wallpaper"
    const val KEY_ENABLED = "enabled"
    const val KEY_INTERVAL_MINUTES = "intervalMinutes"
    const val KEY_SHOW_READING = "showReading"
    const val KEY_SHOW_MEANING = "showMeaning"
    const val KEY_EXCLUDE_KNOWN = "excludeKnown"
    const val KEY_LEVELS = "levels"
    const val KEY_DECK = "deck"
    const val KEY_STATE_OVERRIDES = "stateOverrides"
    const val KEY_PENDING_ACTIONS = "pendingActions"
    const val KEY_CURRENT_WORD_ID = "currentWordId"
    const val KEY_DEADLINE_MILLIS = "deadlineMillis"
    const val KEY_PLAYBACK_INTERVAL = "playbackIntervalMinutes"
    const val KEY_WIDGET_KNOWN_WORD_ID = "widgetKnownWordId"
    const val KEY_WIDGET_KNOWN_DEADLINE_MILLIS = "widgetKnownDeadlineMillis"
    const val DEFAULT_INTERVAL_MINUTES = 30
    const val MIN_INTERVAL_MINUTES = 5
    const val MAX_INTERVAL_MINUTES = 24 * 60
    const val MAX_DECK_SIZE = 128
    const val MAX_ID_LENGTH = 100
    const val MAX_WORD_LENGTH = 80
    const val MAX_READING_LENGTH = 160
    const val MAX_READING_COUNT = 8
    const val MAX_SINGLE_READING_LENGTH = 160
    const val MAX_MEANING_LENGTH = 300
    const val MAX_EXAMPLE_LENGTH = 320
    const val MAX_EXAMPLE_MEANING_LENGTH = 320
    const val MAX_PREVIEW_DETAIL_CHARS_PER_WORD = 8 * 1024
    const val MAX_PART_OF_SPEECH_LENGTH = 80
    const val MAX_CONJUGATION_CLASS_LENGTH = 80
    const val MAX_MEANING_COUNT = 12
    const val MAX_PREVIEW_MEANING_LENGTH = 240
    const val MAX_USAGE_NOTE_COUNT = 8
    const val MAX_USAGE_NOTE_LENGTH = 500
    const val MAX_WORD_NOTE_LENGTH = 1_000
    const val MAX_QUIZ_COUNT = 1_000_000
    const val MAX_FORM_COUNT = 20
    const val MAX_FORM_LABEL_LENGTH = 80
    const val MAX_FORM_SURFACE_LENGTH = 160
    const val MAX_FORM_READING_LENGTH = 240
    const val MAX_FORM_NOTE_LENGTH = 240
    const val MAX_PREVIEW_EXAMPLE_COUNT = 8
    const val MAX_PREVIEW_EXAMPLE_ORIGINAL_LENGTH = 400
    const val MAX_PREVIEW_EXAMPLE_RUBY_LENGTH = 800
    const val MAX_PREVIEW_TRANSLATION_LENGTH = 500
    const val MAX_EXAMPLE_FOCUS_LENGTH = 160
    const val MAX_EXAMPLE_FORM_KIND_LENGTH = 100
    const val MAX_EXAMPLE_NOTE_LENGTH = 500
    const val MAX_PENDING_ACTIONS = 512
    private val pendingLock = Any()

    fun preferences(context: Context) =
        storageContext(context).getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // This contains only the selected bounded display/preview deck,
            // its bookmark/known overlay and per-word aggregate quiz totals.
            // It never stores individual answers. Device-protected storage
            // lets Android draw it after reboot before the first unlock.
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }

    fun read(context: Context): LiveWallpaperConfig {
        val preferences = preferences(context)
        val overrides = decodeOverrides(preferences.getString(KEY_STATE_OVERRIDES, null))
        val excludeKnown = preferences.getBoolean(KEY_EXCLUDE_KNOWN, true)
        return LiveWallpaperConfig(
            enabled = preferences.getBoolean(KEY_ENABLED, false),
            intervalMinutes = preferences
                .getInt(KEY_INTERVAL_MINUTES, DEFAULT_INTERVAL_MINUTES)
                .coerceIn(MIN_INTERVAL_MINUTES, MAX_INTERVAL_MINUTES),
            showReading = preferences.getBoolean(KEY_SHOW_READING, true),
            showMeaning = preferences.getBoolean(KEY_SHOW_MEANING, true),
            excludeKnown = excludeKnown,
            levels = decodeLevels(preferences.getString(KEY_LEVELS, null)),
            deck = decodeDeck(preferences.getString(KEY_DECK, null))
                .map { word ->
                    val state = overrides[word.id]
                    word.copy(
                        bookmark = state?.bookmark ?: word.bookmark,
                        known = state?.known ?: word.known,
                    )
                }
                .let { deck -> if (excludeKnown) deck.filterNot { it.known } else deck },
        )
    }

    /**
     * Reads one stored preview entry without filtering a just-marked known
     * word. The compact wallpaper/widget deck still uses [read] and follows
     * the user's known-word filter, while a direct lookup can show the latest
     * state overlay until Flutter publishes the next deck.
     */
    fun readPreviewWord(context: Context, wordId: String): LiveWallpaperWord? {
        val safeId = wordId.trim().take(MAX_ID_LENGTH)
        if (safeId.isEmpty()) return null
        val preferences = preferences(context)
        val overrides = decodeOverrides(preferences.getString(KEY_STATE_OVERRIDES, null))
        val word = decodeDeck(preferences.getString(KEY_DECK, null))
            .firstOrNull { it.id == safeId } ?: return null
        val state = overrides[word.id]
        return word.copy(
            bookmark = state?.bookmark ?: word.bookmark,
            known = state?.known ?: word.known,
        )
    }

    fun readPlayback(context: Context): LiveWallpaperPlayback {
        val preferences = preferences(context)
        return LiveWallpaperPlayback(
            wordId = preferences.getString(KEY_CURRENT_WORD_ID, null).orEmpty(),
            deadlineMillis = preferences.getLong(KEY_DEADLINE_MILLIS, 0L),
            intervalMinutes = preferences.getInt(KEY_PLAYBACK_INTERVAL, 0),
        )
    }

    fun readWidgetKnownCountdown(context: Context): WidgetKnownCountdown? {
        val preferences = preferences(context)
        val wordId = preferences.getString(KEY_WIDGET_KNOWN_WORD_ID, null)
            ?.trim()
            ?.take(MAX_ID_LENGTH)
            .orEmpty()
        val deadlineMillis = preferences.getLong(KEY_WIDGET_KNOWN_DEADLINE_MILLIS, 0L)
        return if (wordId.isEmpty() || deadlineMillis <= 0L) {
            null
        } else {
            WidgetKnownCountdown(wordId, deadlineMillis)
        }
    }

    fun writeWidgetKnownCountdown(
        context: Context,
        wordId: String,
        deadlineMillis: Long,
    ): Boolean {
        val safeWordId = wordId.trim().take(MAX_ID_LENGTH)
        if (safeWordId.isEmpty() || deadlineMillis <= 0L) return false
        return preferences(context).edit()
            .putString(KEY_WIDGET_KNOWN_WORD_ID, safeWordId)
            .putLong(KEY_WIDGET_KNOWN_DEADLINE_MILLIS, deadlineMillis)
            .commit()
    }

    fun clearWidgetKnownCountdown(context: Context): Boolean =
        preferences(context).edit()
            .remove(KEY_WIDGET_KNOWN_WORD_ID)
            .remove(KEY_WIDGET_KNOWN_DEADLINE_MILLIS)
            .commit()

    fun writePlayback(
        context: Context,
        wordId: String,
        deadlineMillis: Long,
        intervalMinutes: Int,
        notifyWidget: Boolean = true,
    ) {
        preferences(context).edit()
            .putString(KEY_CURRENT_WORD_ID, wordId)
            .putLong(KEY_DEADLINE_MILLIS, deadlineMillis)
            .putInt(KEY_PLAYBACK_INTERVAL, intervalMinutes)
            .commit()
        if (notifyWidget) StarlightWordWidgetProvider.updateAll(context)
    }

    fun enqueueStateAction(
        context: Context,
        wordId: String,
        action: String,
        value: Boolean,
    ): Boolean {
        require(action == "bookmark" || action == "known")
        return synchronized(pendingLock) {
            val preferences = preferences(context)
            val pending = decodePendingActions(preferences.getString(KEY_PENDING_ACTIONS, null))
                .filterNot { it.wordId == wordId && it.action == action }
                .toMutableList()
            pending += PendingWallpaperAction(
                id = UUID.randomUUID().toString(),
                wordId = wordId,
                action = action,
                value = value,
                createdAt = System.currentTimeMillis(),
            )
            val overrides = decodeOverrides(preferences.getString(KEY_STATE_OVERRIDES, null))
                .toMutableMap()
            val previous = overrides[wordId] ?: WordStateOverride()
            overrides[wordId] = when (action) {
                "bookmark" -> previous.copy(bookmark = value)
                else -> previous.copy(known = value)
            }
            preferences.edit()
                .putString(KEY_PENDING_ACTIONS, encodePendingActions(pending).toString())
                .putString(KEY_STATE_OVERRIDES, encodeOverrides(overrides).toString())
                .commit()
        }
    }

    fun enqueueOpenDetails(context: Context, wordId: String): Boolean =
        synchronized(pendingLock) {
            val preferences = preferences(context)
            val pending = decodePendingActions(preferences.getString(KEY_PENDING_ACTIONS, null))
                .filterNot { it.action == "openDetails" }
                .toMutableList()
            pending += PendingWallpaperAction(
                id = UUID.randomUUID().toString(),
                wordId = wordId,
                action = "openDetails",
                value = null,
                createdAt = System.currentTimeMillis(),
            )
            preferences.edit()
                .putString(KEY_PENDING_ACTIONS, encodePendingActions(pending).toString())
                .commit()
        }

    fun pendingActions(context: Context): List<Map<String, Any>> = synchronized(pendingLock) {
        decodePendingActions(preferences(context).getString(KEY_PENDING_ACTIONS, null)).map { action ->
            buildMap {
                put("id", action.id)
                put("wordId", action.wordId)
                put("action", action.action)
                action.value?.let { put("value", it) }
                put("createdAt", action.createdAt)
            }
        }
    }

    fun ackPendingActions(context: Context, actionIds: Set<String>): Boolean {
        if (actionIds.isEmpty()) return true
        return synchronized(pendingLock) {
            val preferences = preferences(context)
            val allActions = decodePendingActions(preferences.getString(KEY_PENDING_ACTIONS, null))
            val acknowledged = allActions.filter { it.id in actionIds }
            val remaining = allActions.filterNot { it.id in actionIds }
            val overrides = decodeOverrides(preferences.getString(KEY_STATE_OVERRIDES, null))
                .toMutableMap()
            acknowledged.forEach { action ->
                if (action.action != "bookmark" && action.action != "known") return@forEach
                val hasNewerDesiredState = remaining.any {
                    it.wordId == action.wordId && it.action == action.action
                }
                if (hasNewerDesiredState) return@forEach
                val current = overrides[action.wordId] ?: return@forEach
                val updated = if (action.action == "bookmark") {
                    current.copy(bookmark = null)
                } else {
                    current.copy(known = null)
                }
                if (updated.bookmark == null && updated.known == null) {
                    overrides.remove(action.wordId)
                } else {
                    overrides[action.wordId] = updated
                }
            }
            preferences.edit()
                .putString(KEY_PENDING_ACTIONS, encodePendingActions(remaining).toString())
                .putString(KEY_STATE_OVERRIDES, encodeOverrides(overrides).toString())
                .commit()
        }
    }

    private fun decodeLevels(raw: String?): List<String> = runCatching {
        val array = JSONArray(raw ?: "[]")
        buildList {
            for (index in 0 until array.length()) {
                val level = array.optString(index).trim().lowercase()
                if (level.matches(Regex("n[1-5]")) && level !in this) add(level)
            }
        }
    }.getOrDefault(emptyList())

    private fun decodeDeck(raw: String?): List<LiveWallpaperWord> = runCatching {
        val array = JSONArray(raw ?: "[]")
        buildList {
            for (index in 0 until minOf(array.length(), MAX_DECK_SIZE)) {
                val item = array.optJSONObject(index) ?: continue
                val id = item.optString("id").trim().take(MAX_ID_LENGTH)
                val word = item.optString("word").trim().take(MAX_WORD_LENGTH)
                if (id.isEmpty() || word.isEmpty()) continue
                val legacyMeaning = item.optString("meaning").trim().take(MAX_MEANING_LENGTH)
                val legacyReading = item.optString("reading").trim().take(MAX_READING_LENGTH)
                val legacyExample = item.optString("example").trim().take(MAX_EXAMPLE_LENGTH)
                val legacyExampleMeaning = item.optString("exampleMeaning").trim()
                    .take(MAX_EXAMPLE_MEANING_LENGTH)
                val meanings = decodeTextList(
                    item.optJSONArray("meanings"),
                    MAX_MEANING_COUNT,
                    MAX_PREVIEW_MEANING_LENGTH,
                ).ifEmpty {
                    if (legacyMeaning.isEmpty()) emptyList() else listOf(legacyMeaning)
                }
                val readings = decodeTextList(
                    item.optJSONArray("readings"),
                    MAX_READING_COUNT,
                    MAX_SINGLE_READING_LENGTH,
                ).ifEmpty {
                    legacyReading.split('・').map(String::trim).filter(String::isNotEmpty)
                }
                val alternativeReadings = decodeTextList(
                    item.optJSONArray("alternativeReadings"),
                    MAX_READING_COUNT,
                    MAX_SINGLE_READING_LENGTH,
                ).ifEmpty { readings.drop(1) }
                val quizAttempts = item.optInt("quizAttempts", 0).coerceIn(0, MAX_QUIZ_COUNT)
                val quizCorrect = item.optInt("quizCorrect", 0)
                    .coerceIn(0, quizAttempts)
                val examples = decodeExamples(item.optJSONArray("examples")).ifEmpty {
                    if (legacyExample.isEmpty() && legacyExampleMeaning.isEmpty()) {
                        emptyList()
                    } else {
                        listOf(
                            LiveWallpaperExampleSentence(
                                original = legacyExample,
                                ruby = "",
                                literalTranslation = legacyExampleMeaning,
                                naturalTranslation = legacyExampleMeaning,
                                focusSurface = "",
                                formKind = "",
                                note = "",
                            ),
                        )
                    }
                }
                add(
                    LiveWallpaperWord(
                        id = id,
                        word = word,
                        reading = legacyReading,
                        readings = readings,
                        alternativeReadings = alternativeReadings,
                        meaning = legacyMeaning.ifEmpty { meanings.firstOrNull().orEmpty() },
                        partOfSpeech = item.optString("partOfSpeech").trim()
                            .take(MAX_PART_OF_SPEECH_LENGTH),
                        conjugationClass = item.optString("conjugationClass").trim()
                            .take(MAX_CONJUGATION_CLASS_LENGTH),
                        meanings = meanings,
                        usageNotes = decodeTextList(
                            item.optJSONArray("usageNotes"),
                            MAX_USAGE_NOTE_COUNT,
                            MAX_USAGE_NOTE_LENGTH,
                        ),
                        note = item.optString("note").trim().take(MAX_WORD_NOTE_LENGTH),
                        quizAttempts = quizAttempts,
                        quizCorrect = quizCorrect,
                        forms = decodeForms(item.optJSONArray("forms")),
                        examples = examples,
                        example = legacyExample.ifEmpty {
                            examples.firstOrNull()?.original.orEmpty()
                        },
                        exampleMeaning = legacyExampleMeaning.ifEmpty {
                            examples.firstOrNull()?.naturalTranslation.orEmpty()
                        },
                        level = item.optString("level").trim().lowercase()
                            .takeIf { it.matches(Regex("n[1-5]")) }
                            .orEmpty(),
                        bookmark = item.optBoolean("bookmark", false),
                        known = item.optBoolean("known", false),
                    ),
                )
            }
        }
    }.getOrDefault(emptyList())

    private fun decodeTextList(
        array: JSONArray?,
        maxItems: Int,
        maxLength: Int,
    ): List<String> = buildList {
        if (array == null) return@buildList
        for (index in 0 until minOf(array.length(), maxItems)) {
            val value = array.optString(index).trim().take(maxLength)
            if (value.isNotEmpty()) add(value)
        }
    }

    private fun decodeForms(array: JSONArray?): List<LiveWallpaperConjugationForm> = buildList {
        if (array == null) return@buildList
        for (index in 0 until minOf(array.length(), MAX_FORM_COUNT)) {
            val item = array.optJSONObject(index) ?: continue
            val surface = item.optString("surface").trim().take(MAX_FORM_SURFACE_LENGTH)
            if (surface.isEmpty()) continue
            add(
                LiveWallpaperConjugationForm(
                    label = item.optString("label").trim().take(MAX_FORM_LABEL_LENGTH),
                    surface = surface,
                    reading = item.optString("reading").trim().take(MAX_FORM_READING_LENGTH),
                    note = item.optString("note").trim().take(MAX_FORM_NOTE_LENGTH),
                ),
            )
        }
    }

    private fun decodeExamples(array: JSONArray?): List<LiveWallpaperExampleSentence> = buildList {
        if (array == null) return@buildList
        for (index in 0 until minOf(array.length(), MAX_PREVIEW_EXAMPLE_COUNT)) {
            val item = array.optJSONObject(index) ?: continue
            val original = item.optString("original").trim()
                .take(MAX_PREVIEW_EXAMPLE_ORIGINAL_LENGTH)
            if (original.isEmpty()) continue
            add(
                LiveWallpaperExampleSentence(
                    original = original,
                    ruby = item.optString("ruby").trim()
                        .take(MAX_PREVIEW_EXAMPLE_RUBY_LENGTH),
                    literalTranslation = item.optString("literalTranslation").trim()
                        .take(MAX_PREVIEW_TRANSLATION_LENGTH),
                    naturalTranslation = item.optString("naturalTranslation").trim()
                        .take(MAX_PREVIEW_TRANSLATION_LENGTH),
                    focusSurface = item.optString("focusSurface").trim()
                        .take(MAX_EXAMPLE_FOCUS_LENGTH),
                    formKind = item.optString("formKind").trim()
                        .take(MAX_EXAMPLE_FORM_KIND_LENGTH),
                    note = item.optString("note").trim().take(MAX_EXAMPLE_NOTE_LENGTH),
                ),
            )
        }
    }

    private data class WordStateOverride(
        val bookmark: Boolean? = null,
        val known: Boolean? = null,
    )

    private data class PendingWallpaperAction(
        val id: String,
        val wordId: String,
        val action: String,
        val value: Boolean?,
        val createdAt: Long,
    )

    private fun decodeOverrides(raw: String?): Map<String, WordStateOverride> = runCatching {
        val root = JSONObject(raw ?: "{}")
        buildMap {
            val keys = root.keys()
            while (keys.hasNext()) {
                val wordId = keys.next()
                val item = root.optJSONObject(wordId) ?: continue
                put(
                    wordId,
                    WordStateOverride(
                        bookmark = if (item.has("bookmark")) item.optBoolean("bookmark") else null,
                        known = if (item.has("known")) item.optBoolean("known") else null,
                    ),
                )
            }
        }
    }.getOrDefault(emptyMap())

    private fun encodeOverrides(overrides: Map<String, WordStateOverride>): JSONObject =
        JSONObject().apply {
            overrides.forEach { (wordId, state) ->
                put(
                    wordId,
                    JSONObject().apply {
                        state.bookmark?.let { put("bookmark", it) }
                        state.known?.let { put("known", it) }
                    },
                )
            }
        }

    private fun decodePendingActions(raw: String?): List<PendingWallpaperAction> = runCatching {
        val array = JSONArray(raw ?: "[]")
        buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val id = item.optString("id")
                val wordId = item.optString("wordId")
                val action = item.optString("action")
                if (id.isEmpty() || wordId.isEmpty() || action.isEmpty()) continue
                val rawValue = item.opt("value")
                val valid = action == "openDetails" ||
                    ((action == "bookmark" || action == "known") && rawValue is Boolean)
                if (!valid) continue
                add(
                    PendingWallpaperAction(
                        id = id,
                        wordId = wordId,
                        action = action,
                        value = rawValue as? Boolean,
                        createdAt = item.optLong("createdAt"),
                    ),
                )
            }
        }.takeLast(MAX_PENDING_ACTIONS)
    }.getOrDefault(emptyList())

    private fun encodePendingActions(actions: List<PendingWallpaperAction>): JSONArray =
        JSONArray().apply {
            actions.takeLast(MAX_PENDING_ACTIONS).forEach { action ->
                put(
                    JSONObject().apply {
                        put("id", action.id)
                        put("wordId", action.wordId)
                        put("action", action.action)
                        action.value?.let { put("value", it) }
                        put("createdAt", action.createdAt)
                    },
                )
            }
        }
}
