package app.shinbi.tsuki_words

import android.app.AlarmManager
import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

/**
 * Interactive companion for the intentionally non-interactive live wallpaper.
 *
 * The widget and wallpaper read the same device-protected deck/playback data,
 * so changing a word in either surface updates the other without introducing a
 * second database or a background service.
 */
open class StarlightWordWidgetProvider : AppWidgetProvider() {
    /**
     * The original component remains the LockStar/keyguard widget so an app
     * upgrade does not silently change existing Galaxy lock-screen bindings.
     */
    protected open val rendersHomeScreenSurface: Boolean = false

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_ROTATE,
            ACTION_EXACT_ALARM_PERMISSION_CHANGED,
            ACTION_PINNED,
            -> updateAll(context)
            ACTION_PREVIOUS,
            ACTION_NEXT,
            ACTION_RESET_TIMER,
            ACTION_EXTEND_LEGACY,
            ACTION_BOOKMARK,
            ACTION_KNOWN,
            -> handleAction(context, intent)
            ACTION_PROGRESS_TICK, ACTION_TIMER_WARNING -> updateTimerViews(context)
            ACTION_KNOWN_COUNTDOWN -> updateAll(context)
            ACTION_DETAILS_LEGACY -> openLegacyAppDetails(context, intent)
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        update(
            context,
            appWidgetManager,
            appWidgetIds,
            forcedHostSurface = providerSurface(rendersHomeScreenSurface),
        )
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        update(
            context,
            appWidgetManager,
            intArrayOf(appWidgetId),
            forcedHostSurface = providerSurface(rendersHomeScreenSurface),
        )
    }

    override fun onEnabled(context: Context) {
        updateAll(context)
    }

    override fun onDisabled(context: Context) {
        // onDisabled is scoped to one receiver component. Re-evaluate both so
        // removing the home widget does not stop an existing LockStar widget,
        // or vice versa.
        updateAll(context)
    }

    companion object {
        private const val ACTION_PREFIX = "app.shinbi.tsuki_words.widget."
        private const val ACTION_PREVIOUS = "${ACTION_PREFIX}PREVIOUS"
        private const val ACTION_NEXT = "${ACTION_PREFIX}NEXT"
        private const val ACTION_RESET_TIMER = "${ACTION_PREFIX}RESET_TIMER"
        private const val ACTION_EXTEND_LEGACY = "${ACTION_PREFIX}EXTEND"
        private const val ACTION_BOOKMARK = "${ACTION_PREFIX}BOOKMARK"
        private const val ACTION_KNOWN = "${ACTION_PREFIX}KNOWN"
        private const val ACTION_DETAILS_LEGACY = "${ACTION_PREFIX}DETAILS"
        private const val ACTION_ROTATE = "${ACTION_PREFIX}ROTATE"
        private const val ACTION_TIMER_WARNING = "${ACTION_PREFIX}TIMER_WARNING"
        private const val ACTION_PROGRESS_TICK = "${ACTION_PREFIX}PROGRESS_TICK"
        private const val ACTION_KNOWN_COUNTDOWN = "${ACTION_PREFIX}KNOWN_COUNTDOWN"
        private const val ACTION_EXACT_ALARM_PERMISSION_CHANGED =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
        internal const val ACTION_PINNED = "${ACTION_PREFIX}PINNED"
        internal const val EXTRA_WORD_ID = "widgetWordId"
        private const val ROTATION_REQUEST_CODE = 31_701
        private const val PROGRESS_REQUEST_CODE = 31_702
        private const val WARNING_REQUEST_CODE = 31_703
        private const val KNOWN_COUNTDOWN_REQUEST_CODE = 31_704
        private const val ONE_DAY_MINUTES = 24 * 60
        private const val MILLIS_PER_MINUTE = 60_000L
        private const val PART_OF_SPEECH_MIN_WIDTH_DP = 300
        private const val TIMER_PROGRESS_MAX = 1_000
        private const val TIMER_PROGRESS_SEGMENTS = 20L
        private const val TIMER_WARNING_THRESHOLD_MILLIS = 10_000L
        private const val KNOWN_UNDO_WINDOW_MILLIS = 3_000L
        private const val MIN_PROGRESS_TICK_MILLIS = 30_000L
        private const val MAX_PROGRESS_TICK_MILLIS = 10 * MILLIS_PER_MINUTE
        private const val CONTENT_PADDING_DP = 16
        private const val TIMER_HORIZONTAL_PADDING_DP = 4
        private const val TIMER_VERTICAL_PADDING_DP = 0
        private const val ACTIVITY_REQUEST_CODE_MULTIPLIER = 100
        private const val DETAILS_REQUEST_CODE_OFFSET = 61
        private const val EXAMPLE_DETAILS_REQUEST_CODE_OFFSET = 62

        private enum class WidgetHostSurface {
            HOME,
            KEYGUARD,
            UNKNOWN,
        }

        private data class WidgetState(
            val config: LiveWallpaperConfig,
            val playback: LiveWallpaperPlayback,
            val word: LiveWallpaperWord,
            val index: Int,
            val pendingKnown: WidgetKnownCountdown? = null,
        )

        /** Refreshes every installed instance after deck/playback changes. */
        internal fun updateAll(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val lockscreenIds = manager.getAppWidgetIds(
                ComponentName(appContext, StarlightWordWidgetProvider::class.java),
            )
            val homeIds = manager.getAppWidgetIds(
                ComponentName(appContext, StarlightHomeWordWidgetProvider::class.java),
            )
            if (lockscreenIds.isEmpty() && homeIds.isEmpty()) {
                cancelRotation(appContext)
                cancelProgressTick(appContext)
                cancelTimerWarning(appContext)
                cancelKnownCountdown(appContext)
                return
            }
            update(
                appContext,
                manager,
                lockscreenIds,
                forcedHostSurface = WidgetHostSurface.KEYGUARD,
            )
            update(
                appContext,
                manager,
                homeIds,
                forcedHostSurface = WidgetHostSurface.HOME,
            )
        }

        internal fun installedWidgetIds(context: Context): IntArray =
            lockscreenWidgetIds(context) + homeWidgetIds(context)

        internal fun lockscreenWidgetIds(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, StarlightWordWidgetProvider::class.java),
            )

        internal fun homeWidgetIds(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, StarlightHomeWordWidgetProvider::class.java),
            )

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray,
            forcedHostSurface: WidgetHostSurface? = null,
        ) {
            if (ids.isEmpty()) return
            val now = System.currentTimeMillis()
            val state = resolveState(context, now)
            ids.forEach { appWidgetId ->
                val options = manager.getAppWidgetOptions(appWidgetId)
                // Component identity is authoritative. Category detection is
                // retained only for compatibility with any future unforced
                // provider because One UI/LockStar may report HOME or omit it.
                val hostSurface = forcedHostSurface ?: resolveHostSurface(options)
                val layout = if (hostSurface == WidgetHostSurface.HOME) {
                    R.layout.starlight_word_widget_compact
                } else {
                    // LockStar and some OEM hosts omit the host-category option.
                    // The inset layout is the safer unknown-host fallback: it
                    // keeps the card's real inner padding and never assumes an
                    // unauthenticated Flutter launch is possible.
                    R.layout.starlight_word_widget_keyguard_compact
                }
                val views = RemoteViews(context.packageName, layout)
                // Some LockStar versions normalize XML padding while caching or
                // reapplying RemoteViews. Reassert it on the nested card root in
                // physical pixels on every render.
                val contentPadding = (
                    CONTENT_PADDING_DP * context.resources.displayMetrics.density + 0.5f
                    ).toInt()
                views.setViewPadding(
                    R.id.widget_root,
                    contentPadding,
                    contentPadding,
                    contentPadding,
                    contentPadding,
                )
                val timerHorizontalPadding = (
                    TIMER_HORIZONTAL_PADDING_DP * context.resources.displayMetrics.density + 0.5f
                    ).toInt()
                val timerVerticalPadding = (
                    TIMER_VERTICAL_PADDING_DP * context.resources.displayMetrics.density + 0.5f
                    ).toInt()
                views.setViewPadding(
                    R.id.widget_timer_card,
                    timerHorizontalPadding,
                    timerVerticalPadding,
                    timerHorizontalPadding,
                    timerVerticalPadding,
                )
                if (state == null) {
                    renderEmpty(views)
                } else {
                    renderWord(
                        context,
                        views,
                        appWidgetId,
                        state,
                        now,
                        options,
                    )
                }
                manager.updateAppWidget(appWidgetId, views)
                if (state != null) {
                    @Suppress("DEPRECATION")
                    manager.notifyAppWidgetViewDataChanged(
                        appWidgetId,
                        R.id.widget_example_list,
                    )
                }
            }
            if (state == null) {
                cancelRotation(context)
                cancelProgressTick(context)
                cancelTimerWarning(context)
                cancelKnownCountdown(context)
            } else if (state.pendingKnown != null) {
                // The three-second undo window owns the next word boundary.
                // Suppress the normal rotation alarms so an already-near timer
                // cannot move the held word out from under the user.
                cancelRotation(context)
                cancelProgressTick(context)
                cancelTimerWarning(context)
                scheduleKnownCountdown(
                    context,
                    state.pendingKnown.deadlineMillis,
                    now,
                )
            } else {
                cancelKnownCountdown(context)
                scheduleRotation(context, state.playback.deadlineMillis, now)
                scheduleTimerWarning(context, state.playback.deadlineMillis, now)
                scheduleProgressTick(
                    context,
                    state.playback.deadlineMillis,
                    state.config.intervalMinutes,
                    now,
                )
            }
        }

        /**
         * Refresh only the timer actions so an in-progress example scroll is
         * not reset by the coarse progress and ten-second warning boundaries.
         */
        private fun updateTimerViews(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val lockscreenIds = lockscreenWidgetIds(appContext)
            val homeIds = homeWidgetIds(appContext)
            if (lockscreenIds.isEmpty() && homeIds.isEmpty()) {
                cancelRotation(appContext)
                cancelProgressTick(appContext)
                cancelTimerWarning(appContext)
                cancelKnownCountdown(appContext)
                return
            }
            val now = System.currentTimeMillis()
            if (LiveWallpaperPreferences.readWidgetKnownCountdown(appContext) != null) {
                // A full render is required because the known button contains
                // the short undo countdown, not only the long rotation timer.
                updateAll(appContext)
                return
            }
            val config = LiveWallpaperPreferences.read(appContext)
            val playback = LiveWallpaperPreferences.readPlayback(appContext)
            val valid = config.deck.any { it.id == playback.wordId } &&
                playback.deadlineMillis > now &&
                playback.intervalMinutes == config.intervalMinutes
            if (!valid) {
                updateAll(appContext)
                return
            }

            fun updateIds(ids: IntArray, layoutId: Int) {
                ids.forEach { appWidgetId ->
                    val views = RemoteViews(appContext.packageName, layoutId)
                    renderTimer(appContext, views, config, playback, now)
                    manager.partiallyUpdateAppWidget(appWidgetId, views)
                }
            }
            updateIds(lockscreenIds, R.layout.starlight_word_widget_keyguard_compact)
            updateIds(homeIds, R.layout.starlight_word_widget_compact)
            scheduleRotation(appContext, playback.deadlineMillis, now)
            scheduleTimerWarning(appContext, playback.deadlineMillis, now)
            scheduleProgressTick(
                appContext,
                playback.deadlineMillis,
                config.intervalMinutes,
                now,
            )
        }

        private fun renderTimer(
            context: Context,
            views: RemoteViews,
            config: LiveWallpaperConfig,
            playback: LiveWallpaperPlayback,
            now: Long,
        ) {
            val remaining = (playback.deadlineMillis - now).coerceAtLeast(0L)
            val intervalMillis = config.intervalMinutes * MILLIS_PER_MINUTE
            val progress = (
                remaining.coerceAtMost(intervalMillis) * TIMER_PROGRESS_MAX / intervalMillis
                ).toInt()
            val warning = remaining in 1L..TIMER_WARNING_THRESHOLD_MILLIS

            views.setTextViewText(
                R.id.widget_timer_title,
                context.getString(
                    if (warning) {
                        R.string.word_widget_timer_warning
                    } else {
                        R.string.word_widget_next_timer
                    },
                ),
            )
            views.setTextViewText(R.id.widget_interval, intervalLabel(config.intervalMinutes))
            views.setInt(
                R.id.widget_timer_card,
                "setBackgroundResource",
                if (warning) {
                    R.drawable.word_widget_timer_warning_background
                } else {
                    R.drawable.word_widget_timer_background
                },
            )
            views.setTextColor(
                R.id.widget_timer_title,
                context.getColor(
                    if (warning) R.color.word_widget_warning_muted else R.color.word_widget_muted,
                ),
            )
            views.setTextColor(
                R.id.widget_countdown,
                context.getColor(
                    if (warning) R.color.word_widget_warning else R.color.word_widget_gold,
                ),
            )
            views.setTextColor(
                R.id.widget_interval,
                context.getColor(
                    if (warning) R.color.word_widget_warning_muted else R.color.word_widget_reading,
                ),
            )
            views.setInt(
                R.id.widget_interval,
                "setBackgroundResource",
                if (warning) {
                    R.drawable.word_widget_interval_warning_badge_background
                } else {
                    R.drawable.word_widget_interval_badge_background
                },
            )
            views.setProgressBar(
                R.id.widget_timer_progress,
                TIMER_PROGRESS_MAX,
                progress,
                false,
            )
            views.setProgressBar(
                R.id.widget_timer_progress_warning,
                TIMER_PROGRESS_MAX,
                progress,
                false,
            )
            views.setViewVisibility(
                R.id.widget_timer_progress,
                if (warning) View.GONE else View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_timer_progress_warning,
                if (warning) View.VISIBLE else View.GONE,
            )

            // Chronometer updates smoothly inside the host process. Alarm
            // broadcasts are needed only for the style and word boundaries.
            val elapsedDeadline = SystemClock.elapsedRealtime() + remaining
            views.setChronometer(R.id.widget_countdown, elapsedDeadline, null, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                views.setChronometerCountDown(R.id.widget_countdown, true)
            }
        }

        private fun renderEmpty(views: RemoteViews) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
        }

        private fun renderWord(
            context: Context,
            views: RemoteViews,
            appWidgetId: Int,
            state: WidgetState,
            now: Long,
            options: android.os.Bundle,
        ) {
            val config = state.config
            val word = state.word
            views.setViewVisibility(R.id.widget_content, View.VISIBLE)
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            views.setTextViewText(
                R.id.widget_level,
                word.level.uppercase().takeIf { it.isNotEmpty() }?.let { "데모" } ?: "데모",
            )
            views.setTextViewText(R.id.widget_position, "${state.index + 1} / ${config.deck.size}")
            val showPartOfSpeech =
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) >=
                    PART_OF_SPEECH_MIN_WIDTH_DP &&
                    word.partOfSpeech.isNotBlank()
            val partOfSpeechLabel = widgetPartOfSpeech(word)
            views.setTextViewText(R.id.widget_part_of_speech, partOfSpeechLabel)
            views.setViewVisibility(
                R.id.widget_part_of_speech,
                if (showPartOfSpeech && partOfSpeechLabel.isNotEmpty()) {
                    View.VISIBLE
                } else {
                    View.GONE
                },
            )
            views.setTextViewText(R.id.widget_reading, word.reading)
            views.setViewVisibility(
                R.id.widget_reading,
                if (config.showReading && word.reading.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            views.setTextViewText(R.id.widget_word, word.word)
            views.setTextViewText(R.id.widget_meaning, word.meaning)
            views.setViewVisibility(
                R.id.widget_meaning,
                if (config.showMeaning && word.meaning.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_example_container,
                View.VISIBLE,
            )
            val exampleAdapter = Intent(context, WordWidgetExampleService::class.java).apply {
                putExtra(WordWidgetExampleService.EXTRA_WORD_ID, word.id)
                data = Uri.Builder()
                    .scheme("starlight-word")
                    .authority("widget-example")
                    .appendPath(appWidgetId.toString())
                    .appendPath(word.id)
                    .build()
            }
            @Suppress("DEPRECATION")
            views.setRemoteAdapter(R.id.widget_example_list, exampleAdapter)
            renderTimer(context, views, config, state.playback, now)

            views.setTextViewText(
                R.id.widget_bookmark,
                if (word.bookmark) {
                    context.getString(R.string.word_widget_bookmarked_label)
                } else {
                    context.getString(R.string.word_widget_bookmark_label)
                },
            )
            views.setInt(
                R.id.widget_bookmark,
                "setBackgroundResource",
                if (word.bookmark) {
                    R.drawable.word_widget_action_active_background
                } else {
                    R.drawable.word_widget_action_background
                },
            )
            val pendingKnown = state.pendingKnown?.takeIf { it.wordId == word.id }
            val visuallyKnown = word.known || pendingKnown != null
            val knownCountdownSeconds = pendingKnown?.let {
                ((it.deadlineMillis - now).coerceAtLeast(1L) + 999L) / 1_000L
            }
            views.setTextViewText(
                R.id.widget_known,
                if (knownCountdownSeconds != null) {
                    context.getString(
                        R.string.word_widget_known_countdown_label,
                        knownCountdownSeconds,
                    )
                } else {
                    context.getString(R.string.word_widget_known_label)
                },
            )
            views.setInt(
                R.id.widget_known,
                "setBackgroundResource",
                if (visuallyKnown) {
                    R.drawable.word_widget_action_active_background
                } else {
                    R.drawable.word_widget_action_background
                },
            )
            views.setTextViewCompoundDrawablesRelative(
                R.id.widget_bookmark,
                if (word.bookmark) {
                    R.drawable.widget_ic_bookmark_filled
                } else {
                    R.drawable.widget_ic_bookmark
                },
                0,
                0,
                0,
            )
            views.setTextViewCompoundDrawablesRelative(
                R.id.widget_known,
                if (visuallyKnown) {
                    R.drawable.widget_ic_known_filled
                } else {
                    R.drawable.widget_ic_known
                },
                0,
                0,
                0,
            )

            val wordId = word.id
            views.setOnClickPendingIntent(
                R.id.widget_previous,
                actionIntent(context, appWidgetId, ACTION_PREVIOUS, wordId, 1),
            )
            views.setOnClickPendingIntent(
                R.id.widget_reset_timer,
                actionIntent(context, appWidgetId, ACTION_RESET_TIMER, wordId, 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                actionIntent(context, appWidgetId, ACTION_NEXT, wordId, 3),
            )
            views.setOnClickPendingIntent(
                R.id.widget_bookmark,
                actionIntent(context, appWidgetId, ACTION_BOOKMARK, wordId, 4),
            )
            views.setOnClickPendingIntent(
                R.id.widget_known,
                actionIntent(context, appWidgetId, ACTION_KNOWN, wordId, 5),
            )
            val details = appDetailsIntent(context, appWidgetId, wordId)
            val exampleDetails = appDetailsIntent(
                context,
                appWidgetId,
                wordId,
                revealExamples = true,
            )
            // Collection rows need a PendingIntent template; the factory adds
            // an empty fill-in intent to each real example row. The separate,
            // immutable template has the examples destination fixed by this
            // app, so untrusted row data cannot alter the Activity or word id.
            views.setPendingIntentTemplate(R.id.widget_example_list, exampleDetails)
            views.setOnClickPendingIntent(R.id.widget_root, details)
        }

        private fun actionIntent(
            context: Context,
            appWidgetId: Int,
            action: String,
            wordId: String,
            actionIndex: Int,
        ): PendingIntent {
            val intent = Intent(context, StarlightWordWidgetProvider::class.java).apply {
                this.action = action
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra(EXTRA_WORD_ID, wordId)
            }
            return PendingIntent.getBroadcast(
                context,
                appWidgetId * 10 + actionIndex,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun appDetailsIntent(
            context: Context,
            appWidgetId: Int,
            wordId: String,
            revealExamples: Boolean = false,
        ): PendingIntent {
            return activityPendingIntent(
                context,
                appWidgetId * ACTIVITY_REQUEST_CODE_MULTIPLIER +
                    if (revealExamples) {
                        EXAMPLE_DETAILS_REQUEST_CODE_OFFSET
                    } else {
                        DETAILS_REQUEST_CODE_OFFSET
                    },
                appDetailsActivityIntent(
                    context,
                    appWidgetId,
                    wordId,
                    revealExamples = revealExamples,
                ),
            )
        }

        private fun appDetailsActivityIntent(
            context: Context,
            appWidgetId: Int,
            wordId: String,
            revealExamples: Boolean = false,
        ): Intent = Intent(context, MainActivity::class.java).apply {
            action = LiveWallpaperChannel.ACTION_OPEN_WORD_DETAILS
            putExtra(LiveWallpaperChannel.EXTRA_WORD_ID, wordId)
            putExtra(LiveWallpaperChannel.EXTRA_REVEAL_EXAMPLES, revealExamples)
            data = detailsData(appWidgetId, revealExamples)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        private fun detailsData(appWidgetId: Int, revealExamples: Boolean = false): Uri =
            Uri.Builder()
                .scheme("starlight-word")
                .authority("widget-details")
                .appendPath(appWidgetId.toString())
                .appendPath(if (revealExamples) "examples" else "word")
                .build()

        @Suppress("DEPRECATION")
        private fun activityPendingIntent(
            context: Context,
            requestCode: Int,
            intent: Intent,
        ): PendingIntent {
            // Android 14+ requires the PendingIntent creator to explicitly opt
            // into background Activity starts. This remains narrowly scoped to
            // the user's explicit tap and our immutable, explicit Activities.
            val creatorOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ActivityOptions.makeBasic()
                    .setPendingIntentCreatorBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                    ).toBundle()
            } else {
                null
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                creatorOptions,
            )
        }

        private fun resolveHostSurface(options: android.os.Bundle): WidgetHostSurface {
            val category = options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY,
                0,
            )
            return when {
                category and AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD != 0 ->
                    WidgetHostSurface.KEYGUARD
                category and AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN != 0 ->
                    WidgetHostSurface.HOME
                else -> WidgetHostSurface.UNKNOWN
            }
        }

        private fun providerSurface(homeScreen: Boolean): WidgetHostSurface =
            if (homeScreen) WidgetHostSurface.HOME else WidgetHostSurface.KEYGUARD

        private fun widgetPartOfSpeech(word: LiveWallpaperWord): String {
            val partOfSpeech = word.partOfSpeech.trim()
            if (!partOfSpeech.contains("동사")) return partOfSpeech
            val conjugation = word.conjugationClass.trim()
            val shortConjugation = when {
                conjugation.startsWith("1단") -> "1단"
                conjugation.startsWith("5단") -> "5단"
                conjugation.startsWith("サ변") -> "サ변"
                conjugation.startsWith("カ변") -> "カ변"
                conjugation.startsWith("ずる") -> "ずる"
                conjugation.contains("불규칙") -> "불규칙"
                else -> ""
            }
            return if (shortConjugation.isEmpty()) {
                partOfSpeech
            } else {
                "$partOfSpeech · $shortConjugation"
            }
        }

        private fun handleAction(context: Context, intent: Intent) {
            val now = System.currentTimeMillis()
            val state = resolveState(context, now) ?: run {
                updateAll(context)
                return
            }
            val config = state.config
            val requestedWordId = intent.getStringExtra(EXTRA_WORD_ID).orEmpty()
            val requestedWord = LiveWallpaperPreferences.readPreviewWord(
                context,
                requestedWordId,
            )
            when (intent.action) {
                ACTION_PREVIOUS, ACTION_NEXT -> {
                    // Explicit navigation wins over a deferred automatic move.
                    // Keep the learned state pending only when the user stays
                    // on the same card; navigation cancels that pending state.
                    if (state.pendingKnown != null) {
                        LiveWallpaperPreferences.clearWidgetKnownCountdown(context)
                        cancelKnownCountdown(context)
                    }
                    val delta = if (intent.action == ACTION_PREVIOUS) -1 else 1
                    val nextIndex = Math.floorMod(state.index + delta, config.deck.size)
                    LiveWallpaperPreferences.writePlayback(
                        context,
                        config.deck[nextIndex].id,
                        now + config.intervalMinutes * MILLIS_PER_MINUTE,
                        config.intervalMinutes,
                        notifyWidget = false,
                    )
                }
                ACTION_RESET_TIMER, ACTION_EXTEND_LEGACY -> {
                    LiveWallpaperPreferences.writePlayback(
                        context,
                        state.word.id,
                        now + config.intervalMinutes * MILLIS_PER_MINUTE,
                        config.intervalMinutes,
                        notifyWidget = false,
                    )
                }
                ACTION_BOOKMARK -> requestedWord?.let { word ->
                    LiveWallpaperPreferences.enqueueStateAction(
                        context,
                        word.id,
                        "bookmark",
                        !word.bookmark,
                    )
                }
                ACTION_KNOWN -> requestedWord?.let { word ->
                    val pending = state.pendingKnown
                    when {
                        pending?.wordId == word.id -> {
                            // Second tap during 3→2→1 is a true undo: no
                            // known action has been published to Flutter yet.
                            LiveWallpaperPreferences.clearWidgetKnownCountdown(context)
                            cancelKnownCountdown(context)
                            LiveWallpaperPreferences.writePlayback(
                                context,
                                word.id,
                                now + config.intervalMinutes * MILLIS_PER_MINUTE,
                                config.intervalMinutes,
                                notifyWidget = false,
                            )
                        }
                        word.known -> {
                            // A word that was already learned before this tap
                            // can be restored immediately; it has no auto-move.
                            LiveWallpaperPreferences.enqueueStateAction(
                                context,
                                word.id,
                                "known",
                                false,
                            )
                        }
                        word.id == state.word.id -> {
                            LiveWallpaperPreferences.writeWidgetKnownCountdown(
                                context,
                                word.id,
                                now + KNOWN_UNDO_WINDOW_MILLIS,
                            )
                        }
                    }
                }
            }
            updateAll(context)
        }

        /** Compatibility path for a stale RemoteViews broadcast after upgrade. */
        private fun openLegacyAppDetails(context: Context, intent: Intent) {
            val wordId = intent.getStringExtra(EXTRA_WORD_ID)?.trim().orEmpty()
            if (wordId.isEmpty()) return
            val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0)
            runCatching {
                context.startActivity(
                    appDetailsActivityIntent(context, appWidgetId, wordId)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
        }

        private fun resolveState(context: Context, now: Long): WidgetState? {
            val pendingKnown = LiveWallpaperPreferences.readWidgetKnownCountdown(context)
            if (pendingKnown != null) {
                if (now >= pendingKnown.deadlineMillis) {
                    completeKnownCountdown(context, pendingKnown, now)
                } else {
                    val pendingConfig = LiveWallpaperPreferences.read(context)
                    val pendingPlayback = LiveWallpaperPreferences.readPlayback(context)
                    val pendingWord = LiveWallpaperPreferences.readPreviewWord(
                        context,
                        pendingKnown.wordId,
                    )
                    val pendingIndex = pendingConfig.deck.indexOfFirst {
                        it.id == pendingKnown.wordId
                    }
                    if (
                        pendingWord != null &&
                        !pendingWord.known &&
                        pendingPlayback.wordId == pendingKnown.wordId &&
                        pendingIndex >= 0
                    ) {
                        return WidgetState(
                            pendingConfig,
                            pendingPlayback,
                            // Reflect the user's tap immediately while the
                            // persisted domain state remains safely undoable.
                            pendingWord.copy(known = true),
                            pendingIndex,
                            pendingKnown,
                        )
                    }
                    LiveWallpaperPreferences.clearWidgetKnownCountdown(context)
                    cancelKnownCountdown(context)
                }
            }

            val config = LiveWallpaperPreferences.read(context)
            if (config.deck.isEmpty()) return null
            var playback = LiveWallpaperPreferences.readPlayback(context)
            var currentIndex = config.deck.indexOfFirst { it.id == playback.wordId }
            val mustReset = currentIndex < 0 ||
                playback.deadlineMillis <= 0L ||
                playback.intervalMinutes != config.intervalMinutes
            if (mustReset) {
                currentIndex = Math.floorMod(
                    wordSlot(config.intervalMinutes, now),
                    config.deck.size.toLong(),
                ).toInt()
                playback = persistPlayback(
                    context,
                    config.deck[currentIndex].id,
                    now + if (config.intervalMinutes == ONE_DAY_MINUTES) {
                        nextDelay(config.intervalMinutes, now)
                    } else {
                        config.intervalMinutes * MILLIS_PER_MINUTE
                    },
                    config.intervalMinutes,
                )
            } else if (now >= playback.deadlineMillis) {
                currentIndex = Math.floorMod(
                    currentIndex.toLong() + 1L,
                    config.deck.size.toLong(),
                ).toInt()
                playback = persistPlayback(
                    context,
                    config.deck[currentIndex].id,
                    now + if (config.intervalMinutes == ONE_DAY_MINUTES) {
                        nextDelay(config.intervalMinutes, now)
                    } else {
                        config.intervalMinutes * MILLIS_PER_MINUTE
                    },
                    config.intervalMinutes,
                )
            }
            currentIndex = config.deck.indexOfFirst { it.id == playback.wordId }
            if (currentIndex < 0) return null
            return WidgetState(config, playback, config.deck[currentIndex], currentIndex)
        }

        private fun completeKnownCountdown(
            context: Context,
            pending: WidgetKnownCountdown,
            now: Long,
        ) {
            val playback = LiveWallpaperPreferences.readPlayback(context)
            val word = LiveWallpaperPreferences.readPreviewWord(context, pending.wordId)
            val before = LiveWallpaperPreferences.read(context)
            val oldIndex = before.deck.indexOfFirst { it.id == pending.wordId }

            // An explicit/manual playback change invalidates the deferred move.
            if (playback.wordId != pending.wordId || word == null || oldIndex < 0) {
                LiveWallpaperPreferences.clearWidgetKnownCountdown(context)
                cancelKnownCountdown(context)
                return
            }
            val committed = word.known ||
                LiveWallpaperPreferences.enqueueStateAction(
                    context,
                    word.id,
                    "known",
                    true,
                )
            if (!committed) return
            // Publish the durable state first. If the process stops between
            // these writes, an expired retry only repeats the idempotent
            // desired state instead of losing the user's tap.
            LiveWallpaperPreferences.clearWidgetKnownCountdown(context)
            cancelKnownCountdown(context)

            val remaining = LiveWallpaperPreferences.read(context)
            if (remaining.deck.isEmpty()) {
                LiveWallpaperPreferences.writePlayback(
                    context,
                    "",
                    0L,
                    before.intervalMinutes,
                    notifyWidget = false,
                )
                return
            }
            val nextIndex = if (remaining.excludeKnown) {
                // The learned entry was removed, so its old index now points
                // to the following entry (or wraps when it was last).
                if (oldIndex < remaining.deck.size) oldIndex else 0
            } else {
                val learnedIndex = remaining.deck.indexOfFirst { it.id == word.id }
                Math.floorMod(learnedIndex + 1, remaining.deck.size)
            }
            LiveWallpaperPreferences.writePlayback(
                context,
                remaining.deck[nextIndex].id,
                now + remaining.intervalMinutes * MILLIS_PER_MINUTE,
                remaining.intervalMinutes,
                notifyWidget = false,
            )
        }

        private fun persistPlayback(
            context: Context,
            wordId: String,
            deadlineMillis: Long,
            intervalMinutes: Int,
        ): LiveWallpaperPlayback {
            LiveWallpaperPreferences.writePlayback(
                context,
                wordId,
                deadlineMillis,
                intervalMinutes,
                notifyWidget = false,
            )
            return LiveWallpaperPlayback(wordId, deadlineMillis, intervalMinutes)
        }

        private fun scheduleRotation(context: Context, deadlineMillis: Long, now: Long) {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
            val remaining = (deadlineMillis - now).coerceAtLeast(1_000L)
            val triggerAt = SystemClock.elapsedRealtime() + remaining
            scheduleTimerBoundary(alarmManager, triggerAt, rotationIntent(context))
        }

        private fun scheduleTimerWarning(context: Context, deadlineMillis: Long, now: Long) {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
            val warningAtMillis = deadlineMillis - TIMER_WARNING_THRESHOLD_MILLIS
            if (warningAtMillis <= now || warningAtMillis >= deadlineMillis) {
                alarmManager.cancel(timerWarningIntent(context))
                return
            }
            val triggerAt = SystemClock.elapsedRealtime() + (warningAtMillis - now)
            scheduleTimerBoundary(alarmManager, triggerAt, timerWarningIntent(context))
        }

        private fun scheduleKnownCountdown(
            context: Context,
            deadlineMillis: Long,
            now: Long,
        ) {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
            val remaining = (deadlineMillis - now).coerceAtLeast(1L)
            val displayedSeconds = (remaining + 999L) / 1_000L
            val nextDisplayedRemaining = (displayedSeconds - 1L).coerceAtLeast(0L) * 1_000L
            val delay = (remaining - nextDisplayedRemaining).coerceAtLeast(1L)
            scheduleTimerBoundary(
                alarmManager,
                SystemClock.elapsedRealtime() + delay,
                knownCountdownIntent(context),
            )
        }

        private fun scheduleTimerBoundary(
            alarmManager: AlarmManager,
            triggerAtElapsedMillis: Long,
            operation: PendingIntent,
        ) {
            // The timer only needs to redraw while the display is awake, so the
            // exact path deliberately remains non-wakeup. If the screen is off,
            // Android delivers the overdue boundary on the next wake and
            // resolveState() advances exactly one word before rendering.
            val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                runCatching { alarmManager.canScheduleExactAlarms() }.getOrDefault(false)
            if (exactAllowed) {
                val scheduled = runCatching {
                    alarmManager.setExact(
                        AlarmManager.ELAPSED_REALTIME,
                        triggerAtElapsedMillis,
                        operation,
                    )
                }.isSuccess
                if (scheduled) return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Android 12+ fresh installs require the user-controlled
                // Alarms & reminders special access for exact delivery. Keep a
                // no-crash, non-wakeup fallback until the user grants it.
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME,
                    triggerAtElapsedMillis,
                    operation,
                )
            } else {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME,
                    triggerAtElapsedMillis,
                    operation,
                )
            }
        }

        /**
         * Advances the visual stick timer in a small number of coarse steps.
         *
         * A plain [AlarmManager.set] alarm is freely batched on recent Android
         * releases. That is fine for background bookkeeping, but not for a
         * determinate AppWidget progress bar: the host-side Chronometer keeps
         * counting while the delayed broadcast leaves the bar frozen. Use the
         * same exact-when-authorized boundary path as rotation and warning so
         * an awake Galaxy/LockStar host receives each visual step on time. The
         * alarm type remains ELAPSED_REALTIME (never *_WAKEUP), and the small
         * fixed number of steps preserves the low-frequency power policy.
         */
        private fun scheduleProgressTick(
            context: Context,
            deadlineMillis: Long,
            intervalMinutes: Int,
            now: Long,
        ) {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
            val remaining = deadlineMillis - now
            val intervalMillis = intervalMinutes * MILLIS_PER_MINUTE
            val tickMillis = (intervalMillis / TIMER_PROGRESS_SEGMENTS).coerceIn(
                MIN_PROGRESS_TICK_MILLIS,
                MAX_PROGRESS_TICK_MILLIS,
            )
            if (remaining <= tickMillis) {
                alarmManager.cancel(progressTickIntent(context))
                return
            }
            scheduleTimerBoundary(
                alarmManager,
                SystemClock.elapsedRealtime() + tickMillis,
                progressTickIntent(context),
            )
        }

        private fun cancelRotation(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                ?.cancel(rotationIntent(context))
        }

        private fun cancelProgressTick(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                ?.cancel(progressTickIntent(context))
        }

        private fun cancelTimerWarning(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                ?.cancel(timerWarningIntent(context))
        }

        private fun cancelKnownCountdown(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                ?.cancel(knownCountdownIntent(context))
        }

        private fun rotationIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                ROTATION_REQUEST_CODE,
                Intent(context, StarlightWordWidgetProvider::class.java).apply {
                    action = ACTION_ROTATE
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun progressTickIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                PROGRESS_REQUEST_CODE,
                Intent(context, StarlightWordWidgetProvider::class.java).apply {
                    action = ACTION_PROGRESS_TICK
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun timerWarningIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                WARNING_REQUEST_CODE,
                Intent(context, StarlightWordWidgetProvider::class.java).apply {
                    action = ACTION_TIMER_WARNING
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun knownCountdownIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                KNOWN_COUNTDOWN_REQUEST_CODE,
                Intent(context, StarlightWordWidgetProvider::class.java).apply {
                    action = ACTION_KNOWN_COUNTDOWN
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun intervalLabel(intervalMinutes: Int): String = when (intervalMinutes) {
            60 -> "1시간"
            180 -> "3시간"
            ONE_DAY_MINUTES -> "하루"
            else -> "${intervalMinutes}분"
        }

        private fun wordSlot(intervalMinutes: Int, now: Long): Long {
            if (intervalMinutes != ONE_DAY_MINUTES) {
                return now / (intervalMinutes * MILLIS_PER_MINUTE)
            }
            val calendar = Calendar.getInstance().apply { timeInMillis = now }
            return civilDayNumber(
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH),
            )
        }

        private fun nextDelay(intervalMinutes: Int, now: Long): Long {
            if (intervalMinutes == ONE_DAY_MINUTES) {
                val nextMidnight = Calendar.getInstance().apply {
                    timeInMillis = now
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                    add(Calendar.DAY_OF_YEAR, 1)
                }.timeInMillis
                return (nextMidnight - now).coerceAtLeast(1_000L)
            }
            val intervalMillis = intervalMinutes * MILLIS_PER_MINUTE
            val remainder = now % intervalMillis
            return if (remainder == 0L) intervalMillis else intervalMillis - remainder
        }

        private fun civilDayNumber(year: Int, month: Int, day: Int): Long {
            val adjustedYear = year - if (month <= 2) 1 else 0
            val era = Math.floorDiv(adjustedYear, 400)
            val yearOfEra = adjustedYear - era * 400
            val adjustedMonth = month + if (month > 2) -3 else 9
            val dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
            val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097L + dayOfEra
        }
    }
}

/** Home-launcher-only component with direct Flutter detail navigation. */
class StarlightHomeWordWidgetProvider : StarlightWordWidgetProvider() {
    override val rendersHomeScreenSurface: Boolean = true
}
