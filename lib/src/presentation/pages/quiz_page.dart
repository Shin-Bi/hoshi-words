import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import '../widgets/aozora_ruby_text.dart';
import '../widgets/common_widgets.dart';

enum _QuizPhase { setup, playing, result }

enum _QuizDirection { bidirectional, japaneseToKorean, koreanToJapanese }

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.controller,
    required this.onOpenWord,
    this.active = true,
  });

  final StudyController controller;
  final ValueChanged<JapaneseWord> onOpenWord;
  final bool active;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const _lowHeightBreakpoint = 410.0;
  static const _lowHeightQuestionHeight = 350.0;

  final math.Random _random = math.Random();

  _QuizPhase _phase = _QuizPhase.setup;
  _QuizDirection _direction = _QuizDirection.bidirectional;
  bool _useAccuracyFilter = false;
  int _accuracyThreshold = 70;
  int _requestedWordCount = 10;
  bool _previewFurigana = false;
  bool _bookmarkedOnly = false;
  bool _includeKnown = false;
  bool _knownOnly = false;
  bool _includeKnownBeforeKnownOnly = false;

  late Set<JlptLevel> _sessionLevels;
  late _QuizControllerSignal _controllerSignal;
  _QuizPoolSnapshot? _poolSnapshot;
  _QuizPoolSnapshot? _activePool;
  bool _controllerListenerAttached = false;
  List<_QuizQuestion> _questions = const [];
  List<JapaneseWord> _unlimitedWords = const [];
  final Map<String, _SessionWordScore> _sessionScores = {};
  int _unlimitedWordIndex = 0;
  bool _unlimitedSecondDirection = false;
  int _index = 0;
  int _score = 0;
  int _answeredCount = 0;
  bool _endedManually = false;
  String? _selectedOption;
  bool _gaveUp = false;

  bool get _unlimited => _requestedWordCount == 0;

  String get _wordCountLabel => _unlimited ? '무제한' : '$_requestedWordCount개';

  @override
  void initState() {
    super.initState();
    _sessionLevels = Set.of(widget.controller.selectedWordLevels);
    _controllerSignal = _QuizControllerSignal.capture(widget.controller);
    if (widget.active) _attachControllerListener();
  }

  @override
  void didUpdateWidget(covariant QuizPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_controllerListenerAttached) {
        oldWidget.controller.removeListener(_handleControllerChanged);
        _controllerListenerAttached = false;
      }
      final levels = widget.controller.selectedWordLevels;
      _sessionLevels = Set.of(levels);
      _controllerSignal = _QuizControllerSignal.capture(widget.controller);
      _poolSnapshot = null;
      _returnToSetup();
      if (widget.active) _attachControllerListener();
      return;
    }

    if (oldWidget.active && !widget.active) {
      _detachControllerListener();
      return;
    }
    if (!oldWidget.active && widget.active) {
      final latestLevels = widget.controller.selectedWordLevels;
      final levelsChanged = !setEquals(latestLevels, _sessionLevels);
      _sessionLevels = Set.of(latestLevels);
      _controllerSignal = _QuizControllerSignal.capture(widget.controller);
      _poolSnapshot = null;
      if (levelsChanged) _returnToSetup();
      _attachControllerListener();
    }
  }

  @override
  void dispose() {
    _detachControllerListener();
    super.dispose();
  }

  void _attachControllerListener() {
    if (_controllerListenerAttached) return;
    widget.controller.addListener(_handleControllerChanged);
    _controllerListenerAttached = true;
  }

  void _detachControllerListener() {
    if (!_controllerListenerAttached) return;
    widget.controller.removeListener(_handleControllerChanged);
    _controllerListenerAttached = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.shrink(key: ValueKey('quiz-inactive'));
    }
    return switch (_phase) {
      _QuizPhase.setup => _buildSetup(),
      _QuizPhase.playing => _buildPlaying(),
      _QuizPhase.result => _buildResult(),
    };
  }

  Widget _buildSetup() {
    final pool = _currentPoolSnapshot();
    final eligible = pool.eligibleWords;
    final selectedWords = _unlimited
        ? eligible.length
        : math.min(_requestedWordCount, eligible.length);
    final problemCount = _unlimited ? 0 : selectedWords * _questionsPerWord;
    final levelLabel = [
      for (final level in JlptLevel.values)
        if (_sessionLevels.contains(level)) level.label,
    ].join(' · ');

    return ListView(
      key: const ValueKey('quiz-settings-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Column(
          key: const ValueKey('quiz-setup'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: const Text(
                '테스트 설정',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$levelLabel 범위에서 원하는 조건으로 문제를 만들어요.',
              style: const TextStyle(color: AppColors.subtleText, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SettingsPanel(
          title: '출제 방향',
          subtitle: '양방향은 선택한 단어마다 두 방향을 모두 출제해요.',
          child: Row(
            children: [
              Expanded(
                child: _DirectionButton(
                  key: const ValueKey('quiz-direction-both'),
                  label: '양방향',
                  selected: _direction == _QuizDirection.bidirectional,
                  onTap: () => _setDirection(_QuizDirection.bidirectional),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _DirectionButton(
                  key: const ValueKey('quiz-direction-ja-ko'),
                  label: '일 → 한',
                  selected: _direction == _QuizDirection.japaneseToKorean,
                  onTap: () => _setDirection(_QuizDirection.japaneseToKorean),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _DirectionButton(
                  key: const ValueKey('quiz-direction-ko-ja'),
                  label: '한 → 일',
                  selected: _direction == _QuizDirection.koreanToJapanese,
                  onTap: () => _setDirection(_QuizDirection.koreanToJapanese),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SettingsPanel(
          title: '테스트 단어 수',
          subtitle: '0~50개 사이에서 5개 단위로 설정해요. 0개는 무제한이에요.',
          child: Row(
            children: [
              const Text(
                '개수',
                style: TextStyle(
                  color: AppColors.body,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('quiz-word-count'),
                  min: 0,
                  max: 50,
                  divisions: 10,
                  value: _requestedWordCount.toDouble(),
                  label: _wordCountLabel,
                  onChanged: (value) => setState(() {
                    _requestedWordCount = (value / 5).round() * 5;
                  }),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  _wordCountLabel,
                  key: const ValueKey('quiz-word-count-value'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SettingsPanel(
          title: '정답률 조건',
          subtitle: '미응시 단어는 정답률 0%로 계산해요.',
          child: Column(
            children: [
              _SettingSwitch(
                key: const ValueKey('quiz-accuracy-filter'),
                label: '정답률이 기준 미만인 단어만',
                value: _useAccuracyFilter,
                onChanged: (value) => setState(() {
                  _useAccuracyFilter = value;
                  _poolSnapshot = null;
                }),
              ),
              if (_useAccuracyFilter) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '기준',
                      style: TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('quiz-accuracy-threshold'),
                        min: 10,
                        max: 100,
                        divisions: 9,
                        value: _accuracyThreshold.toDouble(),
                        label: '$_accuracyThreshold%',
                        onChanged: (value) => setState(() {
                          _accuracyThreshold = value.round();
                          _poolSnapshot = null;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '$_accuracyThreshold%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SettingsPanel(
          title: '표시 및 단어 필터',
          child: Column(
            children: [
              _SettingSwitch(
                key: const ValueKey('quiz-furigana-preview'),
                label: '후리가나 미리보기',
                description: '끄면 정답을 고른 뒤에 표시해요.',
                value: _previewFurigana,
                onChanged: (value) => setState(() {
                  _previewFurigana = value;
                }),
              ),
              const Divider(height: 17),
              _SettingSwitch(
                key: const ValueKey('quiz-bookmarked-only'),
                label: '북마크한 단어만',
                value: _bookmarkedOnly,
                onChanged: (value) => setState(() {
                  _bookmarkedOnly = value;
                  _poolSnapshot = null;
                }),
              ),
              const Divider(height: 17),
              _SettingSwitch(
                key: const ValueKey('quiz-include-known'),
                label: '외운 단어 포함',
                description: _knownOnly
                    ? '외운 단어만 보기 중에는 자동으로 켜져요.'
                    : '기본적으로 외운 단어는 제외해요.',
                value: _includeKnown,
                onChanged: _knownOnly
                    ? null
                    : (value) => setState(() {
                        _includeKnown = value;
                        _poolSnapshot = null;
                      }),
              ),
              const Divider(height: 17),
              _SettingSwitch(
                key: const ValueKey('quiz-known-only'),
                label: '외운 단어만',
                description: '‘외웠어요’로 표시한 단어만 출제해요.',
                value: _knownOnly,
                onChanged: (value) => setState(() {
                  if (value) {
                    _includeKnownBeforeKnownOnly = _includeKnown;
                    _knownOnly = true;
                    _includeKnown = true;
                  } else {
                    _knownOnly = false;
                    _includeKnown = _includeKnownBeforeKnownOnly;
                  }
                  _poolSnapshot = null;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AvailabilityCard(
          eligibleWords: eligible.length,
          selectedWords: selectedWords,
          problemCount: problemCount,
          unlimited: _unlimited,
          message: _availabilityMessage(pool: pool),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('quiz-start'),
          onPressed: eligible.isEmpty ? null : _startQuiz,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            _unlimited
                ? '무제한 시험 시작'
                : problemCount == 0
                ? '테스트를 만들 수 없어요'
                : '$problemCount문제 시작',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaying() {
    if (_questions.isEmpty || _index >= _questions.length) {
      return const SizedBox.shrink();
    }
    final question = _questions[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < _lowHeightBreakpoint) {
          return SingleChildScrollView(
            key: const ValueKey('quiz-low-height-scroll'),
            child: Column(
              children: [
                _buildProgress(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: SizedBox(
                    height: _lowHeightQuestionHeight,
                    child: _buildAnimatedQuestion(question),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          key: const PageStorageKey('quiz-page'),
          children: [
            _buildProgress(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: _buildAnimatedQuestion(question),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgress() {
    final directionLabel = switch (_direction) {
      _QuizDirection.bidirectional => '일 ↔ 한',
      _QuizDirection.japaneseToKorean => '일 → 한',
      _QuizDirection.koreanToJapanese => '한 → 일',
    };
    return Container(
      key: const ValueKey('quiz-progress'),
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(6, 5, 14, 7),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('quiz-stop'),
                onPressed: _finishQuiz,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onDarkMuted,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 17),
                label: const Text(
                  '시험 종료',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _unlimited
                      ? '$directionLabel · ${_answeredCount + 1}번째 · 무제한'
                      : '$directionLabel · ${_index + 1} / ${_questions.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$_score점',
                style: const TextStyle(
                  color: AppColors.moon,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_unlimited)
            Container(
              key: const ValueKey('quiz-unlimited-progress'),
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.moon.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(99),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: (_index + 1) / _questions.length,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.moon),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedQuestion(_QuizQuestion question) {
    return AnimatedSwitcher(
      duration: AppDurations.emphasized,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _QuestionCard(
        key: ValueKey(
          'quiz-card-${question.word.id}-${question.direction.name}-$_answeredCount',
        ),
        question: question,
        selectedOption: _selectedOption,
        isLast: !_unlimited && _index == _questions.length - 1,
        previewFurigana: _previewFurigana,
        bookmarked: widget.controller.isBookmarked(question.word.id),
        onBookmark: () => widget.controller.toggleBookmark(question.word.id),
        onSelect: _answer,
        gaveUp: _gaveUp,
        onGiveUp: _giveUp,
        onNext: _next,
        onOpenWord: widget.onOpenWord,
      ),
    );
  }

  Widget _buildResult() {
    final percent = _answeredCount == 0
        ? 0
        : (_score * 100 / _answeredCount).round();
    final words = <JapaneseWord>[];
    for (final wordId in _sessionScores.keys) {
      final word = widget.controller.wordById(wordId);
      if (word != null) words.add(word);
    }
    final canRetry = _currentPoolSnapshot().eligibleWords.isNotEmpty;

    return Column(
      key: const ValueKey('quiz-result'),
      children: [
        Container(
          width: double.infinity,
          color: AppColors.ink,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
          child: Row(
            children: [
              const StarMark(size: 48, glow: false),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _endedManually ? '시험 종료' : '테스트 완료',
                      style: const TextStyle(
                        color: AppColors.onDarkMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$_score / $_answeredCount · $percent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('quiz-result-list'),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('quiz-result-settings'),
                      onPressed: () => setState(_returnToSetup),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('설정 바꾸기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('quiz-retry'),
                      onPressed: canRetry ? _startQuiz : null,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(canRetry ? '다시 시험' : '재시험 불가'),
                    ),
                  ),
                ],
              ),
              if (!canRetry) ...[
                const SizedBox(height: 8),
                const Text(
                  '현재 조건에 맞는 단어가 남지 않았어요. 설정을 바꿔 주세요.',
                  key: ValueKey('quiz-retry-unavailable'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 10,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '단어별 정답 기록',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '이번 테스트와 지금까지의 누적 기록을 함께 표시해요.',
                style: TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              for (final word in words)
                _WordResultTile(
                  key: ValueKey('quiz-result-word-${word.id}'),
                  word: word,
                  session: _sessionScores[word.id] ?? const _SessionWordScore(),
                  cumulativeAttempts: widget.controller.quizAttemptsFor(
                    word.id,
                  ),
                  cumulativeCorrect: widget.controller.quizCorrectFor(word.id),
                  onTap: () => widget.onOpenWord(word),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleControllerChanged() {
    if (!mounted || !widget.active) return;
    final nextSignal = _QuizControllerSignal.capture(widget.controller);
    final levelsChanged = !setEquals(nextSignal.levels, _sessionLevels);
    final bookmarkChanged =
        nextSignal.bookmarkCount != _controllerSignal.bookmarkCount;
    final knownChanged =
        nextSignal.studyWordCount != _controllerSignal.studyWordCount;
    final quizStatsChanged =
        nextSignal.totalQuizAnswers != _controllerSignal.totalQuizAnswers;
    _controllerSignal = nextSignal;

    if (levelsChanged) {
      setState(() {
        _sessionLevels = Set.of(nextSignal.levels);
        _poolSnapshot = null;
        _returnToSetup();
      });
      return;
    }

    final poolChanged =
        (bookmarkChanged && _bookmarkedOnly) ||
        (knownChanged && (_knownOnly || !_includeKnown)) ||
        (quizStatsChanged && _useAccuracyFilter);
    if (poolChanged) _poolSnapshot = null;

    // The shell keeps every tab mounted in an IndexedStack. Today-card index
    // and display-option notifications are unrelated to quizzes, so rebuilding
    // here would make every swipe pay the full candidate-filtering cost.
    final shouldRebuild =
        ((_phase == _QuizPhase.setup || _phase == _QuizPhase.result) &&
            poolChanged) ||
        (_phase == _QuizPhase.playing && bookmarkChanged);
    if (shouldRebuild) {
      setState(() {});
    }
  }

  void _setDirection(_QuizDirection direction) {
    if (_direction == direction) return;
    setState(() {
      _direction = direction;
      _poolSnapshot = null;
    });
  }

  int get _questionsPerWord =>
      _direction == _QuizDirection.bidirectional ? 2 : 1;

  _QuizPoolSnapshot _currentPoolSnapshot() {
    return _poolSnapshot ??= _buildPoolSnapshot();
  }

  _QuizPoolSnapshot _buildPoolSnapshot() {
    final selectedWords = widget.controller.selectedWordListWords;
    final targetWords = <JapaneseWord>[];
    final meaningChoicesByPartOfSpeech =
        <WordPartOfSpeech, Map<String, _QuizChoice>>{};
    final lemmaChoicesByPartOfSpeech =
        <WordPartOfSpeech, Map<String, _QuizChoice>>{};
    var bookmarkedInSelection = 0;
    var knownInSelection = 0;

    // Build all filters and both answer indexes in one pass. Target-only
    // filters (bookmark and accuracy) deliberately do not restrict distractors.
    for (final word in selectedWords) {
      final known = widget.controller.isKnown(word.id);
      final bookmarked = widget.controller.isBookmarked(word.id);
      if (known) knownInSelection += 1;
      if (bookmarked) bookmarkedInSelection += 1;
      if (_knownOnly ? !known : (known && !_includeKnown)) continue;

      meaningChoicesByPartOfSpeech
          .putIfAbsent(word.partOfSpeech, () => <String, _QuizChoice>{})
          .putIfAbsent(
            word.meanings.first,
            () => _QuizChoice(value: word.meanings.first, word: word),
          );
      lemmaChoicesByPartOfSpeech
          .putIfAbsent(word.partOfSpeech, () => <String, _QuizChoice>{})
          .putIfAbsent(
            word.lemma,
            () => _QuizChoice(
              value: word.lemma,
              word: word,
              reading: word.reading,
            ),
          );

      if (_bookmarkedOnly && !bookmarked) continue;
      if (_useAccuracyFilter &&
          widget.controller.quizAccuracyFor(word.id) * 100 >=
              _accuracyThreshold) {
        continue;
      }
      targetWords.add(word);
    }

    final eligibleWords = <JapaneseWord>[];
    for (final word in targetWords) {
      final meaningChoices =
          meaningChoicesByPartOfSpeech[word.partOfSpeech] ??
          const <String, _QuizChoice>{};
      final lemmaChoices =
          lemmaChoicesByPartOfSpeech[word.partOfSpeech] ??
          const <String, _QuizChoice>{};
      final hasJapaneseToKoreanChoices = _hasThreeOtherValues(
        meaningChoices,
        word.meanings.first,
      );
      final hasKoreanToJapaneseChoices = _hasThreeOtherValues(
        lemmaChoices,
        word.lemma,
      );
      final eligible = switch (_direction) {
        _QuizDirection.bidirectional =>
          hasJapaneseToKoreanChoices && hasKoreanToJapaneseChoices,
        _QuizDirection.japaneseToKorean => hasJapaneseToKoreanChoices,
        _QuizDirection.koreanToJapanese => hasKoreanToJapaneseChoices,
      };
      if (eligible) eligibleWords.add(word);
    }

    return _QuizPoolSnapshot(
      selectedWordCount: selectedWords.length,
      bookmarkedInSelection: bookmarkedInSelection,
      knownInSelection: knownInSelection,
      targetWords: List.unmodifiable(targetWords),
      eligibleWords: List.unmodifiable(eligibleWords),
      meaningChoicesByPartOfSpeech:
          Map<WordPartOfSpeech, List<_QuizChoice>>.unmodifiable({
            for (final entry in meaningChoicesByPartOfSpeech.entries)
              entry.key: List<_QuizChoice>.unmodifiable(entry.value.values),
          }),
      lemmaChoicesByPartOfSpeech:
          Map<WordPartOfSpeech, List<_QuizChoice>>.unmodifiable({
            for (final entry in lemmaChoicesByPartOfSpeech.entries)
              entry.key: List<_QuizChoice>.unmodifiable(entry.value.values),
          }),
    );
  }

  bool _hasThreeOtherValues(Map<String, _QuizChoice> values, String answer) {
    return values.length - (values.containsKey(answer) ? 1 : 0) >= 3;
  }

  String _availabilityMessage({required _QuizPoolSnapshot pool}) {
    final eligible = pool.eligibleWords;
    if (eligible.isNotEmpty) {
      if (_unlimited) {
        return '시험 종료를 누를 때까지 후보 단어에서 계속 출제해요.';
      }
      if (eligible.length < _requestedWordCount) {
        return '요청한 $_requestedWordCount개보다 후보가 적어 ${eligible.length}개만 출제해요.';
      }
      return '모든 조건을 반영한 뒤 무작위로 출제해요.';
    }
    if (_bookmarkedOnly && pool.bookmarkedInSelection == 0) {
      return '선택한 데모 범위에 북마크한 단어가 없어요.';
    }
    if (_knownOnly && pool.knownInSelection == 0) {
      return '선택한 데모 범위에 외운 단어가 없어요.';
    }
    if (!_includeKnown &&
        pool.selectedWordCount > 0 &&
        pool.knownInSelection == pool.selectedWordCount) {
      return '모든 단어가 ‘외웠어요’ 상태예요. 포함 옵션을 켜 보세요.';
    }
    if (_useAccuracyFilter && pool.targetWords.isEmpty) {
      return '정답률 $_accuracyThreshold% 미만에 해당하는 단어가 없어요.';
    }
    if (pool.targetWords.isNotEmpty) {
      return '같은 품사에서 서로 다른 선택지 3개를 만들 단어가 부족해요.';
    }
    return '현재 조건에 맞는 단어가 없어요. 필터를 조정해 보세요.';
  }

  void _startQuiz() {
    final pool = _currentPoolSnapshot();
    final eligible = [...pool.eligibleWords]..shuffle(_random);
    if (eligible.isEmpty) return;
    if (_unlimited) {
      _unlimitedWords = eligible;
      _unlimitedWordIndex = 0;
      _unlimitedSecondDirection = false;
      final firstQuestion = _takeUnlimitedQuestion(pool);
      setState(() {
        _activePool = pool;
        _questions = [firstQuestion];
        _index = 0;
        _score = 0;
        _answeredCount = 0;
        _endedManually = false;
        _selectedOption = null;
        _gaveUp = false;
        _sessionScores.clear();
        _phase = _QuizPhase.playing;
      });
      return;
    }
    final wordCount = math.min(_requestedWordCount, eligible.length);
    if (wordCount == 0) return;
    final selectedWords = eligible.take(wordCount).toList();
    final questions = <_QuizQuestion>[];
    for (final word in selectedWords) {
      if (_direction != _QuizDirection.koreanToJapanese) {
        questions.add(
          _buildWordQuestion(
            word,
            pool.meaningChoicesByPartOfSpeech[word.partOfSpeech] ??
                const <_QuizChoice>[],
            japaneseToKorean: true,
          ),
        );
      }
      if (_direction != _QuizDirection.japaneseToKorean) {
        questions.add(
          _buildWordQuestion(
            word,
            pool.lemmaChoicesByPartOfSpeech[word.partOfSpeech] ??
                const <_QuizChoice>[],
            japaneseToKorean: false,
          ),
        );
      }
    }
    questions.shuffle(_random);
    setState(() {
      _activePool = pool;
      _questions = questions;
      _index = 0;
      _score = 0;
      _answeredCount = 0;
      _endedManually = false;
      _selectedOption = null;
      _gaveUp = false;
      _sessionScores.clear();
      _phase = _QuizPhase.playing;
    });
  }

  _QuizQuestion _takeUnlimitedQuestion(_QuizPoolSnapshot pool) {
    if (_unlimitedWords.isEmpty ||
        _unlimitedWordIndex >= _unlimitedWords.length) {
      _unlimitedWords = [...pool.eligibleWords]..shuffle(_random);
      _unlimitedWordIndex = 0;
      _unlimitedSecondDirection = false;
    }
    final word = _unlimitedWords[_unlimitedWordIndex];
    final japaneseToKorean = switch (_direction) {
      _QuizDirection.japaneseToKorean => true,
      _QuizDirection.koreanToJapanese => false,
      _QuizDirection.bidirectional => !_unlimitedSecondDirection,
    };
    if (_direction == _QuizDirection.bidirectional &&
        !_unlimitedSecondDirection) {
      _unlimitedSecondDirection = true;
    } else {
      _unlimitedSecondDirection = false;
      _unlimitedWordIndex += 1;
    }
    return _buildWordQuestion(
      word,
      japaneseToKorean
          ? pool.meaningChoicesByPartOfSpeech[word.partOfSpeech] ??
                const <_QuizChoice>[]
          : pool.lemmaChoicesByPartOfSpeech[word.partOfSpeech] ??
                const <_QuizChoice>[],
      japaneseToKorean: japaneseToKorean,
    );
  }

  _QuizQuestion _buildWordQuestion(
    JapaneseWord word,
    List<_QuizChoice> pool, {
    required bool japaneseToKorean,
  }) {
    final answer = japaneseToKorean ? word.meanings.first : word.lemma;
    final distractors = <_QuizChoice>[];
    // Floyd's sampling selects four unique indices in bounded O(1) work. Four
    // guarantees three distractors whether or not the answer is sampled.
    final sampleCount = math.min(4, pool.length);
    final sampledIndexes = <int>{};
    for (var upper = pool.length - sampleCount; upper < pool.length; upper++) {
      final candidate = _random.nextInt(upper + 1);
      if (!sampledIndexes.add(candidate)) sampledIndexes.add(upper);
    }
    for (final index in sampledIndexes) {
      final candidate = pool[index];
      if (candidate.value != answer) distractors.add(candidate);
      if (distractors.length == 3) break;
    }
    final options = [
      _QuizChoice(
        value: answer,
        word: word,
        reading: japaneseToKorean ? '' : word.reading,
      ),
      ...distractors,
    ]..shuffle(_random);
    return _QuizQuestion(
      word: word,
      direction: japaneseToKorean
          ? _QuestionDirection.japaneseToKorean
          : _QuestionDirection.koreanToJapanese,
      prompt: japaneseToKorean ? word.lemma : word.meanings.first,
      promptReading: japaneseToKorean ? word.reading : '',
      instruction: japaneseToKorean ? '이 일본어의 뜻을 고르세요.' : '이 뜻에 맞는 일본어를 고르세요.',
      answer: answer,
      answerReading: japaneseToKorean ? word.reading : word.reading,
      options: options,
    );
  }

  void _answer(String option) {
    if (_selectedOption != null || _gaveUp) return;
    final question = _questions[_index];
    final correct = option == question.answer;
    setState(() {
      _selectedOption = option;
      if (correct) _score += 1;
      _answeredCount += 1;
      final previous =
          _sessionScores[question.word.id] ?? const _SessionWordScore();
      _sessionScores[question.word.id] = previous.record(correct);
    });
    widget.controller.recordQuizAnswer(question.word.id, correct: correct);
  }

  void _giveUp() {
    if (_selectedOption != null || _gaveUp) return;
    final question = _questions[_index];
    setState(() {
      _gaveUp = true;
      _answeredCount += 1;
      final previous =
          _sessionScores[question.word.id] ?? const _SessionWordScore();
      _sessionScores[question.word.id] = previous.record(false);
    });
    widget.controller.recordQuizAnswer(question.word.id, correct: false);
  }

  void _next() {
    setState(() {
      if (_unlimited) {
        _questions = [_takeUnlimitedQuestion(_activePool!)];
        _index = 0;
        _selectedOption = null;
        _gaveUp = false;
      } else if (_index == _questions.length - 1) {
        _endedManually = false;
        _phase = _QuizPhase.result;
      } else {
        _index += 1;
        _selectedOption = null;
        _gaveUp = false;
      }
    });
  }

  void _finishQuiz() {
    setState(() {
      _endedManually = true;
      _phase = _QuizPhase.result;
    });
  }

  void _returnToSetup() {
    _phase = _QuizPhase.setup;
    _activePool = null;
    _questions = const [];
    _unlimitedWords = const [];
    _sessionScores.clear();
    _unlimitedWordIndex = 0;
    _unlimitedSecondDirection = false;
    _index = 0;
    _score = 0;
    _answeredCount = 0;
    _endedManually = false;
    _selectedOption = null;
    _gaveUp = false;
  }
}

class _QuizControllerSignal {
  const _QuizControllerSignal({
    required this.levels,
    required this.bookmarkCount,
    required this.studyWordCount,
    required this.totalQuizAnswers,
  });

  factory _QuizControllerSignal.capture(StudyController controller) {
    return _QuizControllerSignal(
      levels: Set.of(controller.selectedWordLevels),
      bookmarkCount: controller.bookmarkCount,
      // This cached view represents the same selected-level words after known
      // words have been removed without forcing the shuffled Today deck to be
      // materialized merely to detect a quiz-relevant change.
      studyWordCount: controller.selectedStudyWords.length,
      totalQuizAnswers: controller.totalQuizAnswers,
    );
  }

  final Set<JlptLevel> levels;
  final int bookmarkCount;
  final int studyWordCount;
  final int totalQuizAnswers;
}

class _QuizPoolSnapshot {
  const _QuizPoolSnapshot({
    required this.selectedWordCount,
    required this.bookmarkedInSelection,
    required this.knownInSelection,
    required this.targetWords,
    required this.eligibleWords,
    required this.meaningChoicesByPartOfSpeech,
    required this.lemmaChoicesByPartOfSpeech,
  });

  final int selectedWordCount;
  final int bookmarkedInSelection;
  final int knownInSelection;
  final List<JapaneseWord> targetWords;
  final List<JapaneseWord> eligibleWords;
  final Map<WordPartOfSpeech, List<_QuizChoice>> meaningChoicesByPartOfSpeech;
  final Map<WordPartOfSpeech, List<_QuizChoice>> lemmaChoicesByPartOfSpeech;
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.subtleText,
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.toggleSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(
          color: selected ? AppColors.ink : AppColors.cardOutline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? AppColors.ink : AppColors.subtleText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description != null)
                Text(
                  description!,
                  style: const TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 9,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.eligibleWords,
    required this.selectedWords,
    required this.problemCount,
    required this.unlimited,
    required this.message,
  });

  final int eligibleWords;
  final int selectedWords;
  final int problemCount;
  final bool unlimited;
  final String message;

  @override
  Widget build(BuildContext context) {
    final available = eligibleWords > 0;
    return Container(
      key: const ValueKey('quiz-availability'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: available
            ? AppColors.successContainer
            : AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            available ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 20,
            color: available ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available
                      ? unlimited
                            ? '출제 가능 $eligibleWords개 · 무제한 모드'
                            : '출제 가능 $eligibleWords개 · 선택 $selectedWords개 · $problemCount문제'
                      : '출제 가능한 단어가 없어요',
                  style: TextStyle(
                    color: available
                        ? AppColors.successText
                        : AppColors.errorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: available
                        ? AppColors.successText
                        : AppColors.errorText,
                    fontSize: 10,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _QuestionDirection { japaneseToKorean, koreanToJapanese }

class _QuizChoice {
  const _QuizChoice({
    required this.value,
    required this.word,
    this.reading = '',
  });

  final String value;
  final JapaneseWord word;
  final String reading;
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.word,
    required this.direction,
    required this.prompt,
    required this.promptReading,
    required this.instruction,
    required this.answer,
    required this.answerReading,
    required this.options,
  });

  final JapaneseWord word;
  final _QuestionDirection direction;
  final String prompt;
  final String promptReading;
  final String instruction;
  final String answer;
  final String answerReading;
  final List<_QuizChoice> options;
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.selectedOption,
    required this.isLast,
    required this.previewFurigana,
    required this.bookmarked,
    required this.onBookmark,
    required this.onSelect,
    required this.gaveUp,
    required this.onGiveUp,
    required this.onNext,
    required this.onOpenWord,
  });

  final _QuizQuestion question;
  final String? selectedOption;
  final bool isLast;
  final bool previewFurigana;
  final bool bookmarked;
  final VoidCallback onBookmark;
  final ValueChanged<String> onSelect;
  final bool gaveUp;
  final VoidCallback onGiveUp;
  final VoidCallback onNext;
  final ValueChanged<JapaneseWord> onOpenWord;

  @override
  Widget build(BuildContext context) {
    final answered = selectedOption != null || gaveUp;
    final showFurigana = previewFurigana || answered;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    question.instruction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: bookmarked ? '북마크 해제' : '북마크',
                  onPressed: onBookmark,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  iconSize: 20,
                  icon: Icon(
                    bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: bookmarked
                        ? AppColors.bookmark
                        : AppColors.mutedBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 70,
            child: Container(
              key: ValueKey('quiz-question-${question.word.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warmSurface,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: question.promptReading.isEmpty
                  ? _AutoFitText(
                      question.prompt,
                      key: ValueKey('quiz-prompt-${question.word.id}'),
                      textAlign: TextAlign.center,
                      maxFontSize: 21,
                      minFontSize: 8,
                      style: const TextStyle(
                        color: AppColors.ink,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : _AutoFitRubyText(
                      key: ValueKey('quiz-prompt-${question.word.id}'),
                      surface: question.prompt,
                      reading: question.promptReading,
                      showRuby: showFurigana,
                      readingKey: showFurigana
                          ? ValueKey('quiz-prompt-reading-${question.word.id}')
                          : null,
                      textAlign: TextAlign.center,
                      baseStyle: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 21,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                      rubyStyle: const TextStyle(
                        color: AppColors.reading,
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _QuizOptionGrid(
              question: question,
              selectedOption: selectedOption,
              answered: answered,
              showFurigana: showFurigana,
              onSelect: onSelect,
              onOpenWord: onOpenWord,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: AnimatedSwitcher(
              duration: AppDurations.fast,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: answered
                  ? _AnsweredQuestionFooter(
                      key: ValueKey(
                        'quiz-answer-${question.word.id}-$selectedOption',
                      ),
                      question: question,
                      selectedOption: selectedOption,
                      isLast: isLast,
                      onOpenWord: () => onOpenWord(question.word),
                      onNext: onNext,
                    )
                  : _UnansweredQuestionFooter(
                      key: const ValueKey('quiz-answer-hint'),
                      onGiveUp: onGiveUp,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizOptionGrid extends StatelessWidget {
  const _QuizOptionGrid({
    required this.question,
    required this.selectedOption,
    required this.answered,
    required this.showFurigana,
    required this.onSelect,
    required this.onOpenWord,
  });

  final _QuizQuestion question;
  final String? selectedOption;
  final bool answered;
  final bool showFurigana;
  final ValueChanged<String> onSelect;
  final ValueChanged<JapaneseWord> onOpenWord;

  @override
  Widget build(BuildContext context) {
    Widget optionAt(int index) {
      final option = question.options[index];
      return Expanded(
        child: _QuizOption(
          option: option,
          answer: question.answer,
          selectedOption: selectedOption,
          answered: answered,
          showFurigana: showFurigana,
          onTap: answered
              ? () => onOpenWord(option.word)
              : () => onSelect(option.value),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [optionAt(0), const SizedBox(width: 7), optionAt(1)],
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [optionAt(2), const SizedBox(width: 7), optionAt(3)],
          ),
        ),
      ],
    );
  }
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.option,
    required this.answer,
    required this.selectedOption,
    required this.answered,
    required this.showFurigana,
    required this.onTap,
  });

  final _QuizChoice option;
  final String answer;
  final String? selectedOption;
  final bool answered;
  final bool showFurigana;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAnswer = option.value == answer;
    final isSelected = selectedOption == option.value;
    final color = !answered
        ? AppColors.softSurface
        : isAnswer
        ? AppColors.successContainer
        : isSelected
        ? AppColors.errorContainer
        : AppColors.softSurface;
    final borderColor = !answered
        ? AppColors.cardOutline
        : isAnswer
        ? AppColors.success
        : isSelected
        ? AppColors.error
        : AppColors.cardOutline;

    return Material(
      key: ValueKey('quiz-option-${option.value}'),
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.option),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: option.reading.isEmpty
                    ? _AutoFitText(
                        option.value,
                        key: ValueKey('quiz-choice-text-${option.value}'),
                        textAlign: TextAlign.center,
                        maxFontSize: 15,
                        minFontSize: 7,
                        style: TextStyle(
                          color: isSelected && !isAnswer
                              ? AppColors.errorText
                              : isAnswer && answered
                              ? AppColors.successText
                              : AppColors.ink,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : _AutoFitRubyText(
                        key: ValueKey('quiz-choice-text-${option.value}'),
                        surface: option.value,
                        reading: option.reading,
                        showRuby: showFurigana,
                        readingKey: showFurigana
                            ? ValueKey('quiz-option-reading-${option.value}')
                            : null,
                        textAlign: TextAlign.center,
                        baseStyle: TextStyle(
                          color: isSelected && !isAnswer
                              ? AppColors.errorText
                              : isAnswer && answered
                              ? AppColors.successText
                              : AppColors.ink,
                          fontSize: 15,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                        rubyStyle: const TextStyle(
                          color: AppColors.reading,
                          fontSize: 8,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnansweredQuestionFooter extends StatelessWidget {
  const _UnansweredQuestionFooter({super.key, required this.onGiveUp});

  final VoidCallback onGiveUp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        key: const ValueKey('quiz-dont-know'),
        onPressed: onGiveUp,
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('모르겠어요'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(132, 44),
          foregroundColor: AppColors.mutedBlue,
          side: const BorderSide(color: AppColors.cardOutline),
        ),
      ),
    );
  }
}

class _AnsweredQuestionFooter extends StatelessWidget {
  const _AnsweredQuestionFooter({
    super.key,
    required this.question,
    required this.selectedOption,
    required this.isLast,
    required this.onOpenWord,
    required this.onNext,
  });

  final _QuizQuestion question;
  final String? selectedOption;
  final bool isLast;
  final VoidCallback onOpenWord;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final correct = selectedOption == question.answer;
    return Row(
      key: const ValueKey('quiz-answer-feedback'),
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpenWord,
            borderRadius: BorderRadius.circular(AppRadii.inner),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    correct ? '정답이에요' : '정답: ${question.answer}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: correct
                          ? AppColors.successText
                          : AppColors.errorText,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (question.answerReading.isNotEmpty)
                    SizedBox(
                      key: ValueKey('quiz-answer-reading-${question.word.id}'),
                      height: 16,
                      child: _AutoFitRubyText(
                        surface: question.word.lemma,
                        reading: question.answerReading,
                        showRuby: true,
                        textAlign: TextAlign.start,
                        baseStyle: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                        rubyStyle: const TextStyle(
                          color: AppColors.reading,
                          fontSize: 6,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        FilledButton(
          key: const ValueKey('next-quiz-question'),
          onPressed: onNext,
          style: FilledButton.styleFrom(
            minimumSize: const Size(92, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(isLast ? '결과 보기' : '다음 문제'),
        ),
      ],
    );
  }
}

class _AutoFitText extends StatelessWidget {
  const _AutoFitText(
    this.text, {
    super.key,
    required this.style,
    required this.maxFontSize,
    required this.minFontSize,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final double maxFontSize;
  final double minFontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return Text(text, textAlign: textAlign, style: effectiveStyle);
        }
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        bool fits(double fontSize) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: effectiveStyle.copyWith(fontSize: fontSize),
            ),
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          final result =
              painter.height <= constraints.maxHeight + 0.1 &&
              painter.width <= constraints.maxWidth + 0.1;
          painter.dispose();
          return result;
        }

        var low = math.min(minFontSize, maxFontSize);
        var high = math.max(minFontSize, maxFontSize);
        final minimumFits = fits(low);
        if (minimumFits) {
          // Eight steps are sub-pixel precise for the ranges used here while
          // avoiding needless native paragraph layouts on every quiz rebuild.
          for (var iteration = 0; iteration < 8; iteration++) {
            final midpoint = (low + high) / 2;
            if (fits(midpoint)) {
              low = midpoint;
            } else {
              high = midpoint;
            }
          }
        }
        final fittedText = Text(
          text,
          textAlign: textAlign,
          softWrap: true,
          style: effectiveStyle.copyWith(fontSize: low),
        );
        if (minimumFits) return Center(child: fittedText);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: switch (textAlign) {
            TextAlign.center => Alignment.center,
            TextAlign.end || TextAlign.right => Alignment.centerRight,
            _ => Alignment.centerLeft,
          },
          child: SizedBox(width: constraints.maxWidth, child: fittedText),
        );
      },
    );
  }
}

class _AutoFitRubyText extends StatelessWidget {
  const _AutoFitRubyText({
    super.key,
    required this.surface,
    required this.reading,
    required this.showRuby,
    required this.baseStyle,
    required this.rubyStyle,
    this.readingKey,
    this.textAlign = TextAlign.start,
  });

  final String surface;
  final String reading;
  final bool showRuby;
  final TextStyle baseStyle;
  final TextStyle rubyStyle;
  final Key? readingKey;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ruby = AozoraRubyText(
          buildAozoraRubySource(surface, reading),
          key: readingKey,
          showRuby: showRuby,
          textAlign: textAlign,
          baseStyle: baseStyle,
          rubyStyle: rubyStyle,
        );
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return ruby;
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: switch (textAlign) {
            TextAlign.center => Alignment.center,
            TextAlign.end || TextAlign.right => Alignment.centerRight,
            _ => Alignment.centerLeft,
          },
          child: SizedBox(width: constraints.maxWidth, child: ruby),
        );
      },
    );
  }
}

class _SessionWordScore {
  const _SessionWordScore({this.attempts = 0, this.correct = 0});

  final int attempts;
  final int correct;

  _SessionWordScore record(bool isCorrect) => _SessionWordScore(
    attempts: attempts + 1,
    correct: correct + (isCorrect ? 1 : 0),
  );
}

class _WordResultTile extends StatelessWidget {
  const _WordResultTile({
    super.key,
    required this.word,
    required this.session,
    required this.cumulativeAttempts,
    required this.cumulativeCorrect,
    required this.onTap,
  });

  final JapaneseWord word;
  final _SessionWordScore session;
  final int cumulativeAttempts;
  final int cumulativeCorrect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sessionRecord = formatQuizAccuracyRecord(
      attempts: session.attempts,
      correct: session.correct,
    );
    final cumulativeRecord = formatQuizAccuracyRecord(
      attempts: cumulativeAttempts,
      correct: cumulativeCorrect,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: const BorderSide(color: AppColors.cardOutline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AozoraRubyText(
                      buildAozoraRubySourceForReadings(
                        word.lemma,
                        word.readings,
                      ),
                      baseStyle: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                      rubyStyle: const TextStyle(
                        color: AppColors.reading,
                        fontSize: 8,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '이번 $sessionRecord\n누적 $cumulativeRecord',
                key: ValueKey('quiz-result-stats-${word.id}'),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: AppColors.body,
                  fontSize: 10,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.subtleText,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
