import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/study_preferences.dart';
import '../domain/vocabulary.dart';

enum WordSortOption { basic, gojuon, accuracy, bookmarkTime, knownTime, random }

enum WordSortDirection { ascending, descending }

class LevelProgress {
  const LevelProgress({required this.total, required this.bookmarked});

  final int total;
  final int bookmarked;
}

enum WeakReviewReason { recentMistake, lowAccuracy, scheduled, firstCheck }

class WeakReviewItem {
  const WeakReviewItem({
    required this.word,
    required this.reason,
    required this.attempts,
    required this.correct,
    this.dueAt,
  });

  final JapaneseWord word;
  final WeakReviewReason reason;
  final int attempts;
  final int correct;
  final DateTime? dueAt;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  String get reasonLabel => switch (reason) {
    WeakReviewReason.recentMistake => '최근 오답',
    WeakReviewReason.lowAccuracy => '정답률 ${(accuracy * 100).round()}%',
    WeakReviewReason.scheduled => '복습할 때',
    WeakReviewReason.firstCheck => '첫 확인',
  };
}

class StudyController extends ChangeNotifier {
  StudyController._({
    required List<JapaneseWord> words,
    required StudyPreferences preferences,
    required StoredStudyState stored,
    DateTime Function()? now,
    Future<void> Function()? debugBeforePersistence,
  }) : _words = List.unmodifiable(words),
       _preferences = preferences,
       _now = now ?? DateTime.now,
       _debugBeforePersistence = debugBeforePersistence,
       _selectedLevel = _levelFromName(stored.selectedLevelName),
       _selectedWordLevels = _levelsFromNames(
         stored.selectedWordLevelNames,
         fallback: _levelFromName(stored.selectedLevelName),
       ),
       _bookmarkedIds = stored.bookmarkedIds,
       _bookmarkedAtByWord = stored.bookmarkedAtByWord,
       _knownIds = stored.knownIds,
       _knownAtByWord = stored.knownAtByWord,
       _todayStudiedIds = stored.todayStudiedIds,
       _activeDateKeys = stored.activeDateKeys,
       _todayKey = stored.todayKey,
       _totalQuizAnswers = stored.totalQuizAnswers,
       _correctQuizAnswers = stored.correctQuizAnswers,
       _quizAttemptsByWord = stored.quizAttemptsByWord,
       _quizCorrectByWord = stored.quizCorrectByWord,
       _reviewDueAtByWord = stored.reviewDueAtByWord,
       _reviewStreakByWord = stored.reviewStreakByWord,
       _lastQuizAtByWord = stored.lastQuizAtByWord,
       _grammarMasteredIds = stored.grammarMasteredIds,
       _grammarAttemptsByPoint = stored.grammarAttemptsByPoint,
       _grammarCorrectByPoint = stored.grammarCorrectByPoint,
       _grammarLastStudiedAtByPoint = stored.grammarLastStudiedAtByPoint,
       _dailyGoal = stored.dailyGoal,
       _wordSort = _wordSortFromName(stored.wordSortName),
       _wordSortDirection = _wordSortDirectionFromName(
         stored.wordSortDirectionName,
       ),
       _wordSearchScopes = _searchScopesFromNames(stored.wordSearchScopeNames),
       _showWordFurigana = stored.showWordFurigana,
       _showWordMeaning = stored.showWordMeaning,
       _showWordPartOfSpeech = stored.showWordPartOfSpeech,
       _wordListBookmarkedOnly = stored.wordListBookmarkedOnly,
       _wordListExcludeKnown = stored.wordListExcludeKnown,
       _wordListKnownOnly = stored.wordListKnownOnly,
       _todayDeckSeed = stored.todayDeckSeed,
       _todayDeckIndex = stored.todayDeckIndex,
       _showTodayFurigana = stored.showTodayFurigana,
       _showTodayFrontMeaning = stored.showTodayFrontMeaning,
       _showTodayMeaning = stored.showTodayMeaning,
       _showTodayForms = stored.showTodayForms,
       _showDetailForms = stored.showDetailForms,
       _showTodayExamples = stored.showTodayExamples,
       _showTodayExampleFurigana = stored.showTodayExampleFurigana,
       _showTodayLiteralTranslation = stored.showTodayLiteralTranslation,
       _showTodayNaturalTranslation = stored.showTodayNaturalTranslation {
    final wordById = <String, JapaneseWord>{};
    final mutableWordsByLevel = <JlptLevel, List<JapaneseWord>>{
      for (final level in JlptLevel.values) level: <JapaneseWord>[],
    };
    final mutableWordIdsByLevel = <JlptLevel, Set<String>>{
      for (final level in JlptLevel.values) level: <String>{},
    };
    for (final word in _words) {
      wordById[word.id] = word;
      mutableWordsByLevel[word.level]!.add(word);
      mutableWordIdsByLevel[word.level]!.add(word.id);
    }
    _wordById = Map<String, JapaneseWord>.unmodifiable(wordById);
    _wordsByLevel = Map<JlptLevel, List<JapaneseWord>>.unmodifiable({
      for (final level in JlptLevel.values)
        level: List<JapaneseWord>.unmodifiable(mutableWordsByLevel[level]!),
    });
    _wordIdsByLevel = Map<JlptLevel, Set<String>>.unmodifiable({
      for (final level in JlptLevel.values)
        level: Set<String>.unmodifiable(mutableWordIdsByLevel[level]!),
    });
    var basicOrder = 0;
    _basicOrderById = Map<String, int>.unmodifiable({
      for (final level in JlptLevel.values)
        for (final word in _wordsByLevel[level]!) word.id: basicOrder++,
    });
    _selectedWordLevelsView = Set<JlptLevel>.unmodifiable(_selectedWordLevels);
    _wordSearchScopesView = Set<VocabularySearchScope>.unmodifiable(
      _wordSearchScopes,
    );
    final availableIds = _wordById.keys.toSet();
    _bookmarkedIds.retainAll(availableIds);
    _knownIds.retainAll(availableIds);
    _bookmarkedAtByWord.removeWhere(
      (id, _) => !availableIds.contains(id) || !_bookmarkedIds.contains(id),
    );
    _knownAtByWord.removeWhere(
      (id, _) => !availableIds.contains(id) || !_knownIds.contains(id),
    );
    // These filters are logical opposites. Prefer the explicit positive filter
    // if a malformed or future state document enables both.
    if (_wordListKnownOnly && _wordListExcludeKnown) {
      _wordListExcludeKnown = false;
    }
    _todayStudiedIds.retainAll(availableIds);
    _quizAttemptsByWord.removeWhere(
      (id, attempts) => !availableIds.contains(id) || attempts <= 0,
    );
    _quizCorrectByWord.removeWhere(
      (id, correct) => !availableIds.contains(id) || correct <= 0,
    );
    for (final entry in _quizCorrectByWord.entries.toList()) {
      final attempts = _quizAttemptsByWord[entry.key] ?? 0;
      if (attempts == 0) {
        _quizCorrectByWord.remove(entry.key);
      } else if (entry.value > attempts) {
        _quizCorrectByWord[entry.key] = attempts;
      }
    }
    _reviewDueAtByWord.removeWhere((id, _) => !availableIds.contains(id));
    _reviewStreakByWord.removeWhere(
      (id, streak) => !availableIds.contains(id) || streak <= 0,
    );
    _lastQuizAtByWord.removeWhere((id, _) => !availableIds.contains(id));
    _grammarMasteredIds.removeWhere((id) => id.trim().isEmpty);
    _grammarAttemptsByPoint.removeWhere(
      (id, attempts) => id.trim().isEmpty || attempts <= 0,
    );
    _grammarCorrectByPoint.removeWhere(
      (id, correct) =>
          id.trim().isEmpty ||
          correct <= 0 ||
          correct > (_grammarAttemptsByPoint[id] ?? 0),
    );
    _grammarLastStudiedAtByPoint.removeWhere((id, _) => id.trim().isEmpty);
    final deckLength = selectedStudyWords.length;
    _todayDeckIndex = deckLength == 0 ? 0 : _todayDeckIndex % deckLength;
  }

  static Future<StudyController> create(
    List<JapaneseWord> words, {
    DateTime Function()? now,
    @visibleForTesting Future<void> Function()? debugBeforePersistence,
  }) async {
    final preferences = await StudyPreferences.load();
    final clock = now ?? DateTime.now;
    final todayKey = _dateKey(clock());
    final stored = preferences.read(currentDateKey: todayKey);
    final controller = StudyController._(
      words: words,
      preferences: preferences,
      stored: stored,
      now: clock,
      debugBeforePersistence: debugBeforePersistence,
    );
    // Persist migration defaults and the first random deck seed immediately.
    // An already-current v4 document needs no startup rewrite.
    if (!preferences.readCurrentState) {
      controller._scheduleSave();
      await controller.flushPendingWrites();
    }
    return controller;
  }

  final List<JapaneseWord> _words;
  late final Map<String, JapaneseWord> _wordById;
  late final Map<JlptLevel, List<JapaneseWord>> _wordsByLevel;
  late final Map<JlptLevel, Set<String>> _wordIdsByLevel;
  late final Map<String, int> _basicOrderById;
  final StudyPreferences _preferences;
  final DateTime Function() _now;
  final Future<void> Function()? _debugBeforePersistence;
  JlptLevel _selectedLevel;
  final Set<JlptLevel> _selectedWordLevels;
  final Set<String> _bookmarkedIds;
  final Map<String, int> _bookmarkedAtByWord;
  final Set<String> _knownIds;
  final Map<String, int> _knownAtByWord;
  final Set<String> _todayStudiedIds;
  final Set<String> _activeDateKeys;
  String _todayKey;
  int _totalQuizAnswers;
  int _correctQuizAnswers;
  final Map<String, int> _quizAttemptsByWord;
  final Map<String, int> _quizCorrectByWord;
  final Map<String, int> _reviewDueAtByWord;
  final Map<String, int> _reviewStreakByWord;
  final Map<String, int> _lastQuizAtByWord;
  final Set<String> _grammarMasteredIds;
  final Map<String, int> _grammarAttemptsByPoint;
  final Map<String, int> _grammarCorrectByPoint;
  final Map<String, int> _grammarLastStudiedAtByPoint;
  int _dailyGoal;
  WordSortOption _wordSort;
  WordSortDirection _wordSortDirection;
  final Set<VocabularySearchScope> _wordSearchScopes;
  bool _showWordFurigana;
  bool _showWordMeaning;
  bool _showWordPartOfSpeech;
  bool _wordListBookmarkedOnly;
  bool _wordListExcludeKnown;
  bool _wordListKnownOnly;
  int _wordStatusRevision = 0;
  int _todayDeckSeed;
  int _todayDeckIndex;
  bool _showTodayFurigana;
  bool _showTodayFrontMeaning;
  bool _showTodayMeaning;
  bool _showTodayForms;
  bool _showDetailForms;
  bool _showTodayExamples;
  bool _showTodayExampleFurigana;
  bool _showTodayLiteralTranslation;
  bool _showTodayNaturalTranslation;
  late Set<JlptLevel> _selectedWordLevelsView;
  late Set<VocabularySearchScope> _wordSearchScopesView;
  List<JapaneseWord>? _cachedSelectedWordListWords;
  List<JapaneseWord>? _cachedSelectedStudyWords;
  List<JapaneseWord>? _cachedTodayDeck;
  Future<void> _pendingSave = Future<void>.value();
  bool _saveScheduled = false;
  bool _hasUnsavedChanges = false;
  bool _needsFullSave = false;
  bool _fullSaveActive = false;
  int _saveFailureSerial = 0;
  Object? _lastSaveError;
  StackTrace? _lastSaveStackTrace;

  List<JapaneseWord> get words => _words;
  JlptLevel get selectedLevel => _selectedLevel;
  Set<JlptLevel> get selectedWordLevels => _selectedWordLevelsView;
  WordSortOption get wordSort => _wordSort;
  WordSortDirection get wordSortDirection => _wordSortDirection;
  Set<VocabularySearchScope> get wordSearchScopes => _wordSearchScopesView;
  int get wordSearchScopeMask => vocabularySearchScopeMask(_wordSearchScopes);
  bool get showWordFurigana => _showWordFurigana;
  bool get showWordMeaning => _showWordMeaning;
  bool get showWordPartOfSpeech => _showWordPartOfSpeech;
  bool get wordListBookmarkedOnly => _wordListBookmarkedOnly;
  bool get wordListExcludeKnown => _wordListExcludeKnown;
  bool get wordListKnownOnly => _wordListKnownOnly;
  int get wordStatusRevision => _wordStatusRevision;
  bool get showTodayFurigana => _showTodayFurigana;
  bool get showTodayFrontMeaning => _showTodayFrontMeaning;
  bool get showTodayMeaning => _showTodayMeaning;
  bool get showTodayForms => _showTodayForms;
  bool get showDetailForms => _showDetailForms;
  bool get showTodayExamples => _showTodayExamples;
  bool get showTodayExampleFurigana => _showTodayExampleFurigana;
  bool get showTodayLiteralTranslation => _showTodayLiteralTranslation;
  bool get showTodayNaturalTranslation => _showTodayNaturalTranslation;
  int get todayDeckSeed => _todayDeckSeed;
  int get todayDeckIndex => _todayDeckIndex;
  int get totalQuizAnswers => _totalQuizAnswers;
  int get correctQuizAnswers => _correctQuizAnswers;
  int get dailyGoal => _dailyGoal;
  int get studiedTodayCount => _todayStudiedIds.length;
  int get bookmarkCount => _bookmarkedIds.length;
  double get dailyProgress =>
      (_todayStudiedIds.length / _dailyGoal).clamp(0, 1);
  double get quizAccuracy =>
      _totalQuizAnswers == 0 ? 0 : _correctQuizAnswers / _totalQuizAnswers;

  int get grammarMasteredCount => _grammarMasteredIds.length;

  int get streak {
    if (_activeDateKeys.isEmpty) return 0;
    var cursor = DateTime(_now().year, _now().month, _now().day);
    if (!_activeDateKeys.contains(_dateKey(cursor))) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    var count = 0;
    while (_activeDateKeys.contains(_dateKey(cursor))) {
      count += 1;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  List<JapaneseWord> wordsFor(JlptLevel level) => _wordsByLevel[level]!;

  List<JapaneseWord> get selectedWordListWords {
    final cached = _cachedSelectedWordListWords;
    if (cached != null) return cached;
    return _cachedSelectedWordListWords = List<JapaneseWord>.unmodifiable([
      for (final level in JlptLevel.values)
        if (_selectedWordLevels.contains(level)) ..._wordsByLevel[level]!,
    ]);
  }

  /// The selected range prepared for Today, excluding fully known words.
  ///
  /// Wordbook and configurable quizzes should use [selectedWordListWords] so
  /// they can decide independently whether known words are included.
  List<JapaneseWord> get selectedStudyWords {
    final cached = _cachedSelectedStudyWords;
    if (cached != null) return cached;
    return _cachedSelectedStudyWords = List<JapaneseWord>.unmodifiable(
      selectedWordListWords.where((word) => !_knownIds.contains(word.id)),
    );
  }

  /// A stable, randomly ordered deck for the selected demo groups.
  List<JapaneseWord> get todayDeckWords {
    final cached = _cachedTodayDeck;
    if (cached != null) return cached;
    final deck = [...selectedStudyWords];
    final orderById = <String, int>{
      for (final word in deck) word.id: _stableDeckKey(word.id, _todayDeckSeed),
    };
    deck.sort((left, right) {
      final order = orderById[left.id]!.compareTo(orderById[right.id]!);
      return order != 0 ? order : left.id.compareTo(right.id);
    });
    final result = _cachedTodayDeck = List<JapaneseWord>.unmodifiable(deck);
    _todayDeckIndex = result.isEmpty ? 0 : _todayDeckIndex % result.length;
    return result;
  }

  JapaneseWord? get todayWord {
    final deck = todayDeckWords;
    return deck.isEmpty ? null : deck[_todayDeckIndex % deck.length];
  }

  JapaneseWord? wordById(String id) => _wordById[id];

  JapaneseWord? wordOfTheDay([JlptLevel? level]) {
    final candidates = wordsFor(level ?? _selectedLevel);
    if (candidates.isEmpty) return null;
    final now = _now();
    final dayOfYear = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(now.year)).inDays;
    final dayCode =
        now.year * 1000 + dayOfYear + (level ?? _selectedLevel).index * 37;
    return candidates[dayCode % candidates.length];
  }

  LevelProgress progressFor(JlptLevel level) {
    final levelWords = _wordsByLevel[level]!;
    final ids = _wordIdsByLevel[level]!;
    return LevelProgress(
      total: levelWords.length,
      bookmarked: _intersectionCount(ids, _bookmarkedIds),
    );
  }

  bool isBookmarked(String id) => _bookmarkedIds.contains(id);

  int? bookmarkTimestampFor(String id) => _bookmarkedAtByWord[id];

  DateTime? bookmarkedAtFor(String id) {
    final timestamp = bookmarkTimestampFor(id);
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  bool isKnown(String id) => _knownIds.contains(id);

  int? knownTimestampFor(String id) => _knownAtByWord[id];

  DateTime? knownAtFor(String id) {
    final timestamp = knownTimestampFor(id);
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  int quizAttemptsFor(String id) => _quizAttemptsByWord[id] ?? 0;

  int quizCorrectFor(String id) => _quizCorrectByWord[id] ?? 0;

  double quizAccuracyFor(String id) {
    final attempts = quizAttemptsFor(id);
    return attempts == 0 ? 0 : quizCorrectFor(id) / attempts;
  }

  DateTime? reviewDueAtFor(String id) {
    final timestamp = _reviewDueAtByWord[id];
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  DateTime? lastQuizAtFor(String id) {
    final timestamp = _lastQuizAtByWord[id];
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  int reviewStreakFor(String id) => _reviewStreakByWord[id] ?? 0;

  /// Builds today's bounded review queue for the currently selected range.
  ///
  /// Explicitly scheduled cards are respected first. Legacy low-accuracy
  /// records without scheduling metadata follow, then unseen words fill any
  /// remaining daily slots so a new learner can use the feature immediately.
  List<WeakReviewItem> weakReviewQueue({int? limit}) {
    final now = _now();
    final nowMs = now.millisecondsSinceEpoch;
    final due = <WeakReviewItem>[];
    final legacyWeak = <WeakReviewItem>[];
    final unseen = <WeakReviewItem>[];

    for (final word in selectedWordListWords) {
      if (_knownIds.contains(word.id)) continue;
      final attempts = quizAttemptsFor(word.id);
      final correct = quizCorrectFor(word.id);
      final dueTimestamp = _reviewDueAtByWord[word.id];
      if (dueTimestamp != null) {
        if (dueTimestamp <= nowMs) {
          final streak = reviewStreakFor(word.id);
          due.add(
            WeakReviewItem(
              word: word,
              reason: streak == 0
                  ? WeakReviewReason.recentMistake
                  : WeakReviewReason.scheduled,
              attempts: attempts,
              correct: correct,
              dueAt: DateTime.fromMillisecondsSinceEpoch(dueTimestamp),
            ),
          );
        }
        continue;
      }
      if (attempts == 0) {
        unseen.add(
          WeakReviewItem(
            word: word,
            reason: WeakReviewReason.firstCheck,
            attempts: 0,
            correct: 0,
          ),
        );
      } else if (correct / attempts < 0.8) {
        legacyWeak.add(
          WeakReviewItem(
            word: word,
            reason: WeakReviewReason.lowAccuracy,
            attempts: attempts,
            correct: correct,
          ),
        );
      }
    }

    due.sort((left, right) {
      final byDue = left.dueAt!.compareTo(right.dueAt!);
      return byDue != 0 ? byDue : left.accuracy.compareTo(right.accuracy);
    });
    legacyWeak.sort((left, right) {
      final byAccuracy = left.accuracy.compareTo(right.accuracy);
      return byAccuracy != 0
          ? byAccuracy
          : right.attempts.compareTo(left.attempts);
    });
    final dailySeed = now.year * 10000 + now.month * 100 + now.day;
    unseen.sort(
      (left, right) => _stableDeckKey(
        left.word.id,
        dailySeed,
      ).compareTo(_stableDeckKey(right.word.id, dailySeed)),
    );

    final requested = (limit ?? _dailyGoal).clamp(1, 50);
    final priorityItems = [...due, ...legacyWeak].take(requested).toList();
    final answeredToday = _lastQuizAtByWord.values.where((timestamp) {
      return _dateKey(DateTime.fromMillisecondsSinceEpoch(timestamp)) ==
          _dateKey(now);
    }).length;
    final unseenAllowance = mathMin(
      requested - priorityItems.length,
      (requested - answeredToday).clamp(0, requested),
    );
    return List<WeakReviewItem>.unmodifiable([
      ...priorityItems,
      ...unseen.take(unseenAllowance),
    ]);
  }

  bool isGrammarMastered(String id) => _grammarMasteredIds.contains(id);

  int grammarAttemptsFor(String id) => _grammarAttemptsByPoint[id] ?? 0;

  int grammarCorrectFor(String id) => _grammarCorrectByPoint[id] ?? 0;

  double grammarAccuracyFor(String id) {
    final attempts = grammarAttemptsFor(id);
    return attempts == 0 ? 0 : grammarCorrectFor(id) / attempts;
  }

  DateTime? grammarLastStudiedAtFor(String id) {
    final timestamp = _grammarLastStudiedAtByPoint[id];
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  void toggleGrammarMastered(String id) {
    if (id.trim().isEmpty) return;
    if (!_grammarMasteredIds.add(id)) _grammarMasteredIds.remove(id);
    _grammarLastStudiedAtByPoint[id] = _now().millisecondsSinceEpoch;
    notifyListeners();
    _scheduleSave();
  }

  void recordGrammarStudied(String id) {
    if (id.trim().isEmpty) return;
    _grammarLastStudiedAtByPoint[id] = _now().millisecondsSinceEpoch;
    notifyListeners();
    _scheduleSave();
  }

  void recordGrammarAnswer(String id, {required bool correct}) {
    if (id.trim().isEmpty) return;
    _rollToToday();
    _activeDateKeys.add(_todayKey);
    _grammarAttemptsByPoint.update(id, (value) => value + 1, ifAbsent: () => 1);
    if (correct) {
      _grammarCorrectByPoint.update(
        id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    _grammarLastStudiedAtByPoint[id] = _now().millisecondsSinceEpoch;
    notifyListeners();
    _scheduleSave();
  }

  void selectLevel(JlptLevel level) {
    setWordLevels({level});
  }

  void setWordLevels(Set<JlptLevel> levels) {
    if (levels.isEmpty || setEquals(levels, _selectedWordLevels)) return;
    _selectedWordLevels
      ..clear()
      ..addAll(levels);
    _selectedWordLevelsView = Set<JlptLevel>.unmodifiable(_selectedWordLevels);
    _selectedLevel = JlptLevel.values.firstWhere(levels.contains);
    _cachedSelectedWordListWords = null;
    _cachedSelectedStudyWords = null;
    _resetTodayDeck();
    notifyListeners();
    _scheduleSave();
  }

  void setWordSort(WordSortOption value) {
    if (_wordSort == value) return;
    _wordSort = value;
    // Each ordered mode starts from its most familiar direction. Random has
    // no direction, but normalizing the hidden value keeps persisted state
    // deterministic when users later return to an ordered mode.
    _wordSortDirection =
        value == WordSortOption.bookmarkTime ||
            value == WordSortOption.knownTime
        ? WordSortDirection.descending
        : WordSortDirection.ascending;
    notifyListeners();
    _scheduleSave();
  }

  void setWordSortDirection(WordSortDirection value) {
    if (_wordSort == WordSortOption.random || _wordSortDirection == value) {
      return;
    }
    _wordSortDirection = value;
    notifyListeners();
    _scheduleSave();
  }

  void toggleWordSortDirection() {
    if (_wordSort == WordSortOption.random) return;
    setWordSortDirection(
      _wordSortDirection == WordSortDirection.ascending
          ? WordSortDirection.descending
          : WordSortDirection.ascending,
    );
  }

  void setWordSearchScopes(Set<VocabularySearchScope> scopes) {
    if (scopes.isEmpty || setEquals(scopes, _wordSearchScopes)) return;
    _wordSearchScopes
      ..clear()
      ..addAll(scopes);
    _wordSearchScopesView = Set<VocabularySearchScope>.unmodifiable(
      _wordSearchScopes,
    );
    notifyListeners();
    _scheduleSave();
  }

  void setShowWordFurigana(bool value) {
    if (_showWordFurigana == value) return;
    _showWordFurigana = value;
    notifyListeners();
    _scheduleSave();
  }

  void setShowWordMeaning(bool value) {
    if (_showWordMeaning == value) return;
    _showWordMeaning = value;
    notifyListeners();
    _scheduleSave();
  }

  void setShowWordPartOfSpeech(bool value) {
    if (_showWordPartOfSpeech == value) return;
    _showWordPartOfSpeech = value;
    notifyListeners();
    _scheduleSave();
  }

  void setWordListBookmarkedOnly(bool value) {
    if (_wordListBookmarkedOnly == value) return;
    _wordListBookmarkedOnly = value;
    notifyListeners();
    _scheduleSave();
  }

  void setWordListExcludeKnown(bool value) {
    if (_wordListExcludeKnown == value && !(value && _wordListKnownOnly)) {
      return;
    }
    _wordListExcludeKnown = value;
    if (value) _wordListKnownOnly = false;
    notifyListeners();
    _scheduleSave();
  }

  void setWordListKnownOnly(bool value) {
    if (_wordListKnownOnly == value && !(value && _wordListExcludeKnown)) {
      return;
    }
    _wordListKnownOnly = value;
    if (value) _wordListExcludeKnown = false;
    notifyListeners();
    _scheduleSave();
  }

  void setShowTodayFurigana(bool value) => _setTodayOption(
    current: _showTodayFurigana,
    value: value,
    apply: () => _showTodayFurigana = value,
  );

  void setShowTodayFrontMeaning(bool value) => _setTodayOption(
    current: _showTodayFrontMeaning,
    value: value,
    apply: () => _showTodayFrontMeaning = value,
  );

  void setShowTodayMeaning(bool value) => _setTodayOption(
    current: _showTodayMeaning,
    value: value,
    apply: () => _showTodayMeaning = value,
  );

  void setShowTodayForms(bool value) => _setTodayOption(
    current: _showTodayForms,
    value: value,
    apply: () => _showTodayForms = value,
  );

  void setShowDetailForms(bool value) => _setTodayOption(
    current: _showDetailForms,
    value: value,
    apply: () => _showDetailForms = value,
  );

  void setShowTodayExamples(bool value) => _setTodayOption(
    current: _showTodayExamples,
    value: value,
    apply: () => _showTodayExamples = value,
  );

  void setShowTodayExampleFurigana(bool value) => _setTodayOption(
    current: _showTodayExampleFurigana,
    value: value,
    apply: () => _showTodayExampleFurigana = value,
  );

  void setShowTodayLiteralTranslation(bool value) => _setTodayOption(
    current: _showTodayLiteralTranslation,
    value: value,
    apply: () => _showTodayLiteralTranslation = value,
  );

  void setShowTodayNaturalTranslation(bool value) => _setTodayOption(
    current: _showTodayNaturalTranslation,
    value: value,
    apply: () => _showTodayNaturalTranslation = value,
  );

  void advanceTodayCard() {
    final deck = todayDeckWords;
    if (deck.isEmpty) return;
    setTodayDeckIndex(_todayDeckIndex + 1);
  }

  void previousTodayCard() {
    final deck = todayDeckWords;
    if (deck.isEmpty) return;
    setTodayDeckIndex(_todayDeckIndex - 1);
  }

  /// Moves to an exact logical position in the persistent Today deck.
  ///
  /// PageView uses this while presenting the deck as an infinite carousel, so
  /// both ends wrap around without losing the stored logical index.
  void setTodayDeckIndex(int index) {
    final deck = todayDeckWords;
    if (deck.isEmpty) return;
    final normalized = index % deck.length;
    if (_todayDeckIndex == normalized) return;
    _todayDeckIndex = normalized;
    notifyListeners();
    _scheduleSave(indexOnly: true);
  }

  void shuffleTodayDeck() {
    var nextSeed = _now().microsecondsSinceEpoch & 0x7fffffff;
    if (nextSeed == _todayDeckSeed) nextSeed = (nextSeed + 1) & 0x7fffffff;
    _todayDeckSeed = nextSeed;
    _todayDeckIndex = 0;
    _cachedTodayDeck = null;
    notifyListeners();
    _scheduleSave();
  }

  void toggleBookmark(String id) {
    setBookmarked(id, !_bookmarkedIds.contains(id));
  }

  /// Applies an idempotent bookmark state, preserving the originating action
  /// time when native surfaces synchronize after the app resumes.
  void setBookmarked(String id, bool value, {DateTime? changedAt}) {
    if (!_wordById.containsKey(id) || _bookmarkedIds.contains(id) == value) {
      return;
    }
    if (value) {
      _bookmarkedIds.add(id);
      _bookmarkedAtByWord[id] = _normalizedStatusTimestamp(changedAt);
    } else {
      _bookmarkedIds.remove(id);
      _bookmarkedAtByWord.remove(id);
    }
    _wordStatusRevision += 1;
    notifyListeners();
    _scheduleSave();
  }

  void toggleKnown(String id) {
    setKnown(id, !_knownIds.contains(id));
  }

  /// Applies an idempotent known state and keeps the Today deck coherent.
  void setKnown(String id, bool value, {DateTime? changedAt}) {
    final word = _wordById[id];
    if (word == null || _knownIds.contains(id) == value) return;

    final affectsSelectedRange = _selectedWordLevels.contains(word.level);
    final oldDeck = affectsSelectedRange ? _cachedTodayDeck : null;
    final oldDeckIndex = oldDeck == null || oldDeck.isEmpty
        ? 0
        : _todayDeckIndex % oldDeck.length;
    final visibleTodayWordId = oldDeck == null || oldDeck.isEmpty
        ? null
        : oldDeck[oldDeckIndex].id;
    if (value) {
      _knownIds.add(id);
      _knownAtByWord[id] = _normalizedStatusTimestamp(changedAt);
    } else {
      _knownIds.remove(id);
      _knownAtByWord.remove(id);
    }
    _wordStatusRevision += 1;

    if (affectsSelectedRange) {
      _updateSelectedStudyWordsForKnownToggle(word, isNowKnown: value);
      _updateTodayDeckForKnownToggle(
        word,
        isNowKnown: value,
        visibleTodayWordId: visibleTodayWordId,
        fallbackIndex: oldDeckIndex,
      );
    }
    notifyListeners();
    _scheduleSave();
  }

  void recordStudied(String id) {
    if (!_wordById.containsKey(id)) return;
    _rollToToday();
    final changed = _todayStudiedIds.add(id);
    _activeDateKeys.add(_todayKey);
    if (!changed) return;
    notifyListeners();
    _scheduleSave();
  }

  void recordQuizAnswer(String id, {required bool correct}) {
    if (!_wordById.containsKey(id)) return;
    _rollToToday();
    _todayStudiedIds.add(id);
    _activeDateKeys.add(_todayKey);
    _totalQuizAnswers += 1;
    _quizAttemptsByWord.update(id, (value) => value + 1, ifAbsent: () => 1);
    if (correct) {
      _correctQuizAnswers += 1;
      _quizCorrectByWord.update(id, (value) => value + 1, ifAbsent: () => 1);
    }
    final answeredAt = _now();
    final streak = correct ? reviewStreakFor(id) + 1 : 0;
    if (streak == 0) {
      _reviewStreakByWord.remove(id);
    } else {
      _reviewStreakByWord[id] = streak;
    }
    _lastQuizAtByWord[id] = answeredAt.millisecondsSinceEpoch;
    _reviewDueAtByWord[id] = answeredAt
        .add(_reviewInterval(correct: correct, streak: streak))
        .millisecondsSinceEpoch;
    notifyListeners();
    _scheduleSave();
  }

  void setDailyGoal(int value) {
    final next = value.clamp(5, 30);
    if (_dailyGoal == next) return;
    _dailyGoal = next;
    notifyListeners();
    _scheduleSave();
  }

  void refreshForCurrentDay() {
    final current = _dateKey(_now());
    if (current == _todayKey) return;
    _todayKey = current;
    _todayStudiedIds.clear();
    notifyListeners();
    _scheduleSave();
  }

  /// Flushes the latest state snapshot.
  ///
  /// Existing callers keep best-effort behavior by default. Native action
  /// bridges can request [throwOnError] so they acknowledge an external action
  /// only after its corresponding study state is durably stored.
  Future<void> flushPendingWrites({bool throwOnError = false}) async {
    // Tests, app startup migrations, and lifecycle callers can force the
    // latest state through immediately instead of waiting for the coalesced
    // microtask. A previously scheduled microtask becomes a harmless no-op.
    final startingFailureSerial = _saveFailureSerial;
    while (true) {
      _saveScheduled = false;
      _queueLatestSave();
      final pending = _pendingSave;
      await pending;
      if (_saveFailureSerial != startingFailureSerial) {
        if (throwOnError) {
          Error.throwWithStackTrace(_lastSaveError!, _lastSaveStackTrace!);
        }
        return;
      }
      if (!_hasUnsavedChanges && identical(pending, _pendingSave)) return;
    }
  }

  void _rollToToday() {
    final current = _dateKey(_now());
    if (current == _todayKey) return;
    _todayKey = current;
    _todayStudiedIds.clear();
  }

  void _scheduleSave({bool indexOnly = false}) {
    _hasUnsavedChanges = true;
    if (!indexOnly) _needsFullSave = true;
    if (_saveScheduled) return;
    _saveScheduled = true;
    scheduleMicrotask(() {
      _saveScheduled = false;
      _queueLatestSave();
    });
  }

  void _queueLatestSave() {
    if (!_hasUnsavedChanges) return;
    // Keep at most one expensive full snapshot/serialization in flight. While
    // it runs, rapid bookmark/known/quiz changes stay as dirty flags and are
    // captured once from the latest state when the current write completes.
    if (_needsFullSave && _fullSaveActive) return;
    _hasUnsavedChanges = false;
    final needsFullSave = _needsFullSave;
    _needsFullSave = false;

    if (!needsFullSave) {
      final todayDeckSeed = _todayDeckSeed;
      final todayDeckIndex = _todayDeckIndex;
      _pendingSave = _pendingSave.then((_) async {
        try {
          await _debugBeforePersistence?.call();
          await _preferences.saveTodayDeckIndex(
            seed: todayDeckSeed,
            index: todayDeckIndex,
          );
        } catch (error, stackTrace) {
          _hasUnsavedChanges = true;
          _recordSaveFailure(error, stackTrace);
        }
      });
      return;
    }

    final selectedLevelName = _selectedLevel.name;
    final selectedWordLevelNames = _selectedWordLevels
        .map((level) => level.name)
        .toSet();
    final bookmarkedIds = Set<String>.of(_bookmarkedIds);
    final bookmarkedAtByWord = Map<String, int>.of(_bookmarkedAtByWord);
    final knownIds = Set<String>.of(_knownIds);
    final knownAtByWord = Map<String, int>.of(_knownAtByWord);
    final todayStudiedIds = Set<String>.of(_todayStudiedIds);
    final todayKey = _todayKey;
    final activeDateKeys = Set<String>.of(_activeDateKeys);
    final totalQuizAnswers = _totalQuizAnswers;
    final correctQuizAnswers = _correctQuizAnswers;
    final quizAttemptsByWord = Map<String, int>.of(_quizAttemptsByWord);
    final quizCorrectByWord = Map<String, int>.of(_quizCorrectByWord);
    final reviewDueAtByWord = Map<String, int>.of(_reviewDueAtByWord);
    final reviewStreakByWord = Map<String, int>.of(_reviewStreakByWord);
    final lastQuizAtByWord = Map<String, int>.of(_lastQuizAtByWord);
    final grammarMasteredIds = Set<String>.of(_grammarMasteredIds);
    final grammarAttemptsByPoint = Map<String, int>.of(_grammarAttemptsByPoint);
    final grammarCorrectByPoint = Map<String, int>.of(_grammarCorrectByPoint);
    final grammarLastStudiedAtByPoint = Map<String, int>.of(
      _grammarLastStudiedAtByPoint,
    );
    final dailyGoal = _dailyGoal;
    final wordSortName = _wordSort.name;
    final wordSortDirectionName = _wordSortDirection.name;
    final wordSearchScopeNames = _wordSearchScopes
        .map((scope) => scope.name)
        .toSet();
    final showWordFurigana = _showWordFurigana;
    final showWordMeaning = _showWordMeaning;
    final showWordPartOfSpeech = _showWordPartOfSpeech;
    final wordListBookmarkedOnly = _wordListBookmarkedOnly;
    final wordListExcludeKnown = _wordListExcludeKnown;
    final wordListKnownOnly = _wordListKnownOnly;
    final todayDeckSeed = _todayDeckSeed;
    final todayDeckIndex = _todayDeckIndex;
    final showTodayFurigana = _showTodayFurigana;
    final showTodayFrontMeaning = _showTodayFrontMeaning;
    final showTodayMeaning = _showTodayMeaning;
    final showTodayForms = _showTodayForms;
    final showDetailForms = _showDetailForms;
    final showTodayExamples = _showTodayExamples;
    final showTodayExampleFurigana = _showTodayExampleFurigana;
    final showTodayLiteralTranslation = _showTodayLiteralTranslation;
    final showTodayNaturalTranslation = _showTodayNaturalTranslation;
    _fullSaveActive = true;
    var fullSaveFailed = false;
    final fullSave = _pendingSave.then((_) async {
      try {
        await _debugBeforePersistence?.call();
        await _preferences.save(
          selectedLevelName: selectedLevelName,
          selectedWordLevelNames: selectedWordLevelNames,
          bookmarkedIds: bookmarkedIds,
          bookmarkedAtByWord: bookmarkedAtByWord,
          knownIds: knownIds,
          knownAtByWord: knownAtByWord,
          todayStudiedIds: todayStudiedIds,
          todayKey: todayKey,
          activeDateKeys: activeDateKeys,
          totalQuizAnswers: totalQuizAnswers,
          correctQuizAnswers: correctQuizAnswers,
          quizAttemptsByWord: quizAttemptsByWord,
          quizCorrectByWord: quizCorrectByWord,
          reviewDueAtByWord: reviewDueAtByWord,
          reviewStreakByWord: reviewStreakByWord,
          lastQuizAtByWord: lastQuizAtByWord,
          grammarMasteredIds: grammarMasteredIds,
          grammarAttemptsByPoint: grammarAttemptsByPoint,
          grammarCorrectByPoint: grammarCorrectByPoint,
          grammarLastStudiedAtByPoint: grammarLastStudiedAtByPoint,
          dailyGoal: dailyGoal,
          wordSortName: wordSortName,
          wordSortDirectionName: wordSortDirectionName,
          wordSearchScopeNames: wordSearchScopeNames,
          showWordFurigana: showWordFurigana,
          showWordMeaning: showWordMeaning,
          showWordPartOfSpeech: showWordPartOfSpeech,
          wordListBookmarkedOnly: wordListBookmarkedOnly,
          wordListExcludeKnown: wordListExcludeKnown,
          wordListKnownOnly: wordListKnownOnly,
          todayDeckSeed: todayDeckSeed,
          todayDeckIndex: todayDeckIndex,
          showTodayFurigana: showTodayFurigana,
          showTodayFrontMeaning: showTodayFrontMeaning,
          showTodayMeaning: showTodayMeaning,
          showTodayForms: showTodayForms,
          showDetailForms: showDetailForms,
          showTodayExamples: showTodayExamples,
          showTodayExampleFurigana: showTodayExampleFurigana,
          showTodayLiteralTranslation: showTodayLiteralTranslation,
          showTodayNaturalTranslation: showTodayNaturalTranslation,
        );
      } catch (error, stackTrace) {
        fullSaveFailed = true;
        _hasUnsavedChanges = true;
        _needsFullSave = true;
        _recordSaveFailure(error, stackTrace);
      }
    });
    _pendingSave = fullSave.whenComplete(() {
      _fullSaveActive = false;
      if (fullSaveFailed) return;
      if (!_hasUnsavedChanges || _saveScheduled) return;
      _saveScheduled = true;
      scheduleMicrotask(() {
        _saveScheduled = false;
        _queueLatestSave();
      });
    });
  }

  void _recordSaveFailure(Object error, StackTrace stackTrace) {
    _saveFailureSerial += 1;
    _lastSaveError = error;
    _lastSaveStackTrace = stackTrace;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: '별빛 단어 학습 상태 저장',
      ),
    );
  }

  @override
  void dispose() {
    _saveScheduled = false;
    // Starting the final write here preserves the previous controller's
    // best-effort persistence behavior. Callers that need a completion
    // guarantee should await flushPendingWrites before disposing.
    _queueLatestSave();
    super.dispose();
  }

  static JlptLevel _levelFromName(String name) {
    return JlptLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => JlptLevel.n5,
    );
  }

  static Set<JlptLevel> _levelsFromNames(
    Set<String> names, {
    required JlptLevel fallback,
  }) {
    final levels = JlptLevel.values
        .where((level) => names.contains(level.name))
        .toSet();
    return levels.isEmpty ? <JlptLevel>{fallback} : levels;
  }

  static WordSortOption _wordSortFromName(String name) {
    return WordSortOption.values.firstWhere(
      (sort) => sort.name == name,
      orElse: () => WordSortOption.basic,
    );
  }

  static WordSortDirection _wordSortDirectionFromName(String name) {
    return WordSortDirection.values.firstWhere(
      (direction) => direction.name == name,
      orElse: () => WordSortDirection.ascending,
    );
  }

  static Set<VocabularySearchScope> _searchScopesFromNames(Set<String> names) {
    final scopes = VocabularySearchScope.values
        .where((scope) => names.contains(scope.name))
        .toSet();
    return scopes.isEmpty ? VocabularySearchScope.values.toSet() : scopes;
  }

  int _normalizedStatusTimestamp(DateTime? changedAt) {
    final now = _now().millisecondsSinceEpoch;
    if (changedAt == null) return now;
    final candidate = changedAt.millisecondsSinceEpoch;
    return candidate > 0 && candidate <= now ? candidate : now;
  }

  void _setTodayOption({
    required bool current,
    required bool value,
    required VoidCallback apply,
  }) {
    if (current == value) return;
    apply();
    notifyListeners();
    _scheduleSave();
  }

  void _resetTodayDeck() {
    var nextSeed = _now().microsecondsSinceEpoch & 0x7fffffff;
    if (nextSeed == _todayDeckSeed) nextSeed = (nextSeed + 1) & 0x7fffffff;
    _todayDeckSeed = nextSeed;
    _todayDeckIndex = 0;
    _cachedTodayDeck = null;
  }

  void _updateSelectedStudyWordsForKnownToggle(
    JapaneseWord word, {
    required bool isNowKnown,
  }) {
    final cached = _cachedSelectedStudyWords;
    if (cached == null) return;
    final updated = List<JapaneseWord>.of(cached);
    if (isNowKnown) {
      updated.removeWhere((candidate) => candidate.id == word.id);
    } else {
      updated.insert(_basicInsertionIndex(updated, word), word);
    }
    _cachedSelectedStudyWords = List<JapaneseWord>.unmodifiable(updated);
  }

  void _updateTodayDeckForKnownToggle(
    JapaneseWord word, {
    required bool isNowKnown,
    required String? visibleTodayWordId,
    required int fallbackIndex,
  }) {
    final cached = _cachedTodayDeck;
    if (cached == null) {
      // There was no materialized deck (and therefore no visible card) to
      // preserve. Defer the only O(n log n) build until the deck is requested.
      return;
    }

    final updated = List<JapaneseWord>.of(cached);
    if (isNowKnown) {
      updated.removeWhere((candidate) => candidate.id == word.id);
    } else {
      updated.insert(_todayDeckInsertionIndex(updated, word), word);
    }
    _cachedTodayDeck = List<JapaneseWord>.unmodifiable(updated);

    if (updated.isEmpty) {
      _todayDeckIndex = 0;
      return;
    }
    final preservedIndex = visibleTodayWordId == null
        ? -1
        : updated.indexWhere((candidate) => candidate.id == visibleTodayWordId);
    _todayDeckIndex = preservedIndex >= 0
        ? preservedIndex
        : fallbackIndex % updated.length;
  }

  int _basicInsertionIndex(List<JapaneseWord> words, JapaneseWord word) {
    final targetOrder = _basicOrderById[word.id]!;
    var low = 0;
    var high = words.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_basicOrderById[words[middle].id]! < targetOrder) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _todayDeckInsertionIndex(List<JapaneseWord> deck, JapaneseWord word) {
    var low = 0;
    var high = deck.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_compareTodayDeckWords(deck[middle], word) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _compareTodayDeckWords(JapaneseWord left, JapaneseWord right) {
    final order = _stableDeckKey(
      left.id,
      _todayDeckSeed,
    ).compareTo(_stableDeckKey(right.id, _todayDeckSeed));
    return order != 0 ? order : left.id.compareTo(right.id);
  }
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

int _intersectionCount(Set<String> left, Set<String> right) {
  final scanLeft = left.length <= right.length;
  final candidates = scanLeft ? left : right;
  final lookup = scanLeft ? right : left;
  var count = 0;
  for (final id in candidates) {
    if (lookup.contains(id)) count += 1;
  }
  return count;
}

int mathMin(int left, int right) => left < right ? left : right;

int _stableDeckKey(String id, int seed) {
  var hash = 0x811c9dc5 ^ seed;
  for (final rune in id.runes) {
    hash ^= rune;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

Duration _reviewInterval({required bool correct, required int streak}) {
  if (!correct) return const Duration(minutes: 10);
  const daysByStreak = <int>[1, 3, 7, 14, 30, 60];
  final index = (streak - 1).clamp(0, daysByStreak.length - 1);
  return Duration(days: daysByStreak[index]);
}
