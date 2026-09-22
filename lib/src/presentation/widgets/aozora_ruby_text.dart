import 'dart:collection';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Builds Aozora ruby markup while keeping okurigana and other kana outside
/// ruby spans. For example, `食べる / たべる` becomes `｜食《た》べる`.
///
/// Kana runs act as anchors while the reading is aligned to kanji runs. When a
/// source and reading cannot be aligned safely, the visible source is returned
/// without speculative ruby.
String buildAozoraRubySource(String surface, String reading) {
  if (surface.isEmpty ||
      reading.isEmpty ||
      surface == reading ||
      !surface.runes.any(_isKanjiRune)) {
    return surface;
  }
  final segments = _splitSurfaceReading(surface, reading);
  if (!segments.any((segment) => segment.reading.isNotEmpty)) return surface;

  final result = StringBuffer();
  for (final segment in segments) {
    if (segment.reading.isEmpty) {
      result.write(segment.base);
    } else {
      result
        ..write('｜')
        ..write(segment.base)
        ..write('《')
        ..write(segment.reading)
        ..write('》');
    }
  }
  return result.toString();
}

/// Builds one ruby source for a word with more than one accepted reading.
/// Readings are combined only when every reading aligns to the same visible
/// segments; otherwise the primary reading is used without guessing.
String buildAozoraRubySourceForReadings(
  String surface,
  Iterable<String> readings,
) {
  final uniqueReadings = <String>[];
  for (final reading in readings) {
    final value = reading.trim();
    if (value.isNotEmpty && !uniqueReadings.contains(value)) {
      uniqueReadings.add(value);
    }
  }
  if (uniqueReadings.isEmpty) return surface;
  if (uniqueReadings.length == 1) {
    return buildAozoraRubySource(surface, uniqueReadings.first);
  }

  final aligned = [
    for (final reading in uniqueReadings)
      _splitSurfaceReading(surface, reading),
  ];
  final primary = aligned.first;
  if (primary.every((segment) => segment.reading.isEmpty)) return surface;
  for (final candidate in aligned.skip(1)) {
    if (candidate.length != primary.length) {
      return buildAozoraRubySource(surface, uniqueReadings.first);
    }
    for (var index = 0; index < primary.length; index++) {
      if (candidate[index].base != primary[index].base ||
          candidate[index].reading.isEmpty != primary[index].reading.isEmpty) {
        return buildAozoraRubySource(surface, uniqueReadings.first);
      }
    }
  }

  final result = StringBuffer();
  for (var index = 0; index < primary.length; index++) {
    final segment = primary[index];
    if (segment.reading.isEmpty) {
      result.write(segment.base);
      continue;
    }
    final alternatives = <String>[];
    for (final candidate in aligned) {
      final reading = candidate[index].reading;
      if (!alternatives.contains(reading)) alternatives.add(reading);
    }
    result
      ..write('｜')
      ..write(segment.base)
      ..write('《')
      ..write(alternatives.join('・'))
      ..write('》');
  }
  return result.toString();
}

/// Renders Aozora-style ruby markup such as `｜漢字《かんじ》`.
class AozoraRubyText extends StatelessWidget {
  const AozoraRubyText(
    this.source, {
    super.key,
    this.showRuby = true,
    this.baseStyle,
    this.rubyStyle,
    this.textAlign = TextAlign.start,
    this.semanticsLabel,
    this.onTap,
    this.tapSemanticsLabel,
  });

  final String source;
  final bool showRuby;
  final TextStyle? baseStyle;
  final TextStyle? rubyStyle;
  final TextAlign textAlign;
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final String? tapSemanticsLabel;

  static final RegExp _rubyPattern = RegExp(r'｜([^《]+)《([^》]+)》');
  static const _maxParsedSourceCacheEntries = 512;
  static final LinkedHashMap<String, _ParsedRubySource> _parsedSourceCache =
      LinkedHashMap<String, _ParsedRubySource>();

  /// Removes ruby readings while preserving the visible Japanese sentence.
  static String plainTextOf(String source) {
    return _parseSource(source).plainText;
  }

  /// Exposed only so regression tests can ensure the rendering cache stays
  /// bounded even when users browse a large vocabulary catalog.
  @visibleForTesting
  static int get debugParsedSourceCacheLength => _parsedSourceCache.length;

  @visibleForTesting
  static void debugClearParsedSourceCache() => _parsedSourceCache.clear();

  static _ParsedRubySource _parseSource(String source) {
    final cached = _parsedSourceCache.remove(source);
    if (cached != null) {
      // Reinsert on access to retain the most recently rendered sources.
      _parsedSourceCache[source] = cached;
      return cached;
    }

    final segments = <_RubySegment>[];
    final plainText = StringBuffer();
    final spokenText = StringBuffer();
    var cursor = 0;
    var hasRuby = false;
    for (final match in _rubyPattern.allMatches(source)) {
      if (match.start > cursor) {
        final prefix = source.substring(cursor, match.start);
        segments.add(_RubySegment(prefix, ''));
        plainText.write(prefix);
        spokenText.write(prefix);
      }
      final base = match.group(1)!;
      final reading = match.group(2)!;
      final alignedSegments = _splitSurfaceReading(base, reading);
      final aligned = alignedSegments.any(
        (segment) => segment.reading.isNotEmpty,
      );
      hasRuby = hasRuby || aligned;
      segments.addAll(alignedSegments);
      plainText.write(base);
      spokenText.write(base);
      if (aligned) {
        spokenText
          ..write(', ')
          ..write(reading);
      }
      cursor = match.end;
    }
    if (cursor < source.length) {
      final suffix = source.substring(cursor);
      segments.add(_RubySegment(suffix, ''));
      plainText.write(suffix);
      spokenText.write(suffix);
    }

    final parsed = _ParsedRubySource(
      hasRuby: hasRuby,
      plainText: hasRuby ? plainText.toString() : source,
      spokenText: hasRuby ? spokenText.toString() : source,
      segments: hasRuby ? List.unmodifiable(segments) : const [],
    );
    if (_parsedSourceCache.length >= _maxParsedSourceCacheEntries) {
      _parsedSourceCache.remove(_parsedSourceCache.keys.first);
    }
    _parsedSourceCache[source] = parsed;
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBase =
        (baseStyle ??
                Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.34,
                ) ??
                const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  height: 1.34,
                  fontWeight: FontWeight.w600,
                ))
            .copyWith(
              fontFamily: AppFonts.japanese,
              fontFamilyFallback: const [AppFonts.primary],
              locale: const Locale('ja'),
            );
    final effectiveRuby =
        (rubyStyle ??
                const TextStyle(
                  color: AppColors.reading,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ))
            .copyWith(
              fontFamily: AppFonts.japanese,
              fontFamilyFallback: const [AppFonts.primary],
              locale: const Locale('ja'),
            );
    final parsed = _parseSource(source);

    final Widget content;
    if (!showRuby || !parsed.hasRuby) {
      content = Text(
        parsed.plainText,
        textAlign: textAlign,
        style: effectiveBase,
        semanticsLabel: semanticsLabel,
      );
    } else {
      content = Semantics(
        label: semanticsLabel ?? parsed.spokenText,
        child: ExcludeSemantics(
          child: Wrap(
            alignment: switch (textAlign) {
              TextAlign.center => WrapAlignment.center,
              TextAlign.end || TextAlign.right => WrapAlignment.end,
              TextAlign.justify => WrapAlignment.spaceBetween,
              _ => WrapAlignment.start,
            },
            spacing: 0,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: parsed.segments
                .map(
                  (segment) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        segment.reading.isEmpty ? '\u00A0' : segment.reading,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: effectiveRuby,
                      ),
                      Text(segment.base, style: effectiveBase),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
    }
    final tap = onTap;
    if (tap == null) return content;
    return Semantics(
      container: true,
      button: true,
      label: tapSemanticsLabel ?? '${parsed.plainText}, 일본어 발음 듣기',
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: content,
      ),
    );
  }
}

class _ParsedRubySource {
  const _ParsedRubySource({
    required this.hasRuby,
    required this.plainText,
    required this.spokenText,
    required this.segments,
  });

  final bool hasRuby;
  final String plainText;
  final String spokenText;
  final List<_RubySegment> segments;
}

class _RubySegment {
  const _RubySegment(this.base, this.reading);

  final String base;
  final String reading;
}

enum _SurfaceSegmentKind { kanji, kana, literal }

class _SurfaceSegment {
  const _SurfaceSegment(this.kind, this.runes);

  final _SurfaceSegmentKind kind;
  final List<int> runes;

  String get text => String.fromCharCodes(runes);
}

List<_RubySegment> _splitSurfaceReading(String surface, String reading) {
  final surfaceSegments = _segmentSurface(surface);
  if (!surfaceSegments.any(
    (segment) => segment.kind == _SurfaceSegmentKind.kanji,
  )) {
    return [_RubySegment(surface, '')];
  }

  final readingRunes = reading.runes.toList(growable: false);
  final memo = <int, List<int>?>{};
  final memoWidth = readingRunes.length + 1;

  List<int>? align(int segmentIndex, int readingIndex) {
    if (segmentIndex == surfaceSegments.length) {
      return readingIndex == readingRunes.length ? const <int>[] : null;
    }
    final key = segmentIndex * memoWidth + readingIndex;
    if (memo.containsKey(key)) return memo[key];

    final segment = surfaceSegments[segmentIndex];
    List<int>? result;
    switch (segment.kind) {
      case _SurfaceSegmentKind.kanji:
        // A kanji run must receive at least one reading rune. Trying the
        // shortest allocation first lets later kana anchors disambiguate
        // okurigana without guessing character-by-character readings.
        for (var end = readingIndex + 1; end <= readingRunes.length; end++) {
          final tail = align(segmentIndex + 1, end);
          if (tail != null) {
            result = [end, ...tail];
            break;
          }
        }
      case _SurfaceSegmentKind.kana:
        final end = readingIndex + segment.runes.length;
        if (end <= readingRunes.length &&
            _matchesReading(segment.runes, readingRunes, readingIndex)) {
          final tail = align(segmentIndex + 1, end);
          if (tail != null) result = [end, ...tail];
        }
      case _SurfaceSegmentKind.literal:
        final end = readingIndex + segment.runes.length;
        if (end <= readingRunes.length &&
            _matchesReading(segment.runes, readingRunes, readingIndex)) {
          final tail = align(segmentIndex + 1, end);
          if (tail != null) result = [end, ...tail];
        }
        // Dictionary readings often omit punctuation or Arabic numerals.
        if (result == null) {
          final tail = align(segmentIndex + 1, readingIndex);
          if (tail != null) result = [readingIndex, ...tail];
        }
    }
    memo[key] = result;
    return result;
  }

  final ends = align(0, 0);
  if (ends == null || ends.length != surfaceSegments.length) {
    return [_RubySegment(surface, '')];
  }

  final result = <_RubySegment>[];
  var readingStart = 0;
  for (var index = 0; index < surfaceSegments.length; index++) {
    final segment = surfaceSegments[index];
    final readingEnd = ends[index];
    final alignedReading = segment.kind == _SurfaceSegmentKind.kanji
        ? String.fromCharCodes(readingRunes.sublist(readingStart, readingEnd))
        : '';
    result.add(_RubySegment(segment.text, alignedReading));
    readingStart = readingEnd;
  }
  return result;
}

List<_SurfaceSegment> _segmentSurface(String surface) {
  final result = <_SurfaceSegment>[];
  _SurfaceSegmentKind? currentKind;
  var currentRunes = <int>[];
  for (final rune in surface.runes) {
    final kind = _isKanjiRune(rune)
        ? _SurfaceSegmentKind.kanji
        : _isKanaRune(rune)
        ? _SurfaceSegmentKind.kana
        : _SurfaceSegmentKind.literal;
    if (currentKind != null && kind != currentKind) {
      result.add(_SurfaceSegment(currentKind, currentRunes));
      currentRunes = <int>[];
    }
    currentKind = kind;
    currentRunes.add(rune);
  }
  if (currentKind != null) {
    result.add(_SurfaceSegment(currentKind, currentRunes));
  }
  return result;
}

bool _matchesReading(
  List<int> surfaceRunes,
  List<int> readingRunes,
  int readingStart,
) {
  for (var offset = 0; offset < surfaceRunes.length; offset++) {
    if (_normalizeKanaRune(surfaceRunes[offset]) !=
        _normalizeKanaRune(readingRunes[readingStart + offset])) {
      return false;
    }
  }
  return true;
}

int _normalizeKanaRune(int rune) =>
    rune >= 0x30A1 && rune <= 0x30F6 ? rune - 0x60 : rune;

bool _isKanaRune(int rune) =>
    (rune >= 0x3040 && rune <= 0x309F) ||
    (rune >= 0x30A0 && rune <= 0x30FF) ||
    (rune >= 0xFF66 && rune <= 0xFF9D);

bool _isKanjiRune(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    rune == 0x3005 ||
    rune == 0x3006 ||
    rune == 0x3007 ||
    rune == 0x30F6;
