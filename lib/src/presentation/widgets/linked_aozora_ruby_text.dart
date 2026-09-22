import 'package:flutter/material.dart';

import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import 'aozora_ruby_text.dart';

/// A dictionary match in the visible (ruby-free) example sentence.
///
/// [start] and [end] are UTF-16 offsets, suitable for [String.substring].
class ExampleWordMatch {
  const ExampleWordMatch({
    required this.word,
    required this.surface,
    required this.start,
    required this.end,
    this.readings = const [],
    this.candidateWords = const [],
  });

  final JapaneseWord word;
  final String surface;
  final int start;
  final int end;
  final List<String> readings;
  final List<JapaneseWord> candidateWords;

  bool get isAmbiguous => candidateWords.length > 1;
}

/// One pass over a user-authored sentence, including the generated ruby source.
class SentenceWordAnalysis {
  const SentenceWordAnalysis({
    required this.sentence,
    required this.rubySource,
    required this.matches,
  });

  final String sentence;
  final String rubySource;
  final List<ExampleWordMatch> matches;

  bool get hasMatches => matches.isNotEmpty;

  int get uniqueWordCount => matches
      .expand(
        (match) => match.candidateWords.isEmpty
            ? <JapaneseWord>[match.word]
            : match.candidateWords,
      )
      .map((word) => word.id)
      .toSet()
      .length;

  int get ambiguousMatchCount =>
      matches.where((match) => match.isAmbiguous).length;
}

/// A reusable lookup index for linking words inside Japanese examples.
///
/// Build this once for the complete catalog and reuse it for every sentence.
/// Lemmas, alternative spellings, registered conjugations, and example focus
/// surfaces are indexed. Matches are left-to-right and longest-first, so they
/// never overlap. Single-kana entries are skipped unless explicitly supplied
/// as [preferredSurface], because they create excessive substring noise in
/// Japanese text without a morphological tokenizer.
class ExampleWordLinkIndex {
  ExampleWordLinkIndex(Iterable<JapaneseWord> words)
    : _entriesByPrefix = _buildEntries(words);

  final Map<String, List<_IndexedSurface>> _entriesByPrefix;

  /// Finds catalog expressions and adds ruby only to those matched ranges.
  ///
  /// Unmatched text is preserved byte-for-byte. A lemma with multiple accepted
  /// readings shows all alignable readings, while conjugated forms use their
  /// registered form reading.
  SentenceWordAnalysis analyzeSentence(String sentence) {
    final matches = match(sentence);
    if (matches.isEmpty) {
      return SentenceWordAnalysis(
        sentence: sentence,
        rubySource: sentence,
        matches: matches,
      );
    }

    final rubySource = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        rubySource.write(sentence.substring(cursor, match.start));
      }
      rubySource.write(
        buildAozoraRubySourceForReadings(match.surface, match.readings),
      );
      cursor = match.end;
    }
    if (cursor < sentence.length) rubySource.write(sentence.substring(cursor));
    return SentenceWordAnalysis(
      sentence: sentence,
      rubySource: rubySource.toString(),
      matches: matches,
    );
  }

  /// Finds non-overlapping catalog words in [sentence].
  ///
  /// Pass both [preferredWord] and [preferredSurface] for an example's owning
  /// word. Every occurrence of that exact focus surface is reserved for its
  /// owner before ordinary longest-match resolution, including irregular
  /// focus forms that are absent from the catalog's conjugation list.
  List<ExampleWordMatch> match(
    String sentence, {
    JapaneseWord? preferredWord,
    String? preferredSurface,
  }) {
    assert(
      (preferredWord == null) == (preferredSurface == null),
      'preferredWord and preferredSurface must be supplied together.',
    );
    if (sentence.isEmpty) return const [];

    final runes = sentence.runes.toList(growable: false);
    final offsets = List<int>.filled(runes.length + 1, 0);
    final runeIndexByOffset = <int, int>{0: 0};
    for (var index = 0; index < runes.length; index++) {
      offsets[index + 1] = offsets[index] + (runes[index] > 0xFFFF ? 2 : 1);
      runeIndexByOffset[offsets[index + 1]] = index + 1;
    }
    final preferredStarts = _preferredStarts(
      sentence,
      preferredWord,
      preferredSurface,
      runeIndexByOffset,
    );
    final orderedPreferredStarts = preferredStarts.keys.toList()..sort();

    final matches = <ExampleWordMatch>[];
    var runeIndex = 0;
    var preferredCursor = 0;
    while (runeIndex < runes.length) {
      final start = offsets[runeIndex];
      while (preferredCursor < orderedPreferredStarts.length &&
          orderedPreferredStarts[preferredCursor] < start) {
        preferredCursor += 1;
      }

      final preferred = preferredStarts[start];
      if (preferred != null) {
        matches.add(preferred);
        runeIndex = runeIndexByOffset[preferred.end]!;
        preferredCursor += 1;
        continue;
      }

      final nextPreferredStart = preferredCursor < orderedPreferredStarts.length
          ? orderedPreferredStarts[preferredCursor]
          : null;
      _IndexedSurface? accepted;
      if (runeIndex + 1 < runes.length) {
        final prefix = String.fromCharCodes(
          runes.sublist(runeIndex, runeIndex + 2),
        );
        accepted = _longestMatchAt(
          sentence,
          runes,
          runeIndex,
          start,
          _entriesByPrefix[prefix],
          maximumEnd: nextPreferredStart,
        );
      }
      accepted ??= _longestMatchAt(
        sentence,
        runes,
        runeIndex,
        start,
        _entriesByPrefix[String.fromCharCode(runes[runeIndex])],
        maximumEnd: nextPreferredStart,
      );

      if (accepted == null) {
        runeIndex += 1;
        continue;
      }

      final end = start + accepted.surface.length;
      matches.add(
        ExampleWordMatch(
          word: accepted.word,
          surface: accepted.surface,
          start: start,
          end: end,
          readings: accepted.readings,
          candidateWords: accepted.candidateWords,
        ),
      );
      runeIndex += accepted.runeLength;
    }
    return List<ExampleWordMatch>.unmodifiable(matches);
  }

  static Map<int, ExampleWordMatch> _preferredStarts(
    String sentence,
    JapaneseWord? word,
    String? rawSurface,
    Map<int, int> runeIndexByOffset,
  ) {
    if (word == null || rawSurface == null) return const {};
    final surface = rawSurface.trim();
    if (surface.isEmpty) return const {};

    final result = <int, ExampleWordMatch>{};
    var searchStart = 0;
    while (searchStart < sentence.length) {
      final start = sentence.indexOf(surface, searchStart);
      if (start < 0) break;
      final end = start + surface.length;
      if (runeIndexByOffset.containsKey(start) &&
          runeIndexByOffset.containsKey(end)) {
        result[start] = ExampleWordMatch(
          word: word,
          surface: surface,
          start: start,
          end: end,
          readings: word.readings,
          candidateWords: [word],
        );
      }
      searchStart = end > start ? end : start + 1;
    }
    return result;
  }

  static _IndexedSurface? _longestMatchAt(
    String sentence,
    List<int> sentenceRunes,
    int startRune,
    int start,
    List<_IndexedSurface>? entries, {
    required int? maximumEnd,
  }) {
    if (entries == null) return null;
    for (final entry in entries) {
      final end = start + entry.surface.length;
      if (maximumEnd != null && end > maximumEnd) continue;
      if (!sentence.startsWith(entry.surface, start)) continue;
      if (!_hasSafeBoundaries(sentenceRunes, startRune, entry)) continue;
      return entry;
    }
    return null;
  }

  static bool _hasSafeBoundaries(
    List<int> sentenceRunes,
    int startRune,
    _IndexedSurface entry,
  ) {
    // The dictionary entry 「では」 means the discourse connector “then”. The
    // same surface inside 「国では」 or 「のではない」 is instead the particles
    // で＋は, so only link the conjunction at a sentence/clause boundary.
    if (entry.surface == 'では' &&
        entry.word.lemma == 'では' &&
        entry.word.partOfSpeech == WordPartOfSpeech.conjunction) {
      if (startRune == 0) return true;
      return _isClauseBoundary(sentenceRunes[startRune - 1]);
    }
    if (!entry.isKanjiOnly) return true;

    final endRune = startRune + entry.runeLength;
    final previous = startRune == 0 ? null : sentenceRunes[startRune - 1];
    final next = endRune == sentenceRunes.length
        ? null
        : sentenceRunes[endRune];
    // Do not turn 「日本」 into a link inside an unindexed compound such as
    // 「日本語」. If the full compound is indexed, it wins as the longer match.
    return (previous == null || !_isKanji(previous)) &&
        (next == null || !_isKanji(next));
  }

  static Map<String, List<_IndexedSurface>> _buildEntries(
    Iterable<JapaneseWord> words,
  ) {
    final choices = <String, Map<String, _SurfaceChoice>>{};
    var catalogOrder = 0;

    void add(
      JapaneseWord word,
      String rawSurface,
      Iterable<String> rawReadings,
      int priority,
    ) {
      final surface = rawSurface.trim();
      if (surface.isEmpty || !_containsJapanese(surface)) return;
      final surfaceRunes = surface.runes.toList(growable: false);
      if (surfaceRunes.length == 1 && _isKana(surfaceRunes.single)) return;

      final next = _SurfaceChoice(
        word: word,
        readings: List<String>.unmodifiable(
          rawReadings
              .map((reading) => reading.trim())
              .where((reading) => reading.isNotEmpty),
        ),
        priority: priority,
        catalogOrder: catalogOrder,
      );
      final choicesByWord = choices.putIfAbsent(
        surface,
        () => <String, _SurfaceChoice>{},
      );
      final previous = choicesByWord[word.id];
      if (previous == null || next.isPreferredTo(previous)) {
        choicesByWord[word.id] = next;
      }
    }

    for (final word in words) {
      final wordReadings = word.readings;
      add(word, word.lemma, wordReadings, 4);
      for (final spelling in word.alternativeSpellings) {
        add(word, spelling, wordReadings, 3);
      }
      for (final form in word.forms) {
        add(word, form.surface, [form.reading], 2);
      }
      for (final example in word.examples) {
        final focus = example.focusSurface.trim();
        if ((choices[focus]?[word.id]?.priority ?? 0) > 1) continue;
        add(word, focus, _focusReadings(example), 1);
      }
      catalogOrder += 1;
    }

    final mutable = <String, List<_IndexedSurface>>{};
    for (final entry in choices.entries) {
      final candidates = entry.value.values.toList(growable: false)
        ..sort((left, right) {
          final byPriority = right.priority.compareTo(left.priority);
          if (byPriority != 0) return byPriority;
          return left.catalogOrder.compareTo(right.catalogOrder);
        });
      final primary = candidates.first;
      final readings = <String>[];
      for (final candidate in candidates) {
        for (final reading in candidate.readings) {
          if (!readings.contains(reading)) readings.add(reading);
        }
      }
      final runes = entry.key.runes.toList(growable: false);
      final prefix = String.fromCharCodes(runes.take(2));
      (mutable[prefix] ??= <_IndexedSurface>[]).add(
        _IndexedSurface(
          word: primary.word,
          surface: entry.key,
          readings: List<String>.unmodifiable(readings),
          candidateWords: List<JapaneseWord>.unmodifiable(
            candidates.map((candidate) => candidate.word),
          ),
          runeLength: runes.length,
          isKanjiOnly: runes.every(_isKanji),
        ),
      );
    }
    for (final entries in mutable.values) {
      entries.sort((left, right) {
        final byLength = right.runeLength.compareTo(left.runeLength);
        if (byLength != 0) return byLength;
        return left.surface.compareTo(right.surface);
      });
    }
    return Map<String, List<_IndexedSurface>>.unmodifiable({
      for (final entry in mutable.entries)
        entry.key: List<_IndexedSurface>.unmodifiable(entry.value),
    });
  }
}

bool _isClauseBoundary(int rune) =>
    rune == 0x000A ||
    rune == 0x000D ||
    rune == 0x3001 || // 、
    rune == 0x3002 || // 。
    rune == 0xFF01 || // ！
    rune == 0xFF1F || // ？
    rune == 0x0021 ||
    rune == 0x003F ||
    rune == 0x2026 || // …
    rune == 0x2014 || // —
    rune == 0x300C || // 「
    rune == 0x300E || // 『
    rune == 0xFF08 || // （
    rune == 0x0028; // (

/// Renders an Aozora-ruby sentence and turns catalog matches into text links.
///
/// Linked text uses a rounded [AppColors.mutedBlue] highlight, while ruby keeps
/// [rubyStyle]. Each link has stable keys from [linkKey] and [highlightKey].
class LinkedAozoraRubyText extends StatelessWidget {
  const LinkedAozoraRubyText(
    this.source, {
    super.key,
    required this.linkIndex,
    required this.onWordTap,
    this.onMatchTap,
    this.onUnlinkedTap,
    this.preferredWord,
    this.preferredSurface,
    this.showRuby = true,
    this.baseStyle,
    this.rubyStyle,
    this.textAlign = TextAlign.start,
    this.unlinkedTapSemanticsLabel,
    this.semanticsLabel,
  }) : assert(
         (preferredWord == null) == (preferredSurface == null),
         'preferredWord and preferredSurface must be supplied together.',
       );

  final String source;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onWordTap;
  final ValueChanged<ExampleWordMatch>? onMatchTap;

  /// Called only when a Japanese fragment that is not a dictionary link is
  /// tapped. Dictionary links always invoke [onWordTap] instead.
  final VoidCallback? onUnlinkedTap;
  final JapaneseWord? preferredWord;
  final String? preferredSurface;
  final bool showRuby;
  final TextStyle? baseStyle;
  final TextStyle? rubyStyle;
  final TextAlign textAlign;

  /// Optional pronunciation-action label for the complete sentence.
  ///
  /// When links split the visual sentence into multiple fragments, this keeps
  /// accessibility services from announcing a fragmented pronunciation.
  final String? unlinkedTapSemanticsLabel;

  /// Optional general sentence label.
  ///
  /// [unlinkedTapSemanticsLabel] takes precedence when both are supplied.
  final String? semanticsLabel;

  static ValueKey<String> linkKey(String wordId, int start) =>
      ValueKey<String>('example-word-link-$wordId-$start');

  static ValueKey<String> highlightKey(String wordId, int start) =>
      ValueKey<String>('example-word-highlight-$wordId-$start');

  static ValueKey<String> unlinkedFragmentKey(int index) =>
      ValueKey<String>('example-unlinked-fragment-$index');

  void _openMatch(ExampleWordMatch match) {
    final matchTap = onMatchTap;
    if (matchTap != null) {
      matchTap(match);
    } else {
      onWordTap(match.word);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSemanticsLabel = unlinkedTapSemanticsLabel ?? semanticsLabel;
    final mapped = _MappedAozoraSource(source);
    final matches = linkIndex.match(
      mapped.plainText,
      preferredWord: preferredWord,
      preferredSurface: preferredSurface,
    );
    final fragments = mapped.fragmentsFor(matches);

    if (!fragments.any((fragment) => fragment.match != null)) {
      return _UnlinkedRubyFragment(
        mapped.normalizedSource,
        key: unlinkedFragmentKey(0),
        onTap: onUnlinkedTap,
        showRuby: showRuby,
        baseStyle: baseStyle,
        rubyStyle: rubyStyle,
        textAlign: textAlign,
        semanticsLabel: effectiveSemanticsLabel,
      );
    }

    final effectiveBase =
        baseStyle ??
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
        );
    final linkedBase = effectiveBase.copyWith(
      color: AppColors.mutedBlue,
      decoration: TextDecoration.none,
    );

    final alignment = switch (textAlign) {
      TextAlign.center => WrapAlignment.center,
      TextAlign.end || TextAlign.right => WrapAlignment.end,
      TextAlign.justify => WrapAlignment.spaceBetween,
      _ => WrapAlignment.start,
    };
    final lines = _splitFragmentsIntoLines(fragments);

    Widget buildFragment(_LineFragment fragment) {
      if (fragment.match case final match?) {
        return Semantics(
          key: linkKey(match.word.id, match.start),
          link: true,
          label: onMatchTap != null && match.isAmbiguous
              ? '${match.surface}, 단어 후보 ${match.candidateWords.length}개 보기'
              : '${match.word.lemma}, 단어 자세히 보기',
          onTap: () => _openMatch(match),
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openMatch(match),
                child: Container(
                  key: highlightKey(match.word.id, match.start),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mutedBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    border: Border.all(
                      color: AppColors.mutedBlue.withValues(alpha: 0.32),
                      width: 0.75,
                    ),
                  ),
                  child: AozoraRubyText(
                    fragment.source,
                    showRuby: showRuby,
                    baseStyle: linkedBase,
                    rubyStyle: rubyStyle,
                    textAlign: textAlign,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return _UnlinkedRubyFragment(
        fragment.source,
        key: unlinkedFragmentKey(fragment.keyIndex),
        onTap: onUnlinkedTap,
        showRuby: showRuby,
        baseStyle: baseStyle,
        rubyStyle: rubyStyle,
        textAlign: textAlign,
        excludeSemantics: effectiveSemanticsLabel != null,
      );
    }

    Widget buildLine(List<_LineFragment> line) {
      if (line.isEmpty) {
        final baseHeight =
            (effectiveBase.fontSize ?? 14) * (effectiveBase.height ?? 1.2);
        final rubyHeight = showRuby
            ? (rubyStyle?.fontSize ?? 10) * (rubyStyle?.height ?? 1)
            : 0.0;
        return SizedBox(height: baseHeight + rubyHeight);
      }
      return Wrap(
        alignment: alignment,
        spacing: 0,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [for (final fragment in line) buildFragment(fragment)],
      );
    }

    final visualSentence = lines.length == 1
        ? buildLine(lines.single)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final line in lines) buildLine(line)],
          );

    if (effectiveSemanticsLabel == null) return visualSentence;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: effectiveSemanticsLabel,
      onTap: onUnlinkedTap,
      child: visualSentence,
    );
  }
}

class _UnlinkedRubyFragment extends StatelessWidget {
  const _UnlinkedRubyFragment(
    this.source, {
    super.key,
    required this.onTap,
    required this.showRuby,
    required this.baseStyle,
    required this.rubyStyle,
    required this.textAlign,
    this.semanticsLabel,
    this.excludeSemantics = false,
  });

  final String source;
  final VoidCallback? onTap;
  final bool showRuby;
  final TextStyle? baseStyle;
  final TextStyle? rubyStyle;
  final TextAlign textAlign;
  final String? semanticsLabel;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final text = AozoraRubyText(
      source,
      showRuby: showRuby,
      baseStyle: baseStyle,
      rubyStyle: rubyStyle,
      textAlign: textAlign,
      semanticsLabel: semanticsLabel,
    );
    final effectiveTap =
        onTap != null && _containsJapanese(AozoraRubyText.plainTextOf(source))
        ? onTap
        : null;
    final semanticChild = excludeSemantics
        ? ExcludeSemantics(child: text)
        : text;
    final paddedChild = Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: semanticChild,
    );
    if (effectiveTap == null) return paddedChild;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: effectiveTap,
        child: paddedChild,
      ),
    );
  }
}

class _LineFragment {
  const _LineFragment({
    required this.source,
    required this.match,
    required this.keyIndex,
  });

  final String source;
  final ExampleWordMatch? match;
  final int keyIndex;
}

List<List<_LineFragment>> _splitFragmentsIntoLines(
  List<_LinkedSourceFragment> fragments,
) {
  final lines = <List<_LineFragment>>[<_LineFragment>[]];
  var nextSyntheticKey = fragments.length;

  for (final (fragmentIndex, fragment) in fragments.indexed) {
    final parts = fragment.source.split(RegExp(r'\r\n|\n|\r'));
    var usedOriginalKey = false;
    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      final part = parts[partIndex];
      if (part.isNotEmpty) {
        lines.last.add(
          _LineFragment(
            source: part,
            // Indexed dictionary surfaces never contain a line break. If
            // malformed external data does, keeping it unlinked is safer than
            // duplicating one semantic link across multiple visual lines.
            match: parts.length == 1 ? fragment.match : null,
            keyIndex: usedOriginalKey ? nextSyntheticKey++ : fragmentIndex,
          ),
        );
        usedOriginalKey = true;
      }
      if (partIndex < parts.length - 1) lines.add(<_LineFragment>[]);
    }
  }
  return lines;
}

class _IndexedSurface {
  const _IndexedSurface({
    required this.word,
    required this.surface,
    required this.readings,
    required this.candidateWords,
    required this.runeLength,
    required this.isKanjiOnly,
  });

  final JapaneseWord word;
  final String surface;
  final List<String> readings;
  final List<JapaneseWord> candidateWords;
  final int runeLength;
  final bool isKanjiOnly;
}

class _SurfaceChoice {
  const _SurfaceChoice({
    required this.word,
    required this.readings,
    required this.priority,
    required this.catalogOrder,
  });

  final JapaneseWord word;
  final List<String> readings;
  final int priority;
  final int catalogOrder;

  bool isPreferredTo(_SurfaceChoice other) =>
      priority > other.priority ||
      (priority == other.priority && catalogOrder < other.catalogOrder);
}

class _LinkedSourceFragment {
  const _LinkedSourceFragment(this.source, this.match);

  final String source;
  final ExampleWordMatch? match;
}

class _MappedAozoraSource {
  _MappedAozoraSource(String source)
    : normalizedSource = source.replaceAllMapped(_rubyPattern, (match) {
        return buildAozoraRubySource(match.group(1)!, match.group(2)!);
      }) {
    final plain = StringBuffer();
    final boundaries = <int, int>{0: 0};
    var rawCursor = 0;

    void addPlain(String value, int rawStart) {
      var plainOffset = plain.length;
      var rawOffset = rawStart;
      boundaries[plainOffset] = rawOffset;
      for (final rune in value.runes) {
        plain.writeCharCode(rune);
        final width = rune > 0xFFFF ? 2 : 1;
        plainOffset += width;
        rawOffset += width;
        boundaries[plainOffset] = rawOffset;
      }
    }

    for (final match in _rubyPattern.allMatches(normalizedSource)) {
      if (match.start > rawCursor) {
        addPlain(normalizedSource.substring(rawCursor, match.start), rawCursor);
      }
      final base = match.group(1)!;
      boundaries[plain.length] = match.start;
      plain.write(base);
      boundaries[plain.length] = match.end;
      rawCursor = match.end;
    }
    if (rawCursor < normalizedSource.length) {
      addPlain(normalizedSource.substring(rawCursor), rawCursor);
    }

    plainText = plain.toString();
    _rawOffsetByPlainBoundary = Map<int, int>.unmodifiable(boundaries);
  }

  static final RegExp _rubyPattern = RegExp(r'｜([^《]+)《([^》]+)》');

  final String normalizedSource;
  late final String plainText;
  late final Map<int, int> _rawOffsetByPlainBoundary;

  String? sourceForPlainRange(int start, int end) {
    final rawStart = _rawOffsetByPlainBoundary[start];
    final rawEnd = _rawOffsetByPlainBoundary[end];
    if (rawStart == null || rawEnd == null || rawStart > rawEnd) return null;
    return normalizedSource.substring(rawStart, rawEnd);
  }

  List<_LinkedSourceFragment> fragmentsFor(List<ExampleWordMatch> matches) {
    final fragments = <_LinkedSourceFragment>[];
    var rawCursor = 0;
    for (final match in matches) {
      final rawStart = _rawOffsetByPlainBoundary[match.start];
      final rawEnd = _rawOffsetByPlainBoundary[match.end];
      // A match inside one indivisible kanji ruby run cannot be sliced without
      // assigning a speculative partial reading, so leave that match plain.
      if (rawStart == null || rawEnd == null) continue;
      if (rawStart > rawCursor) {
        fragments.add(
          _LinkedSourceFragment(
            normalizedSource.substring(rawCursor, rawStart),
            null,
          ),
        );
      }
      fragments.add(
        _LinkedSourceFragment(
          normalizedSource.substring(rawStart, rawEnd),
          match,
        ),
      );
      rawCursor = rawEnd;
    }
    if (rawCursor < normalizedSource.length) {
      fragments.add(
        _LinkedSourceFragment(normalizedSource.substring(rawCursor), null),
      );
    }
    return fragments;
  }
}

List<String> _focusReadings(ExampleSentence example) {
  final focus = example.focusSurface.trim();
  if (focus.isEmpty) return const [];
  if (!focus.runes.any(_isKanji)) return [focus];

  final mapped = _MappedAozoraSource(example.ruby);
  final start = mapped.plainText.indexOf(focus);
  if (start < 0) return const [];
  final source = mapped.sourceForPlainRange(start, start + focus.length);
  if (source == null) return const [];
  final reading = spokenAozoraRuby(source).trim();
  if (reading.isEmpty || reading.runes.any(_isKanji)) return const [];
  return [reading];
}

bool _containsJapanese(String source) =>
    source.runes.any((rune) => _isKanji(rune) || _isKana(rune));

bool _isKana(int rune) =>
    (rune >= 0x3040 && rune <= 0x309F) ||
    (rune >= 0x30A0 && rune <= 0x30FF) ||
    (rune >= 0xFF66 && rune <= 0xFF9D);

bool _isKanji(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    rune == 0x3005 ||
    rune == 0x3006 ||
    rune == 0x3007 ||
    rune == 0x30F6;
