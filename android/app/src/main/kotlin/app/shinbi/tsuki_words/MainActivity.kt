package app.shinbi.tsuki_words

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var japaneseTtsChannel: JapaneseTtsChannel? = null
    private var liveWallpaperChannel: LiveWallpaperChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        japaneseTtsChannel = JapaneseTtsChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        liveWallpaperChannel = LiveWallpaperChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        liveWallpaperChannel?.dispose()
        liveWallpaperChannel = null
        japaneseTtsChannel?.dispose()
        japaneseTtsChannel = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        liveWallpaperChannel?.handleIntent(intent)
    }

    override fun onStop() {
        japaneseTtsChannel?.stopForLifecycle()
        super.onStop()
    }
}

/**
 * Japanese-only bridge around Android's built-in TextToSpeech engine.
 *
 * The engine is initialized lazily and is always pinned to Locale.JAPAN. A
 * speak call stays pending until playback finishes, which lets Flutter surface
 * synthesis/playback failures instead of treating a successfully queued item
 * as a successfully played item.
 */
private class JapaneseTtsChannel(
    context: Context,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler, TextToSpeech.OnInitListener {
    private enum class State { IDLE, INITIALIZING, READY, FAILED, DISPOSED }

    private data class PendingAction(
        val result: MethodChannel.Result,
        val run: (TextToSpeech) -> Unit,
    )

    companion object {
        private const val CHANNEL_NAME = "app.shinbi.tsuki_words/japanese_tts"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val waitingForEngine = mutableListOf<PendingAction>()

    private var state = State.IDLE
    private var engine: TextToSpeech? = null
    private var activeUtteranceId: String? = null
    private var activeResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                when {
                    text.isEmpty() -> result.error("tts_invalid_text", "재생할 일본어가 없습니다.", null)
                    text.length > TextToSpeech.getMaxSpeechInputLength() -> result.error("tts_text_too_long", "문장이 너무 깁니다.", null)
                    else -> speakWithAndroid(text, result)
                }
            }
            "stop" -> stop(result)
            "checkAvailability" -> withReadyEngine(result) {
                result.success(mapOf("status" to "available", "engine" to "android"))
            }
            else -> result.notImplemented()
        }
    }

    private fun speakWithAndroid(text: String, result: MethodChannel.Result) {

        withReadyEngine(result) { readyEngine ->
            // This bridge intentionally uses one current utterance. A new tap
            // replaces older speech and completes the replaced Dart Future.
            cancelActiveUtterance("cancelled")
            readyEngine.stop()

            val utteranceId = UUID.randomUUID().toString()
            activeUtteranceId = utteranceId
            activeResult = result
            val queueResult = readyEngine.speak(
                text,
                TextToSpeech.QUEUE_FLUSH,
                null,
                utteranceId,
            )
            if (queueResult == TextToSpeech.ERROR) {
                activeUtteranceId = null
                activeResult = null
                result.error("tts_speak_failed", "음성 합성을 시작하지 못했습니다.", null)
            }
        }
    }

    private fun stop(result: MethodChannel.Result) {
        val stopResult = engine?.stop() ?: TextToSpeech.SUCCESS
        cancelActiveUtterance("stopped")
        // A stop pressed while the engine is still initializing must also
        // cancel queued speech; otherwise that speech would unexpectedly
        // start as soon as initialization finishes.
        waitingForEngine.forEach {
            it.result.success(mapOf("status" to "cancelled"))
        }
        waitingForEngine.clear()
        if (stopResult == TextToSpeech.ERROR) {
            result.error("tts_stop_failed", "음성 재생을 멈추지 못했습니다.", null)
        } else {
            result.success(mapOf("status" to "stopped"))
        }
    }

    private fun withReadyEngine(
        result: MethodChannel.Result,
        action: (TextToSpeech) -> Unit,
    ) {
        when (state) {
            State.READY -> engine?.let(action) ?: result.error(
                "tts_unavailable",
                "음성 합성 엔진을 사용할 수 없습니다.",
                null,
            )
            State.DISPOSED -> result.error(
                "tts_disposed",
                "음성 합성 기능이 종료되었습니다.",
                null,
            )
            State.IDLE, State.INITIALIZING, State.FAILED -> {
                waitingForEngine += PendingAction(result, action)
                if (state == State.IDLE || state == State.FAILED) initializeEngine()
            }
        }
    }

    private fun initializeEngine() {
        state = State.INITIALIZING
        try {
            engine = TextToSpeech(appContext, this)
        } catch (_: RuntimeException) {
            failInitialization(
                "tts_initialization_failed",
                "음성 합성 엔진을 초기화하지 못했습니다.",
            )
        }
    }

    override fun onInit(status: Int) {
        val readyEngine = engine
        if (status != TextToSpeech.SUCCESS || readyEngine == null) {
            failInitialization(
                "tts_initialization_failed",
                "음성 합성 엔진을 초기화하지 못했습니다.",
            )
            return
        }

        val languageAvailability = readyEngine.isLanguageAvailable(Locale.JAPAN)
        when (languageAvailability) {
            TextToSpeech.LANG_MISSING_DATA -> {
                failInitialization(
                    "tts_language_data_missing",
                    "일본어 음성 데이터가 설치되어 있지 않습니다.",
                )
                return
            }
            TextToSpeech.LANG_NOT_SUPPORTED -> {
                failInitialization(
                    "tts_language_not_supported",
                    "현재 음성 합성 엔진이 일본어를 지원하지 않습니다.",
                )
                return
            }
        }

        val languageResult = readyEngine.setLanguage(Locale.JAPAN)
        if (languageResult == TextToSpeech.LANG_MISSING_DATA) {
            failInitialization(
                "tts_language_data_missing",
                "일본어 음성 데이터가 설치되어 있지 않습니다.",
            )
            return
        }
        if (languageResult == TextToSpeech.LANG_NOT_SUPPORTED) {
            failInitialization(
                "tts_language_not_supported",
                "현재 음성 합성 엔진이 일본어를 지원하지 않습니다.",
            )
            return
        }
        readyEngine.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    finishUtterance(utteranceId) { pendingResult ->
                        pendingResult.success(
                            mapOf("status" to "completed", "engine" to "android"),
                        )
                    }
                }

                @Suppress("OVERRIDE_DEPRECATION")
                override fun onError(utteranceId: String?) {
                    reportPlaybackError(utteranceId, null)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    reportPlaybackError(utteranceId, errorCode)
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    finishUtterance(utteranceId) { pendingResult ->
                        pendingResult.success(mapOf("status" to "cancelled"))
                    }
                }
            },
        )

        state = State.READY
        val pending = waitingForEngine.toList()
        waitingForEngine.clear()
        pending.forEach { it.run(readyEngine) }
    }

    private fun reportPlaybackError(utteranceId: String?, errorCode: Int?) {
        finishUtterance(utteranceId) { pendingResult ->
            pendingResult.error(
                "tts_playback_failed",
                "일본어 음성을 재생하지 못했습니다.",
                errorCode,
            )
        }
    }

    private fun finishUtterance(
        utteranceId: String?,
        complete: (MethodChannel.Result) -> Unit,
    ) {
        mainHandler.post {
            if (utteranceId == null || utteranceId != activeUtteranceId) return@post
            val pendingResult = activeResult ?: return@post
            activeUtteranceId = null
            activeResult = null
            complete(pendingResult)
        }
    }

    private fun cancelActiveUtterance(status: String) {
        val pendingResult = activeResult ?: return
        activeUtteranceId = null
        activeResult = null
        pendingResult.success(mapOf("status" to status))
    }

    private fun failInitialization(code: String, message: String) {
        state = State.FAILED
        engine?.shutdown()
        engine = null
        val pending = waitingForEngine.toList()
        waitingForEngine.clear()
        pending.forEach { it.result.error(code, message, null) }
    }

    fun stopForLifecycle() {
        if (state == State.DISPOSED) return
        engine?.stop()
        cancelActiveUtterance("cancelled")
        waitingForEngine.forEach {
            it.result.success(mapOf("status" to "cancelled"))
        }
        waitingForEngine.clear()
    }

    fun dispose() {
        if (state == State.DISPOSED) return
        channel.setMethodCallHandler(null)
        cancelActiveUtterance("cancelled")
        waitingForEngine.forEach {
            it.result.error("tts_disposed", "음성 합성 기능이 종료되었습니다.", null)
        }
        waitingForEngine.clear()
        engine?.stop()
        engine?.shutdown()
        engine = null
        state = State.DISPOSED
    }
}
