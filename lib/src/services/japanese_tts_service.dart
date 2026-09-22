import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The outcome of a Japanese speech request.
///
/// Android's text-to-speech engine is asynchronous, so [completed] is only
/// returned after playback finishes. [cancelled] is a normal outcome when a
/// newer utterance replaces the current one or the caller explicitly stops it.
enum JapaneseTtsStatus {
  completed,
  cancelled,
  invalidText,
  unsupportedPlatform,
  unavailable,
  languageDataMissing,
  languageNotSupported,
  pitchAccentUnavailable,
  failed,
}

enum JapaneseVoiceEngine {
  android;

  String get label => switch (this) {
    JapaneseVoiceEngine.android => 'Android TTS',
  };
}

@immutable
class JapaneseTtsResult {
  const JapaneseTtsResult(this.status, {this.details, this.engine});

  final JapaneseTtsStatus status;
  final String? details;
  final JapaneseVoiceEngine? engine;

  bool get isSuccess => status == JapaneseTtsStatus.completed;
  bool get isCancelled => status == JapaneseTtsStatus.cancelled;

  /// Short Korean copy suitable for a snackbar or other inline feedback.
  String get userMessage => switch (status) {
    JapaneseTtsStatus.completed => '일본어 발음 재생을 마쳤어요.',
    JapaneseTtsStatus.cancelled => '일본어 발음 재생을 멈췄어요.',
    JapaneseTtsStatus.invalidText => '재생할 일본어가 없어요.',
    JapaneseTtsStatus.unsupportedPlatform => '일본어 음성 재생은 현재 Android에서만 지원해요.',
    JapaneseTtsStatus.unavailable => '기기에서 음성 합성 기능을 사용할 수 없어요.',
    JapaneseTtsStatus.languageDataMissing =>
      '기기의 TTS 설정에서 일본어 음성 데이터를 설치해 주세요.',
    JapaneseTtsStatus.languageNotSupported => '현재 음성 합성 엔진이 일본어를 지원하지 않아요.',
    JapaneseTtsStatus.pitchAccentUnavailable => '공개 데모는 악센트 지정 재생을 지원하지 않아요.',
    JapaneseTtsStatus.failed => '일본어 발음을 재생하지 못했어요.',
  };
}

abstract interface class JapaneseSpeechSynthesizer {
  Future<JapaneseTtsResult> speak(String text);

  Future<JapaneseTtsResult> stop();

  Future<JapaneseTtsResult> checkAvailability();
}

abstract interface class JapanesePitchAccentSynthesizer {
  Future<JapaneseTtsResult> speakPitchAccent(String reading, int accent);
}

/// Synthesizes a normal word request while preserving a known dictionary
/// reading and pitch accent when the selected engine supports it.
abstract interface class JapanesePitchAccentHintSynthesizer {
  Future<JapaneseTtsResult> speakWithPitchAccentHint(
    String text,
    String reading,
    int accent,
  );
}

/// Japanese-only bridge to Android's built-in `TextToSpeech` service.
///
/// The native side always configures `Locale.JAPAN`. There is deliberately no
/// locale parameter in this API, preventing callers from turning the bridge
/// into an unrestricted system TTS endpoint.
class JapaneseTtsService
    implements
        JapaneseSpeechSynthesizer,
        JapanesePitchAccentSynthesizer,
        JapanesePitchAccentHintSynthesizer {
  const JapaneseTtsService({
    MethodChannel channel = _defaultChannel,
    TargetPlatform? platformOverride,
  }) : _channel = channel,
       _platformOverride = platformOverride;

  static const MethodChannel _defaultChannel = MethodChannel(
    'app.shinbi.tsuki_words/japanese_tts',
  );

  static const JapaneseTtsService instance = JapaneseTtsService();

  final MethodChannel _channel;
  final TargetPlatform? _platformOverride;

  bool get _supportsNativeTts =>
      (_platformOverride ?? defaultTargetPlatform) == TargetPlatform.android;

  @override
  Future<JapaneseTtsResult> speak(String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return const JapaneseTtsResult(JapaneseTtsStatus.invalidText);
    }
    if (!_supportsNativeTts) {
      return const JapaneseTtsResult(JapaneseTtsStatus.unsupportedPlatform);
    }
    return _invoke('speak', <String, Object>{
      'text': normalizedText,
    }, fallbackSuccessStatus: JapaneseTtsStatus.completed);
  }

  @override
  Future<JapaneseTtsResult> speakWithPitchAccentHint(
    String text,
    String reading,
    int accent,
  ) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return const JapaneseTtsResult(JapaneseTtsStatus.invalidText);
    }
    if (!_supportsNativeTts) {
      return const JapaneseTtsResult(JapaneseTtsStatus.unsupportedPlatform);
    }
    return speak(normalizedText);
  }

  @override
  Future<JapaneseTtsResult> stop() {
    if (!_supportsNativeTts) {
      return SynchronousFuture(
        const JapaneseTtsResult(JapaneseTtsStatus.unsupportedPlatform),
      );
    }
    return _invoke(
      'stop',
      null,
      fallbackSuccessStatus: JapaneseTtsStatus.cancelled,
    );
  }

  @override
  Future<JapaneseTtsResult> checkAvailability() {
    if (!_supportsNativeTts) {
      return SynchronousFuture(
        const JapaneseTtsResult(JapaneseTtsStatus.unsupportedPlatform),
      );
    }
    return _invoke(
      'checkAvailability',
      null,
      fallbackSuccessStatus: JapaneseTtsStatus.completed,
    );
  }

  @override
  Future<JapaneseTtsResult> speakPitchAccent(
    String reading,
    int accent,
  ) async => const JapaneseTtsResult(JapaneseTtsStatus.pitchAccentUnavailable);

  Future<JapaneseTtsResult> _invoke(
    String method,
    Object? arguments, {
    required JapaneseTtsStatus fallbackSuccessStatus,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      final status = response?['status'];
      return JapaneseTtsResult(
        switch (status) {
          'completed' || 'available' => JapaneseTtsStatus.completed,
          'cancelled' || 'stopped' => JapaneseTtsStatus.cancelled,
          _ => fallbackSuccessStatus,
        },
        engine: switch (response?['engine']) {
          'android' => JapaneseVoiceEngine.android,
          _ => null,
        },
      );
    } on MissingPluginException catch (error) {
      return JapaneseTtsResult(
        JapaneseTtsStatus.unavailable,
        details: error.message,
      );
    } on PlatformException catch (error) {
      return JapaneseTtsResult(
        _statusForPlatformCode(error.code),
        details: error.message,
      );
    } catch (error) {
      return JapaneseTtsResult(
        JapaneseTtsStatus.failed,
        details: error.toString(),
      );
    }
  }

  static JapaneseTtsStatus _statusForPlatformCode(String code) {
    return switch (code) {
      'tts_invalid_text' ||
      'tts_text_too_long' => JapaneseTtsStatus.invalidText,
      'tts_language_data_missing' => JapaneseTtsStatus.languageDataMissing,
      'tts_language_not_supported' => JapaneseTtsStatus.languageNotSupported,
      'tts_pitch_accent_unavailable' =>
        JapaneseTtsStatus.pitchAccentUnavailable,
      'tts_initialization_failed' ||
      'tts_unavailable' ||
      'tts_disposed' => JapaneseTtsStatus.unavailable,
      'tts_stopped' => JapaneseTtsStatus.cancelled,
      _ => JapaneseTtsStatus.failed,
    };
  }
}
