import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../data/conversation_nuance_catalog.dart';
import '../../domain/conversation_nuance.dart';
import '../../domain/vocabulary.dart';
import '../../domain/word_order.dart';
import '../../theme/app_theme.dart';
import 'common_widgets.dart';
import 'japanese_tts_button.dart';
import 'linked_aozora_ruby_text.dart';

/// A compact study deck for expressions whose conversational tone is easy to
/// miss in a dictionary translation.
///
/// Mastery is stored through the existing grammar persistence keys with a
/// `nuance-` namespace, so this feature does not need a second state store.
class ConversationNuanceDeck extends StatefulWidget {
  const ConversationNuanceDeck({
    super.key,
    required this.controller,
    required this.linkIndex,
    required this.onOpenWord,
  });

  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;

  @override
  State<ConversationNuanceDeck> createState() => _ConversationNuanceDeckState();
}

class _ConversationNuanceDeckState extends State<ConversationNuanceDeck> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  var _query = '';
  var _registerFilter = _NuanceRegisterFilter.all;
  var _masteryFilter = _NuanceMasteryFilter.all;
  var _sort = _NuanceSort.catalog;
  var _controlsExpanded = false;
  late int _randomSeed;
  String? _selectedPointId;

  List<ConversationNuancePoint> get _points {
    final normalizedQuery = normalizeVocabularySearch(_query);
    final points = <ConversationNuancePoint>[
      for (final point in conversationNuanceCatalog)
        if (_matchesRegister(point) &&
            _matchesMastery(point) &&
            _matchesQuery(point, normalizedQuery))
          point,
    ];
    if (_sort == _NuanceSort.random) {
      points.sort((left, right) {
        final order = stableWordOrderKey(
          left.id,
          _randomSeed,
        ).compareTo(stableWordOrderKey(right.id, _randomSeed));
        return order != 0 ? order : left.id.compareTo(right.id);
      });
    }
    return points;
  }

  @override
  void initState() {
    super.initState();
    _randomSeed = DateTime.now().microsecondsSinceEpoch;
    _selectedPointId = conversationNuanceCatalog.isEmpty
        ? null
        : conversationNuanceCatalog.first.id;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ConversationNuanceDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _reconcileSelection();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(_reconcileSelection);
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final index = _visibleIndex(points);
    final point = index < 0 ? null : points[index];
    final mastered = point == null ? false : _isMastered(point);
    final masteredCount = points.where(_isMastered).length;
    final position = index < 0 ? 0 : index + 1;
    final total = conversationNuanceCatalog.length;

    return Column(
      key: const ValueKey('conversation-nuance-deck'),
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('conversation-nuance-scroll'),
            controller: _scrollController,
            cacheExtent: 1600,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            children: [
              const Text(
                '회화 뉘앙스 덱',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '검색과 필터로 실제 대화에서 필요한 표현부터 학습해 보세요.',
                style: TextStyle(color: AppColors.subtleText, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('conversation-nuance-explorer-controls'),
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
                      key: const ValueKey('conversation-nuance-search'),
                      controller: _searchController,
                      onChanged: _setQuery,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '표현·뜻·느낌·예문 검색',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                key: const ValueKey(
                                  'conversation-nuance-search-clear',
                                ),
                                tooltip: '검색어 지우기',
                                onPressed: _clearQuery,
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    InkWell(
                      key: const ValueKey(
                        'conversation-nuance-filter-options-toggle',
                      ),
                      onTap: () => setState(
                        () => _controlsExpanded = !_controlsExpanded,
                      ),
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
                                '${_registerFilter.label} · '
                                '${_masteryFilter.label} · '
                                '${_sort == _NuanceSort.catalog ? '기본' : '랜덤'}',
                                key: const ValueKey(
                                  'conversation-nuance-filter-summary',
                                ),
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
                              _controlsExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: AppColors.subtleText,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_controlsExpanded) ...[
                      const Divider(height: AppSpacing.xl),
                      _NuanceFilterGroup(
                        label: '말투·격식',
                        children: [
                          for (final filter in _NuanceRegisterFilter.values)
                            _filterChip(
                              key: ValueKey(
                                'conversation-nuance-register-${filter.name}',
                              ),
                              label: filter.label,
                              selected: _registerFilter == filter,
                              onSelected: () => _setRegisterFilter(filter),
                              icon: filter.icon,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _NuanceFilterGroup(
                        label: '외움 상태',
                        children: [
                          for (final filter in _NuanceMasteryFilter.values)
                            _filterChip(
                              key: ValueKey(
                                'conversation-nuance-mastery-${filter.name}',
                              ),
                              label: filter.label,
                              selected: _masteryFilter == filter,
                              onSelected: () => _setMasteryFilter(filter),
                              icon: filter.icon,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _NuanceFilterGroup(
                        label: '정렬',
                        children: [
                          _filterChip(
                            key: const ValueKey(
                              'conversation-nuance-sort-catalog',
                            ),
                            label: '기본',
                            selected: _sort == _NuanceSort.catalog,
                            onSelected: () => _setSort(_NuanceSort.catalog),
                            icon: Icons.format_list_numbered_rounded,
                          ),
                          _filterChip(
                            key: const ValueKey(
                              'conversation-nuance-sort-random',
                            ),
                            label: '랜덤',
                            selected: _sort == _NuanceSort.random,
                            onSelected: () => _setSort(_NuanceSort.random),
                            icon: Icons.shuffle_rounded,
                          ),
                          if (_sort == _NuanceSort.random)
                            ActionChip(
                              key: const ValueKey(
                                'conversation-nuance-random-reshuffle',
                              ),
                              avatar: const Icon(
                                Icons.refresh_rounded,
                                size: 16,
                              ),
                              label: const Text('다시 섞기'),
                              tooltip: '새 랜덤 순서 만들기',
                              onPressed: _reshuffle,
                            ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const ValueKey(
                            'conversation-nuance-reset-filters',
                          ),
                          onPressed: _hasActiveViewOptions
                              ? _resetViewOptions
                              : null,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('초기화'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _NuanceResultSummary(
                resultCount: points.length,
                totalCount: total,
                masteredCount: masteredCount,
                currentIndex: point == null ? null : index,
              ),
              const SizedBox(height: 12),
              if (point == null)
                _NuanceEmptyState(hasQuery: _query.isNotEmpty)
              else ...[
                AnimatedSwitcher(
                  duration: AppDurations.standard,
                  child: _NuanceCard(
                    key: ValueKey('conversation-nuance-card-${point.id}'),
                    point: point,
                    position: position,
                    total: points.length,
                    mastered: mastered,
                    linkIndex: widget.linkIndex,
                    onOpenWord: widget.onOpenWord,
                    onToggleMastered: () => _toggleMastered(point),
                  ),
                ),
              ],
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
                    key: const ValueKey('conversation-nuance-previous'),
                    onPressed: index <= 0 ? null : () => _move(-1, points),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('이전'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('conversation-nuance-next'),
                    onPressed: index < 0 || index == points.length - 1
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

  bool _isMastered(ConversationNuancePoint point) =>
      widget.controller.isGrammarMastered(_persistentId(point));

  String _persistentId(ConversationNuancePoint point) =>
      point.id.startsWith('nuance-') ? point.id : 'nuance-${point.id}';

  bool get _hasActiveViewOptions =>
      _query.isNotEmpty ||
      _registerFilter != _NuanceRegisterFilter.all ||
      _masteryFilter != _NuanceMasteryFilter.all ||
      _sort != _NuanceSort.catalog;

  bool _matchesRegister(ConversationNuancePoint point) {
    final label = point.registerLabel;
    return switch (_registerFilter) {
      _NuanceRegisterFilter.all => true,
      _NuanceRegisterFilter.casual =>
        label.contains('편한') || label.contains('친근') || label.contains('캐주얼'),
      _NuanceRegisterFilter.flexible =>
        label.contains('일상') || label.contains('정중') || label.contains('문어'),
      _NuanceRegisterFilter.sensitive =>
        label.contains('주의') ||
            label.contains('차이') ||
            label.contains('지역') ||
            label.contains('강한'),
    };
  }

  bool _matchesMastery(ConversationNuancePoint point) =>
      switch (_masteryFilter) {
        _NuanceMasteryFilter.all => true,
        _NuanceMasteryFilter.pending => !_isMastered(point),
        _NuanceMasteryFilter.mastered => _isMastered(point),
      };

  bool _matchesQuery(ConversationNuancePoint point, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final document = <String>[
      point.pattern,
      point.shortMeaning,
      point.registerLabel,
      point.toneLabel,
      point.formation,
      point.explanation,
      point.caution,
      point.contrast,
      for (final example in point.examples) ...[
        example.sentence,
        spokenAozoraRuby(example.sentenceRuby),
        example.translation,
        example.situation,
      ],
    ].join('\u0000');
    return normalizeVocabularySearch(document).contains(normalizedQuery);
  }

  int _visibleIndex(List<ConversationNuancePoint> points) {
    if (points.isEmpty) return -1;
    final index = points.indexWhere((point) => point.id == _selectedPointId);
    return index < 0 ? 0 : index;
  }

  void _reconcileSelection() {
    final points = _points;
    if (points.isEmpty) {
      _selectedPointId = null;
      return;
    }
    if (!points.any((point) => point.id == _selectedPointId)) {
      _selectedPointId = points.first.id;
    }
  }

  Widget _filterChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    required IconData icon,
  }) {
    return CompactToggle(
      key: key,
      label: label,
      semanticsLabel: '$label 회화 뉘앙스 범위',
      value: selected,
      selectedIcon: icon,
      unselectedIcon: icon,
      exclusiveSelection: true,
      minimumTapTargetHeight: 48,
      onChanged: (_) => onSelected(),
    );
  }

  void _toggleMastered(ConversationNuancePoint point) {
    final leavesVisibleResults = _masteryFilter == _NuanceMasteryFilter.all;
    widget.controller.toggleGrammarMastered(_persistentId(point));
    if (leavesVisibleResults) return;
    setState(() => _controlsExpanded = false);
    _scrollToTop();
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _reconcileSelection();
    });
    _scrollToTop();
  }

  void _clearQuery() {
    _searchController.clear();
    _setQuery('');
  }

  void _setRegisterFilter(_NuanceRegisterFilter value) {
    setState(() {
      _registerFilter = value;
      _reconcileSelection();
    });
    _scrollToTop();
  }

  void _setMasteryFilter(_NuanceMasteryFilter value) {
    setState(() {
      _masteryFilter = value;
      _reconcileSelection();
    });
    _scrollToTop();
  }

  void _setSort(_NuanceSort value) {
    if (_sort == value) return;
    setState(() {
      _sort = value;
      final points = _points;
      _selectedPointId = points.isEmpty ? null : points.first.id;
    });
    _scrollToTop();
  }

  void _reshuffle() {
    if (_sort != _NuanceSort.random) return;
    setState(() {
      final previousPoints = _points;
      final previousFirst = previousPoints.isEmpty
          ? null
          : previousPoints.first.id;
      for (var attempt = 0; attempt < 128; attempt++) {
        _randomSeed += 1;
        if (_points.length < 2 || _points.first.id != previousFirst) break;
      }
      final points = _points;
      _selectedPointId = points.isEmpty ? null : points.first.id;
    });
    _scrollToTop();
  }

  void _resetViewOptions() {
    _searchController.clear();
    setState(() {
      _query = '';
      _registerFilter = _NuanceRegisterFilter.all;
      _masteryFilter = _NuanceMasteryFilter.all;
      _sort = _NuanceSort.catalog;
      _controlsExpanded = false;
      _selectedPointId = conversationNuanceCatalog.isEmpty
          ? null
          : conversationNuanceCatalog.first.id;
    });
    _scrollToTop();
  }

  void _move(int delta, List<ConversationNuancePoint> points) {
    final nextIndex = _visibleIndex(points) + delta;
    if (nextIndex < 0 || nextIndex >= points.length) return;
    final next = points[nextIndex];
    setState(() {
      _selectedPointId = next.id;
      _controlsExpanded = false;
    });
    widget.controller.recordGrammarStudied(_persistentId(next));
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: AppDurations.standard,
        curve: Curves.easeOutCubic,
      );
    });
  }
}

enum _NuanceRegisterFilter { all, casual, flexible, sensitive }

extension on _NuanceRegisterFilter {
  String get label => switch (this) {
    _NuanceRegisterFilter.all => '전체',
    _NuanceRegisterFilter.casual => '편한 말투',
    _NuanceRegisterFilter.flexible => '일상·정중 가능',
    _NuanceRegisterFilter.sensitive => '말투 주의',
  };

  IconData get icon => switch (this) {
    _NuanceRegisterFilter.all => Icons.forum_rounded,
    _NuanceRegisterFilter.casual => Icons.chat_bubble_rounded,
    _NuanceRegisterFilter.flexible => Icons.record_voice_over_rounded,
    _NuanceRegisterFilter.sensitive => Icons.info_rounded,
  };
}

enum _NuanceMasteryFilter { all, pending, mastered }

extension on _NuanceMasteryFilter {
  String get label => switch (this) {
    _NuanceMasteryFilter.all => '전체',
    _NuanceMasteryFilter.pending => '미완료',
    _NuanceMasteryFilter.mastered => '완료',
  };

  IconData get icon => switch (this) {
    _NuanceMasteryFilter.all => Icons.library_books_rounded,
    _NuanceMasteryFilter.pending => Icons.radio_button_unchecked_rounded,
    _NuanceMasteryFilter.mastered => Icons.check_circle_rounded,
  };
}

enum _NuanceSort { catalog, random }

class _NuanceFilterGroup extends StatelessWidget {
  const _NuanceFilterGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: children,
        ),
      ],
    );
  }
}

class _NuanceResultSummary extends StatelessWidget {
  const _NuanceResultSummary({
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
      key: const ValueKey('conversation-nuance-result-summary'),
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
                  key: const ValueKey('conversation-nuance-result-count'),
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
                  key: const ValueKey('conversation-nuance-position'),
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
                '$masteredCount / $resultCount개 외움',
                key: const ValueKey('conversation-nuance-mastered-count'),
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
            key: const ValueKey('conversation-nuance-progress'),
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

class _NuanceEmptyState extends StatelessWidget {
  const _NuanceEmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('conversation-nuance-deck-empty'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 34,
            color: AppColors.subtleText,
          ),
          const SizedBox(height: 10),
          const Text(
            '조건에 맞는 회화 표현이 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            hasQuery ? '검색어를 지우거나 범위를 바꿔 보세요.' : '다른 말투나 외움 상태를 선택해 보세요.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.subtleText, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _NuanceCard extends StatelessWidget {
  const _NuanceCard({
    super.key,
    required this.point,
    required this.position,
    required this.total,
    required this.mastered,
    required this.linkIndex,
    required this.onOpenWord,
    required this.onToggleMastered,
  });

  final ConversationNuancePoint point;
  final int position;
  final int total;
  final bool mastered;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;
  final VoidCallback onToggleMastered;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _NuanceChip(label: point.registerLabel, emphasized: true),
                    _NuanceChip(label: point.toneLabel),
                    _NuanceChip(label: '$position / $total'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: ValueKey('conversation-nuance-mastered-${point.id}'),
                tooltip: mastered ? '외웠어요 취소' : '외웠어요',
                onPressed: onToggleMastered,
                style: IconButton.styleFrom(
                  backgroundColor: mastered
                      ? AppColors.success.withValues(alpha: 0.14)
                      : AppColors.toggleSurface,
                  foregroundColor: mastered
                      ? AppColors.success
                      : AppColors.subtleText,
                ),
                icon: Icon(
                  mastered ? Icons.check_circle_rounded : Icons.circle_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            point.pattern,
            style: const TextStyle(
              color: AppColors.ink,
              fontFamily: AppFonts.japanese,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            point.shortMeaning,
            style: const TextStyle(
              color: AppColors.reading,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _NuanceInfo(label: '접속', text: point.formation),
          const SizedBox(height: 12),
          _NuanceInfo(label: '느낌', text: point.explanation),
          const SizedBox(height: 12),
          _NuanceInfo(label: '비교', text: point.contrast),
          const SizedBox(height: 12),
          _NuanceInfo(label: '주의', text: point.caution, caution: true),
          const Divider(height: 30),
          for (final indexed in point.examples.indexed) ...[
            _NuanceExampleView(
              key: ValueKey(
                'conversation-nuance-example-${point.id}-${indexed.$1}',
              ),
              pointId: point.id,
              index: indexed.$1,
              example: indexed.$2,
              linkIndex: linkIndex,
              onOpenWord: onOpenWord,
            ),
            if (indexed.$1 != point.examples.length - 1)
              const Divider(height: 28),
          ],
        ],
      ),
    );
  }
}

class _NuanceChip extends StatelessWidget {
  const _NuanceChip({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.ink : AppColors.toggleSurface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: emphasized ? AppColors.moon : AppColors.body,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NuanceInfo extends StatelessWidget {
  const _NuanceInfo({
    required this.label,
    required this.text,
    this.caution = false,
  });

  final String label;
  final String text;
  final bool caution;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              color: caution ? AppColors.reading : AppColors.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w900,
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
    if (!caution) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.toggleSurface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadii.inner),
      ),
      child: Padding(padding: const EdgeInsets.all(10), child: content),
    );
  }
}

class _NuanceExampleView extends StatelessWidget {
  const _NuanceExampleView({
    super.key,
    required this.pointId,
    required this.index,
    required this.example,
    required this.linkIndex,
    required this.onOpenWord,
  });

  final String pointId;
  final int index;
  final ConversationNuanceExample example;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '예문 ${index + 1}',
              style: const TextStyle(
                color: AppColors.reading,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.toggleSurface,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                example.situation,
                style: const TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LinkedAozoraRubyText(
                example.sentenceRuby,
                linkIndex: linkIndex,
                onWordTap: onOpenWord,
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
              key: ValueKey('conversation-nuance-tts-$pointId-$index'),
              text: spokenAozoraRuby(example.sentenceRuby),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          example.translation,
          style: const TextStyle(color: AppColors.body, height: 1.5),
        ),
      ],
    );
  }
}
