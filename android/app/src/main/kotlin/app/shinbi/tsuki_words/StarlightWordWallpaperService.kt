package app.shinbi.tsuki_words

import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.service.wallpaper.WallpaperService
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.view.SurfaceHolder
import java.util.Calendar
import java.util.Locale
import java.util.Random
import kotlin.math.sin
import kotlin.math.min

/** Battery-conscious, fully offline live wallpaper for the synchronized deck. */
class StarlightWordWallpaperService : WallpaperService() {
    private companion object {
        const val ONE_DAY_MINUTES = 24 * 60
        const val MILLIS_PER_MINUTE = 60_000L
    }

    private lateinit var japaneseTypeface: Typeface
    private lateinit var koreanTypeface: Typeface

    override fun onCreate() {
        super.onCreate()
        japaneseTypeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        koreanTypeface = Typeface.create("sans-serif", Typeface.NORMAL)
    }

    override fun onCreateEngine(): Engine = StarlightEngine()

    private inner class StarlightEngine : Engine() {
        private val handler = Handler(Looper.getMainLooper())
        private val preferences = LiveWallpaperPreferences.preferences(this@StarlightWordWallpaperService)
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
        private val paragraphPaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
        private val powerManager by lazy {
            getSystemService(PowerManager::class.java)
        }

        private var visible = false
        private var surfaceReady = false
        private var destroyed = false
        private var drawPosted = false
        private var configRefreshPosted = false
        private var xPixelOffset = 0
        private var yPixelOffset = 0
        private var motionEnabled = true
        private var cachedConfig =
            LiveWallpaperPreferences.read(this@StarlightWordWallpaperService)
        private var playback =
            LiveWallpaperPreferences.readPlayback(this@StarlightWordWallpaperService)

        private val rotationRunnable = object : Runnable {
            override fun run() {
                if (!canDraw()) return
                drawFrame()
                scheduleNextRotation()
                scheduleTicker()
            }
        }
        private val tickerRunnable = object : Runnable {
            override fun run() {
                if (!canDraw() || !isScreenInteractive()) return
                drawFrame()
                scheduleTicker()
            }
        }
        private val drawRunnable = Runnable {
            drawPosted = false
            if (canDraw()) drawFrame()
        }
        private val configRefreshRunnable = Runnable {
            configRefreshPosted = false
            if (destroyed) return@Runnable
            cachedConfig = LiveWallpaperPreferences.read(this@StarlightWordWallpaperService)
            playback = LiveWallpaperPreferences.readPlayback(this@StarlightWordWallpaperService)
            requestDraw()
            scheduleNextRotation()
            scheduleTicker()
        }
        private val preferenceListener =
            SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
                handler.post {
                    if (destroyed) return@post
                    // One apply() changes several keys. Refresh the JSON deck
                    // only once on the next main-loop turn instead of once per key.
                    if (!configRefreshPosted) {
                        configRefreshPosted = true
                        handler.post(configRefreshRunnable)
                    }
                }
            }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            motionEnabled = readAnimationsEnabled()
            setOffsetNotificationsEnabled(true)
            preferences.registerOnSharedPreferenceChangeListener(preferenceListener)
        }

        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            handler.removeCallbacks(rotationRunnable)
            handler.removeCallbacks(tickerRunnable)
            if (isVisible) {
                motionEnabled = readAnimationsEnabled()
                requestDraw()
                scheduleNextRotation()
                scheduleTicker()
            } else {
                handler.removeCallbacks(drawRunnable)
                drawPosted = false
            }
        }

        override fun onSurfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            surfaceReady = width > 0 && height > 0
            requestDraw()
            scheduleNextRotation()
            scheduleTicker()
        }

        override fun onSurfaceRedrawNeeded(holder: SurfaceHolder) {
            super.onSurfaceRedrawNeeded(holder)
            requestDraw()
            scheduleTicker()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            surfaceReady = false
            handler.removeCallbacks(rotationRunnable)
            handler.removeCallbacks(tickerRunnable)
            handler.removeCallbacks(drawRunnable)
            drawPosted = false
            super.onSurfaceDestroyed(holder)
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xOffsetStep: Float,
            yOffsetStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            this.xPixelOffset = xPixelOffset
            this.yPixelOffset = yPixelOffset
            requestDraw(16L)
        }

        override fun onDestroy() {
            destroyed = true
            visible = false
            surfaceReady = false
            preferences.unregisterOnSharedPreferenceChangeListener(preferenceListener)
            handler.removeCallbacksAndMessages(null)
            super.onDestroy()
        }

        private fun canDraw(): Boolean =
            !destroyed && visible && surfaceReady && surfaceHolder.surface.isValid

        private fun requestDraw(delayMillis: Long = 0L) {
            if (!canDraw() || drawPosted) return
            drawPosted = true
            handler.postDelayed(drawRunnable, delayMillis)
        }

        private fun scheduleNextRotation() {
            handler.removeCallbacks(rotationRunnable)
            if (!canDraw()) return
            val config = cachedConfig
            if (!config.enabled || config.deck.isEmpty()) return
            val now = System.currentTimeMillis()
            val current = ensurePlayback(config, now) ?: return
            handler.postDelayed(
                rotationRunnable,
                (current.deadlineMillis - now).coerceAtLeast(1L) + 100L,
            )
        }

        private fun scheduleTicker() {
            handler.removeCallbacks(tickerRunnable)
            if (!canDraw() || !isScreenInteractive()) return
            val config = cachedConfig
            if (!config.enabled || config.deck.isEmpty()) return
            val now = System.currentTimeMillis()
            ensurePlayback(config, now) ?: return
            handler.postDelayed(tickerRunnable, 1_000L - (now % 1_000L) + 20L)
        }

        private fun isScreenInteractive(): Boolean = powerManager?.isInteractive == true

        private fun ensurePlayback(
            config: LiveWallpaperConfig,
            nowMillis: Long,
        ): LiveWallpaperPlayback? {
            if (config.deck.isEmpty()) return null
            var currentIndex = config.deck.indexOfFirst { it.id == playback.wordId }
            val mustReset =
                currentIndex < 0 ||
                    playback.deadlineMillis <= 0L ||
                    playback.intervalMinutes != config.intervalMinutes
            if (mustReset) {
                currentIndex = Math.floorMod(
                    wordSlot(config.intervalMinutes, nowMillis),
                    config.deck.size.toLong(),
                ).toInt()
                return updatePlayback(
                    config.deck[currentIndex].id,
                    nowMillis + nextDelay(config.intervalMinutes, nowMillis),
                    config.intervalMinutes,
                )
            }
            if (nowMillis < playback.deadlineMillis) return playback

            val steps = if (config.intervalMinutes == ONE_DAY_MINUTES) {
                val previousDay = wordSlot(config.intervalMinutes, playback.deadlineMillis - 1L)
                val currentDay = wordSlot(config.intervalMinutes, nowMillis)
                (currentDay - previousDay).coerceAtLeast(1L)
            } else {
                1L + (nowMillis - playback.deadlineMillis) /
                    (config.intervalMinutes * MILLIS_PER_MINUTE)
            }
            currentIndex = Math.floorMod(currentIndex.toLong() + steps, config.deck.size.toLong())
                .toInt()
            val nextDeadline = if (config.intervalMinutes == ONE_DAY_MINUTES) {
                nowMillis + nextDelay(config.intervalMinutes, nowMillis)
            } else {
                playback.deadlineMillis + steps * config.intervalMinutes * MILLIS_PER_MINUTE
            }
            return updatePlayback(
                config.deck[currentIndex].id,
                nextDeadline,
                config.intervalMinutes,
            )
        }

        private fun updatePlayback(
            wordId: String,
            deadlineMillis: Long,
            intervalMinutes: Int,
        ): LiveWallpaperPlayback {
            playback = LiveWallpaperPlayback(wordId, deadlineMillis, intervalMinutes)
            LiveWallpaperPreferences.writePlayback(
                this@StarlightWordWallpaperService,
                wordId,
                deadlineMillis,
                intervalMinutes,
            )
            return playback
        }

        private fun drawFrame() {
            val holder = surfaceHolder
            if (!holder.surface.isValid) return
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas() ?: return
                render(canvas, cachedConfig)
            } catch (_: RuntimeException) {
                // Surface replacement during lock/unlock is expected on some One UI versions.
            } finally {
                canvas?.let { lockedCanvas ->
                    runCatching { holder.unlockCanvasAndPost(lockedCanvas) }
                }
            }
        }

        private fun render(canvas: Canvas, config: LiveWallpaperConfig) {
            val canvasWidth = canvas.width.toFloat()
            val canvasHeight = canvas.height.toFloat()
            if (canvasWidth <= 0f || canvasHeight <= 0f) return

            val displayMetrics = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                displayContext?.resources?.displayMetrics ?: resources.displayMetrics
            } else {
                resources.displayMetrics
            }
            val viewportWidth = min(canvasWidth, displayMetrics.widthPixels.toFloat())
            val viewportHeight = min(canvasHeight, displayMetrics.heightPixels.toFloat())
            val viewportLeft = (-xPixelOffset).toFloat()
                .coerceIn(0f, (canvasWidth - viewportWidth).coerceAtLeast(0f))
            val viewportTop = (-yPixelOffset).toFloat()
                .coerceIn(0f, (canvasHeight - viewportHeight).coerceAtLeast(0f))
            val viewport = RectF(
                viewportLeft,
                viewportTop,
                viewportLeft + viewportWidth,
                viewportTop + viewportHeight,
            )

            val isNight = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
            drawBackground(canvas, canvasWidth, canvasHeight, isNight)

            if (!config.enabled) {
                drawPlaceholder(canvas, viewport, "앱에서 잠금화면 단어를 켜주세요")
                return
            }
            if (config.deck.isEmpty()) {
                drawPlaceholder(canvas, viewport, "표시할 단어를 먼저 선택해 주세요")
                return
            }

            val now = System.currentTimeMillis()
            val current = ensurePlayback(config, now) ?: return
            val wordIndex = config.deck.indexOfFirst { it.id == current.wordId }
                .takeIf { it >= 0 } ?: return
            drawStars(canvas, canvasWidth, canvasHeight, now)
            drawWordCard(
                canvas,
                viewport,
                config,
                config.deck[wordIndex],
                wordIndex,
                current.deadlineMillis,
                now,
            )
        }

        private fun drawBackground(
            canvas: Canvas,
            width: Float,
            height: Float,
            isNight: Boolean,
        ) {
            fillPaint.style = Paint.Style.FILL
            val top = if (isNight) Color.rgb(8, 15, 31) else Color.rgb(18, 31, 57)
            val bottom = if (isNight) Color.rgb(18, 26, 52) else Color.rgb(30, 43, 77)
            fillPaint.shader = LinearGradient(0f, 0f, width, height, top, bottom, Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, width, height, fillPaint)
            fillPaint.shader = RadialGradient(
                width * 0.76f,
                height * 0.18f,
                min(width, height) * 0.7f,
                intArrayOf(Color.argb(58, 89, 107, 165), Color.TRANSPARENT),
                null,
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width, height, fillPaint)
            fillPaint.shader = null
        }

        private fun drawStars(canvas: Canvas, width: Float, height: Float, nowMillis: Long) {
            fillPaint.style = Paint.Style.FILL
            val random = Random(0x53544152L)
            val scale = min(width, height) / 400f
            val animated = isScreenInteractive() && motionEnabled
            val elapsedSeconds = nowMillis / 1_000.0
            repeat(42) { index ->
                val x = random.nextFloat() * width
                val y = random.nextFloat() * height
                val baseRadius = (if (index % 9 == 0) 1.75f else 0.75f) * scale
                val baseAlpha = 70 + random.nextInt(75)
                val starPhase = random.nextDouble() * Math.PI * 2.0
                val wave = if (animated) {
                    sin(elapsedSeconds * 0.32 + starPhase).toFloat()
                } else {
                    0f
                }
                val radius = baseRadius * (1f + wave * 0.055f)
                val alpha = (baseAlpha + wave * 11f).toInt().coerceIn(35, 170)
                fillPaint.color = Color.argb(alpha, 255, 222, 137)
                canvas.drawCircle(x, y, radius, fillPaint)
                if (index % 9 == 0) {
                    fillPaint.strokeWidth = 0.7f * scale
                    canvas.drawLine(x - radius * 2.4f, y, x + radius * 2.4f, y, fillPaint)
                    canvas.drawLine(x, y - radius * 2.4f, x, y + radius * 2.4f, fillPaint)
                }
            }
        }

        private fun readAnimationsEnabled(): Boolean = runCatching {
            Settings.Global.getFloat(
                contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) > 0f
        }.getOrDefault(true)

        private fun drawPlaceholder(canvas: Canvas, viewport: RectF, message: String) {
            val scale = (min(viewport.width(), viewport.height()) / 390f).coerceIn(0.8f, 4f)
            val centerX = viewport.centerX()
            val centerY = viewport.top + viewport.height() * 0.46f
            drawFourPointStar(canvas, centerX, centerY - 74f * scale, 17f * scale)
            textPaint.apply {
                shader = null
                color = Color.rgb(246, 220, 151)
                typeface = koreanTypeface
                textAlign = Paint.Align.CENTER
                textSize = 17f * scale
            }
            canvas.drawText(message, centerX, centerY, textPaint)
        }

        private fun drawWordCard(
            canvas: Canvas,
            viewport: RectF,
            config: LiveWallpaperConfig,
            word: LiveWallpaperWord,
            wordIndex: Int,
            deadlineMillis: Long,
            nowMillis: Long,
        ) {
            val portrait = viewport.height() >= viewport.width()
            val scale = (min(viewport.width(), viewport.height()) / 390f).coerceIn(0.8f, 4f)
            val panelWidth = if (portrait) {
                viewport.width() * 0.88f
            } else {
                min(viewport.width() * 0.74f, viewport.height() * 1.55f)
            }
            val panelLeft = viewport.centerX() - panelWidth / 2f
            val panelRight = viewport.centerX() + panelWidth / 2f
            val contentCard = RectF(
                panelLeft,
                viewport.top + viewport.height() * if (portrait) 0.27f else 0.12f,
                panelRight,
                viewport.top + viewport.height() * if (portrait) 0.525f else 0.64f,
            )
            // Samsung places its unlock affordance around the middle-lower portion
            // of the lock screen. Keep a deliberate clear band between both cards.
            val timerCard = RectF(
                panelLeft,
                viewport.top + viewport.height() * if (portrait) 0.69f else 0.70f,
                panelRight,
                viewport.top + viewport.height() * if (portrait) 0.79f else 0.88f,
            )
            drawPanel(canvas, contentCard, scale)
            drawPanel(canvas, timerCard, scale)
            val padding = 24f * scale

            textPaint.apply {
                shader = null
                color = Color.argb(172, 204, 212, 233)
                typeface = koreanTypeface
                textAlign = Paint.Align.LEFT
                textSize = 10f * scale
            }
            canvas.drawText(
                "${wordIndex + 1} / ${config.deck.size}",
                contentCard.left + padding,
                contentCard.top + padding + 3f * scale,
                textPaint,
            )

            val levelLabel = mapOf("n5" to "1", "n4" to "2", "n3" to "3", "n2" to "4", "n1" to "5")[word.level].orEmpty()
            if (levelLabel.isNotEmpty()) {
                textPaint.apply {
                    shader = null
                    color = Color.rgb(247, 219, 145)
                    typeface = koreanTypeface
                    textAlign = Paint.Align.RIGHT
                    textSize = 11f * scale
                }
                canvas.drawText(
                    "데모 $levelLabel",
                    contentCard.right - padding,
                    contentCard.top + padding + 4f * scale,
                    textPaint,
                )
            }

            val bodyRegion = RectF(
                contentCard.left + padding,
                contentCard.top + 43f * scale,
                contentCard.right - padding,
                contentCard.bottom - 15f * scale,
            )
            val reading = word.reading.trim()
            val showReading = config.showReading && reading.isNotEmpty()
            if (showReading) {
                textPaint.apply {
                    shader = null
                    color = Color.rgb(203, 211, 232)
                    typeface = japaneseTypeface
                    textAlign = Paint.Align.CENTER
                    textSize = 15f * scale
                }
                fitText(reading, bodyRegion.width(), 10f * scale)
            }
            val readingMetrics = textPaint.fontMetrics
            val readingHeight = if (showReading) {
                readingMetrics.descent - readingMetrics.ascent
            } else {
                0f
            }

            textPaint.apply {
                shader = null
                color = Color.WHITE
                typeface = japaneseTypeface
                textAlign = Paint.Align.CENTER
                textSize = 48f * scale
            }
            fitText(word.word, bodyRegion.width(), 24f * scale)
            val wordMetrics = textPaint.fontMetrics
            val wordHeight = wordMetrics.descent - wordMetrics.ascent

            val meaning = word.meaning.trim()
            val showMeaning = config.showMeaning && meaning.isNotEmpty()
            val meaningLayout = if (showMeaning) {
                paragraphPaint.apply {
                    color = Color.rgb(239, 241, 248)
                    typeface = koreanTypeface
                    textAlign = Paint.Align.LEFT
                    textSize = 17f * scale
                }
                val paragraphWidth = bodyRegion.width().toInt().coerceAtLeast(1)
                StaticLayout.Builder
                    .obtain(meaning, 0, meaning.length, paragraphPaint, paragraphWidth)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER)
                    .setIncludePad(false)
                    .setLineSpacing(0f, 1.08f)
                    .setMaxLines(3)
                    .setEllipsize(TextUtils.TruncateAt.END)
                    .build()
            } else {
                null
            }

            val firstGap = if (showReading) 7f * scale else 0f
            val secondGap = if (showMeaning) 9f * scale else 0f
            val contentHeight =
                readingHeight + firstGap + wordHeight + secondGap +
                    (meaningLayout?.height?.toFloat() ?: 0f)
            var cursorY = bodyRegion.centerY() - contentHeight / 2f

            if (showReading) {
                textPaint.apply {
                    shader = null
                    color = Color.rgb(203, 211, 232)
                    typeface = japaneseTypeface
                    textAlign = Paint.Align.CENTER
                    textSize = 15f * scale
                }
                fitText(reading, bodyRegion.width(), 10f * scale)
                val metrics = textPaint.fontMetrics
                canvas.drawText(
                    reading,
                    bodyRegion.centerX(),
                    cursorY - metrics.ascent,
                    textPaint,
                )
                cursorY += metrics.descent - metrics.ascent + firstGap
            }

            textPaint.apply {
                shader = null
                color = Color.WHITE
                typeface = japaneseTypeface
                textAlign = Paint.Align.CENTER
                textSize = 48f * scale
            }
            fitText(word.word, bodyRegion.width(), 24f * scale)
            val fittedWordMetrics = textPaint.fontMetrics
            canvas.drawText(
                word.word,
                bodyRegion.centerX(),
                cursorY - fittedWordMetrics.ascent,
                textPaint,
            )
            cursorY += fittedWordMetrics.descent - fittedWordMetrics.ascent + secondGap

            meaningLayout?.let { layout ->
                // ALIGN_CENTER aligns every paragraph line inside layout.width.
                // Matching the layout width to this symmetric region and then
                // translating from its exact center fixes both one- and multi-line
                // meanings without relying on glyph-specific visual offsets.
                val paragraphRegion = RectF(
                    bodyRegion.left,
                    cursorY,
                    bodyRegion.right,
                    (cursorY + layout.height).coerceAtMost(bodyRegion.bottom),
                )
                val paragraphTop = paragraphRegion.centerY() - layout.height / 2f
                canvas.save()
                canvas.clipRect(paragraphRegion)
                canvas.translate(
                    paragraphRegion.centerX() - layout.width / 2f,
                    paragraphTop,
                )
                layout.draw(canvas)
                canvas.restore()
            }

            drawTimer(
                canvas,
                timerCard,
                config.intervalMinutes,
                deadlineMillis,
                nowMillis,
                scale,
            )
        }

        private fun drawTimer(
            canvas: Canvas,
            panel: RectF,
            intervalMinutes: Int,
            deadlineMillis: Long,
            nowMillis: Long,
            scale: Float,
        ) {
            val horizontalPadding = 20f * scale
            val headerBaseline = panel.top + 22f * scale
            textPaint.apply {
                shader = null
                color = Color.rgb(247, 219, 145)
                typeface = koreanTypeface
                textAlign = Paint.Align.LEFT
                textSize = 10.5f * scale
            }
            canvas.drawText(
                "다음 단어",
                panel.left + horizontalPadding,
                headerBaseline,
                textPaint,
            )
            textPaint.apply {
                color = Color.argb(170, 204, 212, 233)
                textAlign = Paint.Align.RIGHT
                textSize = 9f * scale
            }
            canvas.drawText(
                intervalLabel(intervalMinutes),
                panel.right - horizontalPadding,
                headerBaseline,
                textPaint,
            )

            textPaint.apply {
                color = Color.WHITE
                textAlign = Paint.Align.CENTER
                textSize = 22f * scale
            }
            canvas.drawText(
                remainingLabel(deadlineMillis, nowMillis),
                panel.centerX(),
                panel.centerY() + 9f * scale,
                textPaint,
            )

            val track = RectF(
                panel.left + horizontalPadding,
                panel.bottom - 18f * scale,
                panel.right - horizontalPadding,
                panel.bottom - 13f * scale,
            )
            val progress = timerProgress(intervalMinutes, deadlineMillis, nowMillis)
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.argb(70, 205, 214, 236)
            canvas.drawRoundRect(track, track.height() / 2f, track.height() / 2f, fillPaint)
            if (progress > 0f) {
                val progressRect = RectF(
                    track.left,
                    track.top,
                    track.left + track.width() * progress,
                    track.bottom,
                )
                fillPaint.color = Color.rgb(246, 210, 119)
                canvas.drawRoundRect(
                    progressRect,
                    track.height() / 2f,
                    track.height() / 2f,
                    fillPaint,
                )
            }
        }

        private fun drawPanel(canvas: Canvas, panel: RectF, scale: Float) {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.argb(224, 25, 36, 64)
            canvas.drawRoundRect(panel, 25f * scale, 25f * scale, fillPaint)
            fillPaint.style = Paint.Style.STROKE
            fillPaint.strokeWidth = 1.15f * scale
            fillPaint.color = Color.argb(112, 255, 221, 135)
            canvas.drawRoundRect(panel, 25f * scale, 25f * scale, fillPaint)
            fillPaint.style = Paint.Style.FILL
        }

        private fun remainingLabel(deadlineMillis: Long, nowMillis: Long): String {
            val totalSeconds = ((deadlineMillis - nowMillis).coerceAtLeast(0L) + 999L) / 1_000L
            val hours = totalSeconds / 3_600L
            val minutes = (totalSeconds % 3_600L) / 60L
            val seconds = totalSeconds % 60L
            return if (hours > 0L) {
                String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format(Locale.ROOT, "%02d:%02d", minutes, seconds)
            }
        }

        private fun timerProgress(
            intervalMinutes: Int,
            deadlineMillis: Long,
            nowMillis: Long,
        ): Float {
            val intervalMillis = if (intervalMinutes == ONE_DAY_MINUTES) {
                val previousMidnight = Calendar.getInstance().apply {
                    timeInMillis = deadlineMillis
                    add(Calendar.DAY_OF_YEAR, -1)
                }.timeInMillis
                (deadlineMillis - previousMidnight).coerceAtLeast(MILLIS_PER_MINUTE)
            } else {
                intervalMinutes * MILLIS_PER_MINUTE
            }
            val remaining = (deadlineMillis - nowMillis).coerceIn(0L, intervalMillis)
            return (1.0 - remaining.toDouble() / intervalMillis.toDouble())
                .toFloat()
                .coerceIn(0f, 1f)
        }

        private fun intervalLabel(intervalMinutes: Int): String = when (intervalMinutes) {
            60 -> "1시간마다"
            180 -> "3시간마다"
            ONE_DAY_MINUTES -> "하루마다"
            else -> "${intervalMinutes}분마다"
        }

        private fun fitText(text: String, maxWidth: Float, minimumSize: Float) {
            val measuredWidth = textPaint.measureText(text)
            if (measuredWidth > maxWidth && measuredWidth > 0f) {
                textPaint.textSize =
                    (textPaint.textSize * maxWidth / measuredWidth).coerceAtLeast(minimumSize)
            }
        }

        /** Returns a local-calendar day for "하루", and epoch intervals otherwise. */
        private fun wordSlot(intervalMinutes: Int, nowMillis: Long): Long {
            if (intervalMinutes != ONE_DAY_MINUTES) {
                return nowMillis / (intervalMinutes * MILLIS_PER_MINUTE)
            }
            val calendar = Calendar.getInstance().apply { timeInMillis = nowMillis }
            return civilDayNumber(
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH),
            )
        }

        /** Calculates the exact next local midnight for the "하루" interval. */
        private fun nextDelay(intervalMinutes: Int, nowMillis: Long): Long {
            if (intervalMinutes == ONE_DAY_MINUTES) {
                val nextMidnight = Calendar.getInstance().apply {
                    timeInMillis = nowMillis
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                    add(Calendar.DAY_OF_YEAR, 1)
                }.timeInMillis
                return (nextMidnight - nowMillis).coerceAtLeast(1_000L)
            }
            val intervalMillis = intervalMinutes * MILLIS_PER_MINUTE
            val remainder = nowMillis % intervalMillis
            return if (remainder == 0L) intervalMillis else intervalMillis - remainder
        }

        /** Monotonic Gregorian day number derived from local Calendar fields. */
        private fun civilDayNumber(year: Int, month: Int, day: Int): Long {
            val adjustedYear = year - if (month <= 2) 1 else 0
            val era = Math.floorDiv(adjustedYear, 400)
            val yearOfEra = adjustedYear - era * 400
            val adjustedMonth = month + if (month > 2) -3 else 9
            val dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
            val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097L + dayOfEra
        }

        private fun drawFourPointStar(canvas: Canvas, x: Float, y: Float, radius: Float) {
            fillPaint.color = Color.rgb(250, 211, 112)
            val path = android.graphics.Path().apply {
                moveTo(x, y - radius)
                lineTo(x + radius * 0.24f, y - radius * 0.24f)
                lineTo(x + radius, y)
                lineTo(x + radius * 0.24f, y + radius * 0.24f)
                lineTo(x, y + radius)
                lineTo(x - radius * 0.24f, y + radius * 0.24f)
                lineTo(x - radius, y)
                lineTo(x - radius * 0.24f, y - radius * 0.24f)
                close()
            }
            canvas.drawPath(path, fillPaint)
        }
    }
}
