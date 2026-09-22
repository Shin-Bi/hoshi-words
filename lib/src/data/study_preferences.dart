import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoredStudyState {
  const StoredStudyState({
    required this.selectedLevelName,
    required this.selectedWordLevelNames,
    required this.bookmarkedIds,
    required this.bookmarkedAtByWord,
    required this.knownIds,
    required this.knownAtByWord,
    required this.todayStudiedIds,
    required this.todayKey,
    required this.activeDateKeys,
    required this.totalQuizAnswers,
    required this.correctQuizAnswers,
    required this.quizAttemptsByWord,
    required this.quizCorrectByWord,
    required this.reviewDueAtByWord,
    required this.reviewStreakByWord,
    required this.lastQuizAtByWord,
    required this.grammarMasteredIds,
    required this.grammarAttemptsByPoint,
    required this.grammarCorrectByPoint,
    required this.grammarLastStudiedAtByPoint,
    required this.dailyGoal,
    required this.wordSortName,
    required this.wordSortDirectionName,
    required this.wordSearchScopeNames,
    required this.showWordFurigana,
    required this.showWordMeaning,
    required this.showWordPartOfSpeech,
    required this.wordListBookmarkedOnly,
    required this.wordListExcludeKnown,
    required this.wordListKnownOnly,
    required this.todayDeckSeed,
    required this.todayDeckIndex,
    required this.showTodayFurigana,
    required this.showTodayFrontMeaning,
    required this.showTodayMeaning,
    required this.showTodayForms,
    required this.showDetailForms,
    required this.showTodayExamples,
    required this.showTodayExampleFurigana,
    required this.showTodayLiteralTranslation,
    required this.showTodayNaturalTranslation,
  });

  final String selectedLevelName;
  final Set<String> selectedWordLevelNames;
  final Set<String> bookmarkedIds;
  final Map<String, int> bookmarkedAtByWord;
  final Set<String> knownIds;
  final Map<String, int> knownAtByWord;
  final Set<String> todayStudiedIds;
  final String todayKey;
  final Set<String> activeDateKeys;
  final int totalQuizAnswers;
  final int correctQuizAnswers;
  final Map<String, int> quizAttemptsByWord;
  final Map<String, int> quizCorrectByWord;
  final Map<String, int> reviewDueAtByWord;
  final Map<String, int> reviewStreakByWord;
  final Map<String, int> lastQuizAtByWord;
  final Set<String> grammarMasteredIds;
  final Map<String, int> grammarAttemptsByPoint;
  final Map<String, int> grammarCorrectByPoint;
  final Map<String, int> grammarLastStudiedAtByPoint;
  final int dailyGoal;
  final String wordSortName;
  final String wordSortDirectionName;
  final Set<String> wordSearchScopeNames;
  final bool showWordFurigana;
  final bool showWordMeaning;
  final bool showWordPartOfSpeech;
  final bool wordListBookmarkedOnly;
  final bool wordListExcludeKnown;
  final bool wordListKnownOnly;
  final int todayDeckSeed;
  final int todayDeckIndex;
  final bool showTodayFurigana;
  final bool showTodayFrontMeaning;
  final bool showTodayMeaning;
  final bool showTodayForms;
  final bool showDetailForms;
  final bool showTodayExamples;
  final bool showTodayExampleFurigana;
  final bool showTodayLiteralTranslation;
  final bool showTodayNaturalTranslation;
}

class StudyPreferences {
  StudyPreferences._(this._preferences);

  static const _prefix = 'kotobaMoon.';
  static const _stateKey = '${_prefix}state.v4';
  static const _previousStateKey = '${_prefix}state.v3';
  static const _olderStateKey = '${_prefix}state.v2';
  static const _legacyStateKey = '${_prefix}state.v1';
  static const _selectedLevelKey = '${_prefix}selectedLevel';
  static const _bookmarksKey = '${_prefix}bookmarks';
  static const _todayStudiedKey = '${_prefix}todayStudied';
  static const _todayKey = '${_prefix}todayKey';
  static const _activeDatesKey = '${_prefix}activeDates';
  static const _totalQuizAnswersKey = '${_prefix}totalQuizAnswers';
  static const _correctQuizAnswersKey = '${_prefix}correctQuizAnswers';
  static const _dailyGoalKey = '${_prefix}dailyGoal';
  static const _todayDeckPositionOverlayKey =
      '${_prefix}todayDeckPosition.current';

  final SharedPreferences _preferences;
  bool _readCurrentState = false;

  /// Whether [read] restored the current v4 document rather than defaults or
  /// an older schema that still needs a one-time migration write.
  bool get readCurrentState => _readCurrentState;

  static Future<StudyPreferences> load() async {
    return StudyPreferences._(await SharedPreferences.getInstance());
  }

  StoredStudyState read({required String currentDateKey}) {
    final state = _readStateJson();
    String stringValue(String field, String legacyKey, String fallback) {
      final value = state?[field];
      return value is String
          ? value
          : _preferences.getString(legacyKey) ?? fallback;
    }

    int intValue(String field, String legacyKey, int fallback) {
      final value = state?[field];
      return value is int ? value : _preferences.getInt(legacyKey) ?? fallback;
    }

    bool boolValue(String field, bool fallback) {
      final value = state?[field];
      return value is bool ? value : fallback;
    }

    Set<String> stringSetValue(String field, String legacyKey) {
      final value = state?[field];
      if (value is List) {
        return value.whereType<String>().toSet();
      }
      return _stringSet(legacyKey);
    }

    Map<String, int> intMapValue(String field) {
      final value = state?[field];
      if (value is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in value.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt().clamp(0, 1 << 31),
      };
    }

    Map<String, int> timestampMapValue(String field) {
      final value = state?[field];
      if (value is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in value.entries)
          if (entry.key is String &&
              entry.value is num &&
              (entry.value as num).toInt() > 0 &&
              (entry.value as num).toInt() <= 8640000000000000)
            entry.key as String: (entry.value as num).toInt(),
      };
    }

    final storedTodayKey = stringValue('todayKey', _todayKey, '');
    final isToday = storedTodayKey == currentDateKey;
    final selectedLevelName = stringValue(
      'selectedLevel',
      _selectedLevelKey,
      'n5',
    );
    final selectedWordLevels = state?['selectedWordLevels'];
    final wordSearchScopes = state?['wordSearchScopes'];
    final todayDeckSeed = intValue(
      'todayDeckSeed',
      '${_prefix}todayDeckSeed',
      DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
    );
    return StoredStudyState(
      selectedLevelName: selectedLevelName,
      selectedWordLevelNames: selectedWordLevels is List
          ? selectedWordLevels.whereType<String>().toSet()
          : <String>{'n5', 'n4', 'n3', 'n2', 'n1'},
      bookmarkedIds: stringSetValue('bookmarks', _bookmarksKey),
      // Bookmarks from versions before status timestamps deliberately remain
      // valid with an unknown time (no map entry).
      bookmarkedAtByWord: timestampMapValue('bookmarkedAtByWord'),
      knownIds: stringSetValue('knownIds', '${_prefix}knownIds'),
      knownAtByWord: timestampMapValue('knownAtByWord'),
      todayStudiedIds: isToday
          ? stringSetValue('todayStudied', _todayStudiedKey)
          : <String>{},
      todayKey: currentDateKey,
      activeDateKeys: stringSetValue('activeDates', _activeDatesKey),
      totalQuizAnswers: intValue('totalQuizAnswers', _totalQuizAnswersKey, 0),
      correctQuizAnswers: intValue(
        'correctQuizAnswers',
        _correctQuizAnswersKey,
        0,
      ),
      quizAttemptsByWord: intMapValue('quizAttemptsByWord'),
      quizCorrectByWord: intMapValue('quizCorrectByWord'),
      reviewDueAtByWord: timestampMapValue('reviewDueAtByWord'),
      reviewStreakByWord: intMapValue('reviewStreakByWord'),
      lastQuizAtByWord: timestampMapValue('lastQuizAtByWord'),
      grammarMasteredIds: stringSetValue(
        'grammarMasteredIds',
        '${_prefix}grammarMasteredIds',
      ),
      grammarAttemptsByPoint: intMapValue('grammarAttemptsByPoint'),
      grammarCorrectByPoint: intMapValue('grammarCorrectByPoint'),
      grammarLastStudiedAtByPoint: timestampMapValue(
        'grammarLastStudiedAtByPoint',
      ),
      dailyGoal: intValue('dailyGoal', _dailyGoalKey, 10).clamp(5, 30),
      wordSortName: state?['wordSort'] is String
          ? state!['wordSort'] as String
          : 'basic',
      // v1-v4 documents created before directional sorting omit this field.
      // Ascending exactly matches their basic/gojuon behavior.
      wordSortDirectionName: state?['wordSortDirection'] is String
          ? state!['wordSortDirection'] as String
          : 'ascending',
      // Older v4 documents predate scoped search and therefore restore the
      // original all-fields behavior.
      wordSearchScopeNames: wordSearchScopes is List
          ? wordSearchScopes.whereType<String>().toSet()
          : <String>{'lemma', 'reading', 'meaning', 'example'},
      showWordFurigana: boolValue('showWordFurigana', true),
      showWordMeaning: boolValue('showWordMeaning', true),
      // Older v4 documents predate this display option and previously always
      // showed the part-of-speech badge.
      showWordPartOfSpeech: boolValue('showWordPartOfSpeech', true),
      wordListBookmarkedOnly: boolValue('wordListBookmarkedOnly', false),
      wordListExcludeKnown: boolValue('wordListExcludeKnown', false),
      wordListKnownOnly: boolValue('wordListKnownOnly', false),
      todayDeckSeed: todayDeckSeed,
      todayDeckIndex: _readCurrentState
          ? _readTodayDeckPosition(todayDeckSeed) ??
                intValue('todayDeckIndex', '${_prefix}todayDeckIndex', 0)
          : intValue('todayDeckIndex', '${_prefix}todayDeckIndex', 0),
      showTodayFurigana: boolValue('showTodayFurigana', true),
      // This is deliberately a new preference instead of reusing the old
      // back-face meaning option. Existing users should still start each card
      // with the answer hidden.
      showTodayFrontMeaning: boolValue('showTodayFrontMeaning', false),
      showTodayMeaning: boolValue('showTodayMeaning', true),
      showTodayForms: boolValue('showTodayForms', true),
      showDetailForms: boolValue('showDetailForms', true),
      showTodayExamples: boolValue('showTodayExamples', true),
      showTodayExampleFurigana: boolValue('showTodayExampleFurigana', true),
      showTodayLiteralTranslation: boolValue(
        'showTodayLiteralTranslation',
        true,
      ),
      showTodayNaturalTranslation: boolValue(
        'showTodayNaturalTranslation',
        true,
      ),
    );
  }

  Map<String, dynamic>? _readStateJson() {
    final currentSource = _preferences.getString(_stateKey);
    if (currentSource != null && currentSource.isNotEmpty) {
      final current = _decodeStateJson(currentSource);
      _readCurrentState =
          current?['schemaVersion'] == 4 && current?['todayDeckSeed'] is int;
      return current;
    }
    _readCurrentState = false;
    final source =
        _preferences.getString(_previousStateKey) ??
        _preferences.getString(_olderStateKey) ??
        _preferences.getString(_legacyStateKey);
    if (source == null || source.isEmpty) return null;
    return _decodeStateJson(source);
  }

  Map<String, dynamic>? _decodeStateJson(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Set<String> _stringSet(String key) {
    return (_preferences.getStringList(key) ?? const <String>[]).toSet();
  }

  int? _readTodayDeckPosition(int expectedSeed) {
    final encoded = _preferences.getString(_todayDeckPositionOverlayKey);
    if (encoded == null) return null;
    final separator = encoded.indexOf(':');
    if (separator <= 0) return null;
    final seed = int.tryParse(encoded.substring(0, separator));
    final index = int.tryParse(encoded.substring(separator + 1));
    return seed == expectedSeed ? index : null;
  }

  Future<void> save({
    required String selectedLevelName,
    required Set<String> selectedWordLevelNames,
    required Set<String> bookmarkedIds,
    required Map<String, int> bookmarkedAtByWord,
    required Set<String> knownIds,
    required Map<String, int> knownAtByWord,
    required Set<String> todayStudiedIds,
    required String todayKey,
    required Set<String> activeDateKeys,
    required int totalQuizAnswers,
    required int correctQuizAnswers,
    required Map<String, int> quizAttemptsByWord,
    required Map<String, int> quizCorrectByWord,
    required Map<String, int> reviewDueAtByWord,
    required Map<String, int> reviewStreakByWord,
    required Map<String, int> lastQuizAtByWord,
    required Set<String> grammarMasteredIds,
    required Map<String, int> grammarAttemptsByPoint,
    required Map<String, int> grammarCorrectByPoint,
    required Map<String, int> grammarLastStudiedAtByPoint,
    required int dailyGoal,
    required String wordSortName,
    required String wordSortDirectionName,
    required Set<String> wordSearchScopeNames,
    required bool showWordFurigana,
    required bool showWordMeaning,
    required bool showWordPartOfSpeech,
    required bool wordListBookmarkedOnly,
    required bool wordListExcludeKnown,
    required bool wordListKnownOnly,
    required int todayDeckSeed,
    required int todayDeckIndex,
    required bool showTodayFurigana,
    required bool showTodayFrontMeaning,
    required bool showTodayMeaning,
    required bool showTodayForms,
    required bool showDetailForms,
    required bool showTodayExamples,
    required bool showTodayExampleFurigana,
    required bool showTodayLiteralTranslation,
    required bool showTodayNaturalTranslation,
  }) async {
    final payload = <String, Object?>{
      'selectedLevel': selectedLevelName,
      'selectedWordLevels': selectedWordLevelNames,
      'bookmarks': bookmarkedIds,
      'bookmarkedAtByWord': bookmarkedAtByWord,
      'knownIds': knownIds,
      'knownAtByWord': knownAtByWord,
      'todayStudied': todayStudiedIds,
      'todayKey': todayKey,
      'activeDates': activeDateKeys,
      'totalQuizAnswers': totalQuizAnswers,
      'correctQuizAnswers': correctQuizAnswers,
      'quizAttemptsByWord': quizAttemptsByWord,
      'quizCorrectByWord': quizCorrectByWord,
      'reviewDueAtByWord': reviewDueAtByWord,
      'reviewStreakByWord': reviewStreakByWord,
      'lastQuizAtByWord': lastQuizAtByWord,
      'grammarMasteredIds': grammarMasteredIds,
      'grammarAttemptsByPoint': grammarAttemptsByPoint,
      'grammarCorrectByPoint': grammarCorrectByPoint,
      'grammarLastStudiedAtByPoint': grammarLastStudiedAtByPoint,
      'dailyGoal': dailyGoal,
      'wordSort': wordSortName,
      'wordSortDirection': wordSortDirectionName,
      'wordSearchScopes': wordSearchScopeNames,
      'showWordFurigana': showWordFurigana,
      'showWordMeaning': showWordMeaning,
      'showWordPartOfSpeech': showWordPartOfSpeech,
      'wordListBookmarkedOnly': wordListBookmarkedOnly,
      'wordListExcludeKnown': wordListExcludeKnown,
      'wordListKnownOnly': wordListKnownOnly,
      'todayDeckSeed': todayDeckSeed,
      'todayDeckIndex': todayDeckIndex,
      'showTodayFurigana': showTodayFurigana,
      'showTodayFrontMeaning': showTodayFrontMeaning,
      'showTodayMeaning': showTodayMeaning,
      'showTodayForms': showTodayForms,
      'showDetailForms': showDetailForms,
      'showTodayExamples': showTodayExamples,
      'showTodayExampleFurigana': showTodayExampleFurigana,
      'showTodayLiteralTranslation': showTodayLiteralTranslation,
      'showTodayNaturalTranslation': showTodayNaturalTranslation,
    };
    final collectionSize =
        selectedWordLevelNames.length +
        wordSearchScopeNames.length +
        bookmarkedIds.length +
        bookmarkedAtByWord.length +
        knownIds.length +
        knownAtByWord.length +
        todayStudiedIds.length +
        activeDateKeys.length +
        quizAttemptsByWord.length +
        quizCorrectByWord.length +
        reviewDueAtByWord.length +
        reviewStreakByWord.length +
        lastQuizAtByWord.length +
        grammarMasteredIds.length +
        grammarAttemptsByPoint.length +
        grammarCorrectByPoint.length +
        grammarLastStudiedAtByPoint.length;
    final state = collectionSize >= 256
        ? await compute(
            _encodeStudyState,
            payload,
            debugLabel: '별빛 단어 학습 상태 직렬화',
          )
        : _encodeStudyState(payload);
    // Invalidate the position overlay before committing the full document.
    // If the process stops between writes, restore falls back to the index in
    // whichever complete v4 document is present instead of combining a new
    // known-word deck with an old same-seed position.
    if (_preferences.containsKey(_todayDeckPositionOverlayKey) &&
        !await _preferences.remove(_todayDeckPositionOverlayKey)) {
      throw StateError('오늘의 단어 위치 임시값을 정리하지 못했습니다.');
    }
    if (_preferences.getString(_stateKey) != state &&
        !await _preferences.setString(_stateKey, state)) {
      throw StateError('학습 상태를 기기에 저장하지 못했습니다.');
    }
    await saveTodayDeckIndex(seed: todayDeckSeed, index: todayDeckIndex);
  }

  /// Persists carousel movement without rewriting bookmarks and per-word quiz
  /// maps. The overlay is read ahead of the v4 field and is also refreshed by
  /// every full save, so both paths converge after any other state change.
  Future<void> saveTodayDeckIndex({
    required int seed,
    required int index,
  }) async {
    final encoded = '$seed:$index';
    if (_preferences.getString(_todayDeckPositionOverlayKey) == encoded) return;
    if (!await _preferences.setString(_todayDeckPositionOverlayKey, encoded)) {
      throw StateError('오늘의 단어 위치를 기기에 저장하지 못했습니다.');
    }
  }
}

String _encodeStudyState(Map<String, Object?> payload) {
  List<String> sortedSet(String field) {
    return (payload[field]! as Set<String>).toList()..sort();
  }

  return jsonEncode({
    'schemaVersion': 4,
    ...payload,
    'selectedWordLevels': sortedSet('selectedWordLevels'),
    'wordSearchScopes': sortedSet('wordSearchScopes'),
    'bookmarks': sortedSet('bookmarks'),
    'knownIds': sortedSet('knownIds'),
    'grammarMasteredIds': sortedSet('grammarMasteredIds'),
    'bookmarkedAtByWord': _sortedIntMap(
      payload['bookmarkedAtByWord']! as Map<String, int>,
    ),
    'knownAtByWord': _sortedIntMap(
      payload['knownAtByWord']! as Map<String, int>,
    ),
    'todayStudied': sortedSet('todayStudied'),
    'activeDates': sortedSet('activeDates'),
    'quizAttemptsByWord': _sortedIntMap(
      payload['quizAttemptsByWord']! as Map<String, int>,
    ),
    'quizCorrectByWord': _sortedIntMap(
      payload['quizCorrectByWord']! as Map<String, int>,
    ),
    'reviewDueAtByWord': _sortedIntMap(
      payload['reviewDueAtByWord']! as Map<String, int>,
    ),
    'reviewStreakByWord': _sortedIntMap(
      payload['reviewStreakByWord']! as Map<String, int>,
    ),
    'lastQuizAtByWord': _sortedIntMap(
      payload['lastQuizAtByWord']! as Map<String, int>,
    ),
    'grammarAttemptsByPoint': _sortedIntMap(
      payload['grammarAttemptsByPoint']! as Map<String, int>,
    ),
    'grammarCorrectByPoint': _sortedIntMap(
      payload['grammarCorrectByPoint']! as Map<String, int>,
    ),
    'grammarLastStudiedAtByPoint': _sortedIntMap(
      payload['grammarLastStudiedAtByPoint']! as Map<String, int>,
    ),
  });
}

Map<String, int> _sortedIntMap(Map<String, int> source) {
  final keys = source.keys.toList()..sort();
  return <String, int>{for (final key in keys) key: source[key]!};
}
