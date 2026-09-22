import 'package:flutter/material.dart';

import '../../services/japanese_tts_service.dart';
import '../../theme/app_theme.dart';

/// Plays [text] and reports device TTS failures using the nearest scaffold.
///
/// This is shared by the visible speaker button and tappable Japanese text so
/// every pronunciation entry point behaves consistently.
Future<JapaneseTtsResult> speakJapaneseWithFeedback(
  BuildContext context,
  String text, {
  JapaneseSpeechSynthesizer synthesizer = JapaneseTtsService.instance,
  String? reading,
  int? pitchAccent,
}) async {
  final pitchSynthesizer = synthesizer is JapanesePitchAccentHintSynthesizer
      ? synthesizer as JapanesePitchAccentHintSynthesizer
      : null;
  final result =
      reading != null && pitchAccent != null && pitchSynthesizer != null
      ? await pitchSynthesizer.speakWithPitchAccentHint(
          text,
          reading,
          pitchAccent,
        )
      : await synthesizer.speak(text);
  if (!context.mounted || result.isSuccess || result.isCancelled) return result;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.userMessage)));
  return result;
}

Future<JapaneseTtsResult> speakPitchAccentWithFeedback(
  BuildContext context,
  String reading,
  int accent, {
  JapanesePitchAccentSynthesizer synthesizer = JapaneseTtsService.instance,
}) async {
  final result = await synthesizer.speakPitchAccent(reading, accent);
  if (!context.mounted || result.isSuccess || result.isCancelled) return result;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.userMessage)));
  return result;
}

/// A reusable control that plays Japanese text through the device TTS engine.
///
/// Failed requests always surface a short snackbar. Playback cancellation is
/// intentionally quiet because it is the expected result of pressing stop or
/// starting another utterance.
class JapaneseTtsButton extends StatefulWidget {
  const JapaneseTtsButton({
    super.key,
    required this.text,
    this.synthesizer = JapaneseTtsService.instance,
    this.tooltip = '일본어 발음 듣기',
    this.iconSize = 20,
    this.visualDensity = VisualDensity.compact,
    this.dark = false,
    this.constraints,
    this.padding,
    this.reading,
    this.pitchAccent,
  });

  final String text;
  final JapaneseSpeechSynthesizer synthesizer;
  final String tooltip;
  final double iconSize;
  final VisualDensity visualDensity;
  final bool dark;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final String? reading;
  final int? pitchAccent;

  @override
  State<JapaneseTtsButton> createState() => _JapaneseTtsButtonState();
}

class _JapaneseTtsButtonState extends State<JapaneseTtsButton> {
  bool _speaking = false;
  bool _stopping = false;

  @override
  Widget build(BuildContext context) {
    final idleColor = widget.dark ? AppColors.moon : AppColors.mutedBlue;
    final activeColor = widget.dark ? Colors.white : AppColors.ink;
    return IconButton.outlined(
      tooltip: _speaking ? '일본어 발음 중지' : widget.tooltip,
      onPressed: _stopping ? null : (_speaking ? _stop : _speak),
      visualDensity: widget.visualDensity,
      constraints: widget.constraints,
      padding: widget.padding,
      style: widget.dark
          ? IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            )
          : null,
      icon: AnimatedSwitcher(
        duration: AppDurations.fast,
        child: Icon(
          _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
          key: ValueKey(_speaking ? 'tts-stop-icon' : 'tts-play-icon'),
          size: widget.iconSize,
          color: _speaking ? activeColor : idleColor,
        ),
      ),
    );
  }

  Future<void> _speak() async {
    if (_speaking || _stopping) return;
    setState(() => _speaking = true);
    await speakJapaneseWithFeedback(
      context,
      widget.text,
      synthesizer: widget.synthesizer,
      reading: widget.reading,
      pitchAccent: widget.pitchAccent,
    );
    if (!mounted) return;
    setState(() => _speaking = false);
  }

  Future<void> _stop() async {
    if (!_speaking || _stopping) return;
    setState(() => _stopping = true);
    final result = await widget.synthesizer.stop();
    if (!mounted) return;
    setState(() {
      _speaking = false;
      _stopping = false;
    });
    _showFailure(result);
  }

  void _showFailure(JapaneseTtsResult result) {
    if (result.isSuccess || result.isCancelled) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.userMessage)));
  }
}
