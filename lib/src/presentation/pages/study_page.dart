import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../data/jlpt_grammar_catalog.dart';
import '../../domain/grammar.dart';
import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import '../widgets/aozora_ruby_text.dart';
import '../widgets/common_widgets.dart';
import '../widgets/conversation_nuance_deck.dart';
import '../widgets/japanese_tts_button.dart';
import '../widgets/linked_aozora_ruby_text.dart';

enum _StudySection { weakReview, grammar, nuance }

class StudyPage extends StatefulWidget {
  const StudyPage({
    super.key,
    required this.controller,
    required this.linkIndex,
    required this.onOpenWord,
    this.active = true,
  });

  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;
  final bool active;

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  _StudySection _section = _StudySection.weakReview;
  List<WeakReviewItem>? _reviewSession;
  List<GrammarPoint>? _grammarSession;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _updateListener();
  }

  @override
  void didUpdateWidget(covariant StudyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller && _listening) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
    _updateListener();
  }

  @override
  void dispose() {
    if (_listening) widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _updateListener() {
    if (widget.active && !_listening) {
      widget.controller.addListener(_handleControllerChanged);
      _listening = true;
    } else if (!widget.active && _listening) {
      widget.controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.shrink(key: ValueKey('study-inactive'));
    }
    final reviewSession = _reviewSession;
    if (reviewSession != null) {
      return _WeakReviewSession(
        items: reviewSession,
        pool: widget.controller.selectedWordListWords,
        controller: widget.controller,
        onOpenWord: widget.onOpenWord,
        onClose: () => setState(() => _reviewSession = null),
      );
    }
    final grammarSession = _grammarSession;
    if (grammarSession != null) {
      return _GrammarQuizSession(
        points: grammarSession,
        controller: widget.controller,
        onClose: () => setState(() => _grammarSession = null),
      );
    }

    return Column(
      key: const ValueKey('study-dashboard'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: SegmentedButton<_StudySection>(
            key: const ValueKey('study-section-selector'),
            segments: const [
              ButtonSegment(
                value: _StudySection.weakReview,
                icon: Icon(Icons.refresh_rounded),
                label: Text('약점 복습'),
              ),
              ButtonSegment(
                value: _StudySection.grammar,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('문법 덱'),
              ),
              ButtonSegment(
                value: _StudySection.nuance,
                icon: Icon(Icons.forum_outlined),
                label: Text('뉘앙스 덱'),
              ),
            ],
            selected: {_section},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() {
              _section = value.single;
            }),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppDurations.standard,
            child: switch (_section) {
              _StudySection.weakReview => _WeakReviewDashboard(
                key: const ValueKey('weak-review-dashboard'),
                controller: widget.controller,
                onOpenWord: widget.onOpenWord,
                onStart: (items) => setState(() {
                  _reviewSession = items;
                }),
              ),
              _StudySection.grammar => _GrammarDeck(
                key: const ValueKey('grammar-deck'),
                controller: widget.controller,
                linkIndex: widget.linkIndex,
                onOpenWord: widget.onOpenWord,
                onStartQuiz: (points) => setState(() {
                  _grammarSession = points;
                }),
              ),
              _StudySection.nuance => ConversationNuanceDeck(
                key: const ValueKey('nuance-deck'),
                controller: widget.controller,
                linkIndex: widget.linkIndex,
                onOpenWord: widget.onOpenWord,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _WeakReviewDashboard extends StatelessWidget {
  const _WeakReviewDashboard({
    super.key,
    required this.controller,
    required this.onOpenWord,
    required this.onStart,
  });

  final StudyController controller;
  final ValueChanged<JapaneseWord> onOpenWord;
  final ValueChanged<List<WeakReviewItem>> onStart;

  @override
  Widget build(BuildContext context) {
    final items = controller.weakReviewQueue();
    final existing = items
        .where((item) => item.reason != WeakReviewReason.firstCheck)
        .length;
    final firstChecks = items.length - existing;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadii.largeCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppColors.moon),
                  SizedBox(width: 8),
                  Text(
                    '오늘의 약점 복습',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '오답은 10분 뒤, 연속 정답은 1·3·7·14·30·60일 간격으로 다시 만나요.',
                style: TextStyle(
                  color: AppColors.onDarkMuted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DarkMetric(label: '복습', value: '$existing개'),
                  _DarkMetric(label: '첫 확인', value: '$firstChecks개'),
                  _DarkMetric(
                    label: '오늘 목표',
                    value: '${controller.dailyGoal}개',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('weak-review-start'),
                  onPressed: items.isEmpty ? null : () => onStart(items),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.moon,
                    foregroundColor: AppColors.ink,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('${items.length}개 복습 시작'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          items.isEmpty ? '오늘 복습을 마쳤어요' : '오늘 만날 단어',
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.task_alt_rounded,
            title: '복습할 단어가 없어요',
            message: '퀴즈를 풀면 결과에 맞춰 다음 복습 시간이 자동으로 정해져요.',
          )
        else
          for (final item in items.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: ValueKey('weak-review-preview-${item.word.id}'),
                onTap: () => onOpenWord(item.word),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  side: const BorderSide(color: AppColors.cardOutline),
                ),
                title: Text(
                  item.word.lemma,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontFamily: AppFonts.japanese,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  item.word.primaryMeaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item.reason == WeakReviewReason.firstCheck
                        ? AppColors.toggleSurface
                        : AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    item.reasonLabel,
                    style: TextStyle(
                      color: item.reason == WeakReviewReason.firstCheck
                          ? AppColors.body
                          : AppColors.errorText,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(color: AppColors.onDarkMuted),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.moon,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _WeakReviewSession extends StatefulWidget {
  const _WeakReviewSession({
    required this.items,
    required this.pool,
    required this.controller,
    required this.onOpenWord,
    required this.onClose,
  });

  final List<WeakReviewItem> items;
  final List<JapaneseWord> pool;
  final StudyController controller;
  final ValueChanged<JapaneseWord> onOpenWord;
  final VoidCallback onClose;

  @override
  State<_WeakReviewSession> createState() => _WeakReviewSessionState();
}

class _WeakReviewSessionState extends State<_WeakReviewSession> {
  var _index = 0;
  var _score = 0;
  String? _selected;
  late List<String> _options;

  JapaneseWord get _word => widget.items[_index].word;

  @override
  void initState() {
    super.initState();
    _options = _optionsFor(_word);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('weak-review-session'),
      children: [
        _SessionHeader(
          label: '약점 복습',
          progress: '${_index + 1} / ${widget.items.length}',
          value: (_index + 1) / widget.items.length,
          onClose: widget.onClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
            children: [
              Text(
                widget.items[_index].reasonLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.reading,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              AozoraRubyText(
                buildAozoraRubySource(_word.lemma, _word.reading),
                key: ValueKey('weak-review-word-${_word.id}'),
                textAlign: TextAlign.center,
                baseStyle: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: AppFonts.japanese,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
                rubyStyle: const TextStyle(
                  color: AppColors.reading,
                  fontFamily: AppFonts.japanese,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 26),
              for (final option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _AnswerTile(
                    label: option,
                    selected: _selected == option,
                    correct: _selected == null
                        ? null
                        : option == _word.primaryMeaning,
                    onTap: _selected == null ? () => _answer(option) : null,
                  ),
                ),
              if (_selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selected == _word.primaryMeaning
                      ? '정답이에요'
                      : '정답: ${_word.primaryMeaning}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _selected == _word.primaryMeaning
                        ? AppColors.successText
                        : AppColors.errorText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onOpenWord(_word),
                  child: const Text('단어 자세히 보기'),
                ),
                FilledButton(
                  key: const ValueKey('weak-review-next'),
                  onPressed: _next,
                  child: Text(
                    _index == widget.items.length - 1 ? '결과 보기' : '다음 단어',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<String> _optionsFor(JapaneseWord word) {
    final values = <String>{word.primaryMeaning};
    final shuffled = [...widget.pool]..shuffle(math.Random(word.id.hashCode));
    for (final candidate in shuffled) {
      if (values.length >= 4) break;
      values.add(candidate.primaryMeaning);
    }
    return values.toList()..shuffle(math.Random(word.id.hashCode ^ 0x5f3759df));
  }

  void _answer(String option) {
    final correct = option == _word.primaryMeaning;
    widget.controller.recordQuizAnswer(_word.id, correct: correct);
    setState(() {
      _selected = option;
      if (correct) _score += 1;
    });
  }

  void _next() {
    if (_index == widget.items.length - 1) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('오늘 복습 완료'),
          content: Text('${widget.items.length}개 중 $_score개를 맞혔어요.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onClose();
              },
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _index += 1;
      _selected = null;
      _options = _optionsFor(_word);
    });
  }
}

class _GrammarDeck extends StatefulWidget {
  const _GrammarDeck({
    super.key,
    required this.controller,
    required this.linkIndex,
    required this.onOpenWord,
    required this.onStartQuiz,
  });

  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;
  final ValueChanged<List<GrammarPoint>> onStartQuiz;

  @override
  State<_GrammarDeck> createState() => _GrammarDeckState();
}

enum _GrammarMasteryFilter { all, unmastered, mastered }

enum _GrammarSort { basic, random }

class _GrammarDeckState extends State<_GrammarDeck> {
  var _index = 0;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  late Set<JlptLevel> _selectedLevels;
  late Set<JlptLevel> _lastControllerLevels;
  late List<String> _randomOrder;
  var _query = '';
  var _masteryFilter = _GrammarMasteryFilter.all;
  var _sort = _GrammarSort.basic;
  var _randomSeed = DateTime.now().microsecondsSinceEpoch;
  var _controlsExpanded = false;

  @override
  void initState() {
    super.initState();
    _lastControllerLevels = Set.of(widget.controller.selectedWordLevels);
    _selectedLevels = Set.of(_lastControllerLevels);
    _randomOrder = _newRandomOrder();
  }

  @override
  void didUpdateWidget(covariant _GrammarDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextControllerLevels = Set.of(widget.controller.selectedWordLevels);
    if (oldWidget.controller == widget.controller &&
        setEquals(nextControllerLevels, _lastControllerLevels)) {
      return;
    }
    _lastControllerLevels = nextControllerLevels;
    _selectedLevels = Set.of(nextControllerLevels);
    _index = 0;
    _controlsExpanded = false;
    _scrollToTop();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<GrammarPoint> get _points {
    final normalizedQuery = normalizeVocabularySearch(_query);
    final filtered = jlptGrammarCatalog
        .where((point) => _selectedLevels.contains(point.level))
        .where((point) {
          final mastered = widget.controller.isGrammarMastered(point.id);
          return switch (_masteryFilter) {
            _GrammarMasteryFilter.all => true,
            _GrammarMasteryFilter.unmastered => !mastered,
            _GrammarMasteryFilter.mastered => mastered,
          };
        })
        .where(
          (point) =>
              normalizedQuery.isEmpty ||
              _grammarSearchText(point).contains(normalizedQuery),
        )
        .toList(growable: false);
    if (_sort == _GrammarSort.basic) return filtered;

    final randomRank = <String, int>{
      for (var index = 0; index < _randomOrder.length; index++)
        _randomOrder[index]: index,
    };
    return [...filtered]..sort(
      (left, right) => (randomRank[left.id] ?? jlptGrammarCatalog.length)
          .compareTo(randomRank[right.id] ?? jlptGrammarCatalog.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (points.isEmpty) {
      _index = 0;
    } else if (_index >= points.length) {
      _index = points.length - 1;
    }
    final point = points.isEmpty ? null : points[_index];
    final mastered =
        point != null && widget.controller.isGrammarMastered(point.id);
    final masteredCount = points
        .where((value) => widget.controller.isGrammarMastered(value.id))
        .length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('grammar-card-scroll'),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '데모 문법 덱',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          '검색과 필터로 필요한 문법부터 학습해 보세요.',
                          style: TextStyle(
                            color: AppColors.subtleText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('grammar-quiz-start'),
                    onPressed: points.isEmpty
                        ? null
                        : () => widget.onStartQuiz(_quizPoints(points)),
                    icon: const Icon(Icons.quiz_outlined, size: 18),
                    label: const Text('문제 풀기'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _GrammarDeckControls(
                searchController: _searchController,
                query: _query,
                selectedLevels: _selectedLevels,
                masteryFilter: _masteryFilter,
                sort: _sort,
                expanded: _controlsExpanded,
                onQueryChanged: _setQuery,
                onClearQuery: _clearQuery,
                onToggleExpanded: () =>
                    setState(() => _controlsExpanded = !_controlsExpanded),
                onLevelToggled: _toggleLevel,
                onToggleAllLevels: _toggleAllLevels,
                onMasteryFilterChanged: _setMasteryFilter,
                onSortChanged: _setSort,
                onReshuffle: _reshuffle,
              ),
              const SizedBox(height: 12),
              _GrammarResultSummary(
                resultCount: points.length,
                totalCount: jlptGrammarCatalog.length,
                masteredCount: masteredCount,
                currentIndex: point == null ? null : _index,
              ),
              const SizedBox(height: 12),
              if (point == null)
                EmptyState(
                  key: const ValueKey('grammar-filter-empty'),
                  icon: _query.trim().isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.filter_alt_off_rounded,
                  title: _query.trim().isNotEmpty
                      ? '검색 결과가 없어요'
                      : '필터에 맞는 문법이 없어요',
                  message: '검색어나 데모 범위, 외움 상태를 바꿔 보세요.',
                  action: _query.trim().isNotEmpty
                      ? OutlinedButton.icon(
                          key: const ValueKey('grammar-clear-search'),
                          onPressed: _clearQuery,
                          icon: const Icon(Icons.backspace_outlined),
                          label: const Text('검색어 지우기'),
                        )
                      : OutlinedButton.icon(
                          key: const ValueKey('grammar-clear-filters'),
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off_rounded),
                          label: const Text('필터 해제'),
                        ),
                )
              else
                AnimatedSwitcher(
                  duration: AppDurations.standard,
                  child: Container(
                    key: ValueKey('grammar-card-${point.id}'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.largeCard),
                      border: Border.all(color: AppColors.cardOutline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                              child: Text(
                                point.level.label,
                                style: const TextStyle(
                                  color: AppColors.moon,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              key: ValueKey(
                                'grammar-mastered-icon-${point.id}',
                              ),
                              tooltip: mastered ? '외웠어요 취소' : '외웠어요',
                              onPressed: () => _toggleMastered(point),
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                foregroundColor: mastered
                                    ? AppColors.success
                                    : AppColors.subtleText,
                                backgroundColor: mastered
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : AppColors.softSurface,
                                side: BorderSide(
                                  color: mastered
                                      ? AppColors.success.withValues(
                                          alpha: 0.32,
                                        )
                                      : AppColors.cardOutline,
                                ),
                                shape: const CircleBorder(),
                              ),
                              icon: Icon(
                                mastered
                                    ? Icons.check_circle_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 20,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '현재 ${_index + 1} / ${points.length}',
                              key: const ValueKey('grammar-current-position'),
                              style: const TextStyle(
                                color: AppColors.body,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          point.pattern,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontFamily: AppFonts.japanese,
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          point.meaning,
                          style: const TextStyle(
                            color: AppColors.reading,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _GrammarInfo(label: '접속', text: point.formation),
                        const SizedBox(height: 12),
                        _GrammarInfo(label: '쓰임', text: point.explanation),
                        const Divider(height: 30),
                        const Text(
                          '기본 예문',
                          style: TextStyle(
                            color: AppColors.subtleText,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LinkedAozoraRubyText(
                                point.exampleRuby,
                                linkIndex: widget.linkIndex,
                                onWordTap: widget.onOpenWord,
                                baseStyle: const TextStyle(
                                  color: AppColors.ink,
                                  fontFamily: AppFonts.japanese,
                                  fontSize: 16,
                                  height: 1.75,
                                  fontWeight: FontWeight.w700,
                                ),
                                rubyStyle: const TextStyle(
                                  color: AppColors.reading,
                                  fontFamily: AppFonts.japanese,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            JapaneseTtsButton(
                              key: ValueKey('grammar-tts-${point.id}'),
                              text: spokenAozoraRuby(point.exampleRuby),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          point.translation,
                          style: const TextStyle(
                            color: AppColors.body,
                            height: 1.5,
                          ),
                        ),
                        const Divider(height: 28),
                        const Text(
                          '회화 예문',
                          style: TextStyle(
                            color: AppColors.reading,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LinkedAozoraRubyText(
                                point.conversationExampleRuby,
                                linkIndex: widget.linkIndex,
                                onWordTap: widget.onOpenWord,
                                baseStyle: const TextStyle(
                                  color: AppColors.ink,
                                  fontFamily: AppFonts.japanese,
                                  fontSize: 16,
                                  height: 1.75,
                                  fontWeight: FontWeight.w700,
                                ),
                                rubyStyle: const TextStyle(
                                  color: AppColors.reading,
                                  fontFamily: AppFonts.japanese,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            JapaneseTtsButton(
                              key: ValueKey(
                                'grammar-conversation-tts-${point.id}',
                              ),
                              text: spokenAozoraRuby(
                                point.conversationExampleRuby,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          point.conversationTranslation,
                          style: const TextStyle(
                            color: AppColors.body,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: ValueKey('grammar-mastered-${point.id}'),
                            onPressed: () => _toggleMastered(point),
                            icon: Icon(
                              mastered
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: mastered
                                  ? AppColors.success
                                  : AppColors.subtleText,
                            ),
                            label: Text(mastered ? '외운 문법' : '외웠어요'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                '문법 카드는 공개 데모용이며, 묶음은 시험 급수나 난도를 나타내지 않습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.paper,
            border: Border(top: BorderSide(color: AppColors.cardOutline)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('grammar-previous'),
                    onPressed: points.isEmpty || _index == 0
                        ? null
                        : () => _move(-1, points),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('이전'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('grammar-next'),
                    onPressed: points.isEmpty || _index == points.length - 1
                        ? null
                        : () => _move(1, points),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('다음'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _move(int delta, List<GrammarPoint> points) {
    if (points.isEmpty) return;
    final next = (_index + delta).clamp(0, points.length - 1);
    if (next == _index) return;
    setState(() {
      _index = next;
      _controlsExpanded = false;
    });
    widget.controller.recordGrammarStudied(points[next].id);
    _scrollToTop(animate: true);
  }

  void _setQuery(String value) {
    _updateExplorer(() => _query = value);
  }

  void _clearQuery() {
    _searchController.clear();
    _updateExplorer(() => _query = '');
  }

  void _toggleLevel(JlptLevel level) {
    _updateExplorer(() {
      if (_selectedLevels.contains(level)) {
        _selectedLevels.remove(level);
      } else {
        _selectedLevels.add(level);
      }
    });
  }

  void _toggleAllLevels() {
    _updateExplorer(() {
      if (_selectedLevels.length == JlptLevel.values.length) {
        _selectedLevels.clear();
      } else {
        _selectedLevels = Set.of(JlptLevel.values);
      }
    });
  }

  void _setMasteryFilter(_GrammarMasteryFilter value) {
    if (_masteryFilter == value) return;
    _updateExplorer(() => _masteryFilter = value);
  }

  void _toggleMastered(GrammarPoint point) {
    final leavesVisibleResults = _masteryFilter == _GrammarMasteryFilter.all;
    widget.controller.toggleGrammarMastered(point.id);
    if (leavesVisibleResults) return;
    setState(() => _controlsExpanded = false);
    _scrollToTop();
  }

  void _setSort(_GrammarSort value) {
    if (_sort == value) return;
    _updateExplorer(() => _sort = value);
  }

  void _reshuffle() {
    final visibleIds = _points.map((point) => point.id).toSet();
    final previousFirst = _points.isEmpty ? null : _points.first.id;
    final next = _newRandomOrder();
    final nextVisibleIndex = next.indexWhere(visibleIds.contains);
    if (visibleIds.length > 1 &&
        nextVisibleIndex >= 0 &&
        next[nextVisibleIndex] == previousFirst) {
      final replacementIndex = next.indexWhere(
        (id) => visibleIds.contains(id) && id != previousFirst,
        nextVisibleIndex + 1,
      );
      if (replacementIndex >= 0) {
        final first = next[nextVisibleIndex];
        next[nextVisibleIndex] = next[replacementIndex];
        next[replacementIndex] = first;
      }
    }
    _updateExplorer(() {
      _randomOrder = next;
      _sort = _GrammarSort.random;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _updateExplorer(() {
      _query = '';
      _selectedLevels = Set.of(JlptLevel.values);
      _masteryFilter = _GrammarMasteryFilter.all;
      _sort = _GrammarSort.basic;
      _controlsExpanded = false;
    });
  }

  void _updateExplorer(VoidCallback update) {
    setState(() {
      update();
      _index = 0;
    });
    _scrollToTop();
  }

  void _scrollToTop({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          0,
          duration: AppDurations.standard,
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  List<String> _newRandomOrder() {
    final ids = jlptGrammarCatalog.map((point) => point.id).toList();
    ids.shuffle(math.Random(_randomSeed++));
    return ids;
  }

  String _grammarSearchText(GrammarPoint point) {
    return normalizeVocabularySearch(
      [
        point.level.label,
        point.pattern,
        point.meaning,
        point.formation,
        point.explanation,
        point.example,
        spokenAozoraRuby(point.exampleRuby),
        point.translation,
        point.conversationExample,
        spokenAozoraRuby(point.conversationExampleRuby),
        point.conversationTranslation,
      ].join('\u0000'),
    );
  }

  List<GrammarPoint> _quizPoints(List<GrammarPoint> points) {
    final ordered = [...points]
      ..sort((left, right) {
        final leftMastered = widget.controller.isGrammarMastered(left.id);
        final rightMastered = widget.controller.isGrammarMastered(right.id);
        if (leftMastered != rightMastered) return leftMastered ? 1 : -1;
        final accuracy = widget.controller
            .grammarAccuracyFor(left.id)
            .compareTo(widget.controller.grammarAccuracyFor(right.id));
        return accuracy != 0 ? accuracy : left.id.compareTo(right.id);
      });
    return ordered.take(10).toList(growable: false);
  }
}

class _GrammarDeckControls extends StatelessWidget {
  const _GrammarDeckControls({
    required this.searchController,
    required this.query,
    required this.selectedLevels,
    required this.masteryFilter,
    required this.sort,
    required this.expanded,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onToggleExpanded,
    required this.onLevelToggled,
    required this.onToggleAllLevels,
    required this.onMasteryFilterChanged,
    required this.onSortChanged,
    required this.onReshuffle,
  });

  final TextEditingController searchController;
  final String query;
  final Set<JlptLevel> selectedLevels;
  final _GrammarMasteryFilter masteryFilter;
  final _GrammarSort sort;
  final bool expanded;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onToggleExpanded;
  final ValueChanged<JlptLevel> onLevelToggled;
  final VoidCallback onToggleAllLevels;
  final ValueChanged<_GrammarMasteryFilter> onMasteryFilterChanged;
  final ValueChanged<_GrammarSort> onSortChanged;
  final VoidCallback onReshuffle;

  @override
  Widget build(BuildContext context) {
    final allLevelsSelected = selectedLevels.length == JlptLevel.values.length;
    final levelSummary = selectedLevels.isEmpty
        ? '범위 없음'
        : allLevelsSelected
        ? '데모 1~5'
        : JlptLevel.values
              .where(selectedLevels.contains)
              .map((level) => level.label)
              .join('·');
    final masterySummary = switch (masteryFilter) {
      _GrammarMasteryFilter.all => '전체',
      _GrammarMasteryFilter.unmastered => '미완료',
      _GrammarMasteryFilter.mastered => '완료',
    };
    final sortSummary = sort == _GrammarSort.basic ? '기본' : '랜덤';
    return Container(
      key: const ValueKey('grammar-explorer-controls'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('grammar-search-field'),
            controller: searchController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '문법·뜻·접속·해설·예문 검색',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('grammar-search-clear-icon'),
                      tooltip: '검색어 지우기',
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            key: const ValueKey('grammar-filter-options-toggle'),
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppColors.mutedBlue,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text(
                    '필터·정렬',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '$levelSummary · $masterySummary · $sortSummary',
                      key: const ValueKey('grammar-filter-summary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.subtleText,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: AppColors.subtleText,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                const Expanded(child: _GrammarControlLabel('데모 범위')),
                TextButton(
                  key: const ValueKey('grammar-level-toggle-all'),
                  onPressed: onToggleAllLevels,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  child: Text(allLevelsSelected ? '전체 해제' : '전체 선택'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final level in JlptLevel.values)
                  CompactToggle(
                    key: ValueKey('grammar-level-${level.name}'),
                    label: level.label,
                    semanticsLabel: '${level.label} 문법 범위',
                    value: selectedLevels.contains(level),
                    selectedIcon: Icons.check_circle_rounded,
                    unselectedIcon: Icons.circle_outlined,
                    minimumTapTargetHeight: 48,
                    onChanged: (_) => onLevelToggled(level),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _GrammarControlLabel('외움 상태'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                CompactToggle(
                  key: const ValueKey('grammar-mastery-all'),
                  label: '전체',
                  semanticsLabel: '전체 문법 표시',
                  value: masteryFilter == _GrammarMasteryFilter.all,
                  selectedIcon: Icons.library_books_rounded,
                  unselectedIcon: Icons.library_books_outlined,
                  exclusiveSelection: true,
                  minimumTapTargetHeight: 48,
                  onChanged: (_) =>
                      onMasteryFilterChanged(_GrammarMasteryFilter.all),
                ),
                CompactToggle(
                  key: const ValueKey('grammar-mastery-unmastered'),
                  label: '미완료',
                  semanticsLabel: '외우지 않은 문법만 표시',
                  value: masteryFilter == _GrammarMasteryFilter.unmastered,
                  selectedIcon: Icons.radio_button_unchecked_rounded,
                  unselectedIcon: Icons.radio_button_unchecked_rounded,
                  exclusiveSelection: true,
                  minimumTapTargetHeight: 48,
                  onChanged: (_) =>
                      onMasteryFilterChanged(_GrammarMasteryFilter.unmastered),
                ),
                CompactToggle(
                  key: const ValueKey('grammar-mastery-mastered'),
                  label: '완료',
                  semanticsLabel: '외운 문법만 표시',
                  value: masteryFilter == _GrammarMasteryFilter.mastered,
                  selectedIcon: Icons.check_circle_rounded,
                  unselectedIcon: Icons.check_circle_outline_rounded,
                  exclusiveSelection: true,
                  minimumTapTargetHeight: 48,
                  onChanged: (_) =>
                      onMasteryFilterChanged(_GrammarMasteryFilter.mastered),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _GrammarControlLabel('정렬'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CompactToggle(
                  key: const ValueKey('grammar-sort-basic'),
                  label: '기본',
                  semanticsLabel: '기본 문법 순서',
                  value: sort == _GrammarSort.basic,
                  selectedIcon: Icons.format_list_numbered_rounded,
                  unselectedIcon: Icons.format_list_numbered_rounded,
                  exclusiveSelection: true,
                  minimumTapTargetHeight: 48,
                  onChanged: (_) => onSortChanged(_GrammarSort.basic),
                ),
                CompactToggle(
                  key: const ValueKey('grammar-sort-random'),
                  label: '랜덤',
                  semanticsLabel: '랜덤 문법 순서',
                  value: sort == _GrammarSort.random,
                  selectedIcon: Icons.shuffle_rounded,
                  unselectedIcon: Icons.shuffle_rounded,
                  exclusiveSelection: true,
                  minimumTapTargetHeight: 48,
                  onChanged: (_) => onSortChanged(_GrammarSort.random),
                ),
                if (sort == _GrammarSort.random)
                  ActionChip(
                    key: const ValueKey('grammar-random-reshuffle'),
                    avatar: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('다시 섞기'),
                    tooltip: '새 랜덤 순서 만들기',
                    onPressed: onReshuffle,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GrammarControlLabel extends StatelessWidget {
  const _GrammarControlLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _GrammarResultSummary extends StatelessWidget {
  const _GrammarResultSummary({
    required this.resultCount,
    required this.totalCount,
    required this.masteredCount,
    required this.currentIndex,
  });

  final int resultCount;
  final int totalCount;
  final int masteredCount;
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('grammar-result-summary'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '필터 결과 $resultCount개 · 전체 $totalCount개',
                  key: const ValueKey('grammar-result-count'),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (currentIndex != null)
                Text(
                  '현재 ${currentIndex! + 1} / $resultCount',
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Text(
                '외움 진행',
                style: TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$masteredCount / $resultCount개',
                key: const ValueKey('grammar-mastery-summary'),
                style: const TextStyle(
                  color: AppColors.successText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            key: const ValueKey('grammar-mastery-progress'),
            minHeight: 5,
            value: resultCount == 0 ? 0 : masteredCount / resultCount,
            backgroundColor: AppColors.toggleSurface,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _GrammarInfo extends StatelessWidget {
  const _GrammarInfo({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.body, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _GrammarQuizSession extends StatefulWidget {
  const _GrammarQuizSession({
    required this.points,
    required this.controller,
    required this.onClose,
  });

  final List<GrammarPoint> points;
  final StudyController controller;
  final VoidCallback onClose;

  @override
  State<_GrammarQuizSession> createState() => _GrammarQuizSessionState();
}

class _GrammarQuizSessionState extends State<_GrammarQuizSession> {
  var _index = 0;
  var _score = 0;
  String? _selected;
  late List<String> _options;

  GrammarPoint get _point => widget.points[_index];

  @override
  void initState() {
    super.initState();
    _options = _optionsFor(_point);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('grammar-quiz-session'),
      children: [
        _SessionHeader(
          label: '문법 문제',
          progress: '${_index + 1} / ${widget.points.length}',
          value: (_index + 1) / widget.points.length,
          onClose: widget.onClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
            children: [
              const Text(
                '다음 뜻에 맞는 문법을 고르세요',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subtleText),
              ),
              const SizedBox(height: 14),
              Text(
                _point.meaning,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 26),
              for (final option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _AnswerTile(
                    label: option,
                    japanese: true,
                    selected: _selected == option,
                    correct: _selected == null
                        ? null
                        : option == _point.pattern,
                    onTap: _selected == null ? () => _answer(option) : null,
                  ),
                ),
              if (_selected != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: AppColors.warmSurface,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _point.example,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontFamily: AppFonts.japanese,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(_point.translation),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('grammar-quiz-next'),
                  onPressed: _next,
                  child: Text(
                    _index == widget.points.length - 1 ? '결과 보기' : '다음 문제',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<String> _optionsFor(GrammarPoint point) {
    final sameLevel =
        jlptGrammarCatalog
            .where((candidate) => candidate.level == point.level)
            .toList()
          ..shuffle(math.Random(point.id.hashCode));
    final values = <String>{point.pattern};
    for (final candidate in sameLevel) {
      if (values.length >= 4) break;
      values.add(candidate.pattern);
    }
    return values.toList()
      ..shuffle(math.Random(point.id.hashCode ^ 0x1f123bb5));
  }

  void _answer(String option) {
    final correct = option == _point.pattern;
    widget.controller.recordGrammarAnswer(_point.id, correct: correct);
    setState(() {
      _selected = option;
      if (correct) _score += 1;
    });
  }

  void _next() {
    if (_index == widget.points.length - 1) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('문법 문제 완료'),
          content: Text('${widget.points.length}문제 중 $_score문제를 맞혔어요.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onClose();
              },
              child: const Text('문법 덱으로'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _index += 1;
      _selected = null;
      _options = _optionsFor(_point);
    });
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.label,
    required this.progress,
    required this.value,
    required this.onClose,
  });

  final String label;
  final String progress;
  final double value;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: onClose,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onDarkMuted,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('그만두기'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                progress,
                style: const TextStyle(
                  color: AppColors.moon,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: value,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppColors.moon),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
    this.japanese = false,
  });

  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback? onTap;
  final bool japanese;

  @override
  Widget build(BuildContext context) {
    final revealedCorrect = correct == true;
    final revealedWrong = selected && correct == false;
    return Material(
      color: revealedCorrect
          ? AppColors.successContainer
          : revealedWrong
          ? AppColors.errorContainer
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(
          color: revealedCorrect
              ? AppColors.success
              : revealedWrong
              ? AppColors.error
              : AppColors.cardOutline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontFamily: japanese ? AppFonts.japanese : null,
                    fontSize: japanese ? 16 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (revealedCorrect)
                const Icon(Icons.check_circle_rounded, color: AppColors.success)
              else if (revealedWrong)
                const Icon(Icons.cancel_rounded, color: AppColors.error),
            ],
          ),
        ),
      ),
    );
  }
}
