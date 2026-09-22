import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../domain/vocabulary.dart';
import '../../domain/word_order.dart';
import '../../theme/app_theme.dart';
import '../widgets/aozora_ruby_text.dart';
import '../widgets/common_widgets.dart';
import '../widgets/japanese_tts_button.dart';

class WordListPage extends StatefulWidget {
  const WordListPage({
    super.key,
    required this.controller,
    required this.onOpenWord,
    this.active = true,
  });

  final StudyController controller;
  final ValueChanged<JapaneseWord> onOpenWord;
  final bool active;

  @override
  State<WordListPage> createState() => _WordListPageState();
}

class _WordListPageState extends State<WordListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _randomSeed = DateTime.now().microsecondsSinceEpoch;
  final Map<String, String> _gojuonKeyByWordId = <String, String>{};
  List<JapaneseWord>? _cachedOrderedSourceWords;
  List<JapaneseWord>? _cachedOrderedWords;
  WordSortOption? _cachedOrderedSort;
  WordSortDirection? _cachedOrderedDirection;
  int? _cachedOrderedSortDataRevision;
  int? _cachedOrderedRandomSeed;
  List<JapaneseWord>? _cachedSourceWords;
  List<JapaneseWord>? _cachedFilteredWords;
  String? _cachedNormalizedQuery;
  WordSortOption? _cachedSort;
  WordSortDirection? _cachedDirection;
  int? _cachedSortDataRevision;
  bool? _cachedBookmarkedOnly;
  bool? _cachedExcludeKnown;
  bool? _cachedKnownOnly;
  int? _cachedSearchScopeMask;
  int? _cachedRandomSeed;
  late _WordListConfiguration _configuration;
  bool _listening = false;

  bool get _filtersActive =>
      widget.controller.wordListBookmarkedOnly ||
      widget.controller.wordListExcludeKnown ||
      widget.controller.wordListKnownOnly;

  @override
  void initState() {
    super.initState();
    _configuration = _WordListConfiguration.from(widget.controller);
    _updateControllerSubscription();
  }

  @override
  void didUpdateWidget(covariant WordListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_listening) {
        oldWidget.controller.removeListener(_handleControllerChanged);
        _listening = false;
      }
      _gojuonKeyByWordId.clear();
      _cachedOrderedSourceWords = null;
      _cachedOrderedWords = null;
      _cachedFilteredWords = null;
      _configuration = _WordListConfiguration.from(widget.controller);
    }
    _updateControllerSubscription();
    if (widget.active && !oldWidget.active) {
      _configuration = _WordListConfiguration.from(widget.controller);
      if (_filtersActive) _cachedFilteredWords = null;
    }
  }

  @override
  void dispose() {
    if (_listening) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLevels = widget.controller.selectedWordLevels;
    final sourceWords = widget.controller.selectedWordListWords;
    final words = _filteredWords(sourceWords);
    final levelKey = JlptLevel.values
        .where(selectedLevels.contains)
        .map((level) => level.name)
        .join('-');

    return CustomScrollView(
      key: ValueKey('word-list-$levelKey'),
      slivers: [
        SliverToBoxAdapter(
          child: _WordListControls(
            searchController: _searchController,
            query: _query,
            sort: widget.controller.wordSort,
            sortDirection: widget.controller.wordSortDirection,
            searchScopes: widget.controller.wordSearchScopes,
            showFurigana: widget.controller.showWordFurigana,
            showMeaning: widget.controller.showWordMeaning,
            showPartOfSpeech: widget.controller.showWordPartOfSpeech,
            bookmarkedOnly: widget.controller.wordListBookmarkedOnly,
            excludeKnown: widget.controller.wordListExcludeKnown,
            knownOnly: widget.controller.wordListKnownOnly,
            onQueryChanged: (value) => setState(() => _query = value),
            onClearQuery: _clearQuery,
            onOpenSearchScopes: _showSearchScopeSheet,
            onSortChanged: _setSort,
            onShowFuriganaChanged: widget.controller.setShowWordFurigana,
            onShowMeaningChanged: widget.controller.setShowWordMeaning,
            onShowPartOfSpeechChanged:
                widget.controller.setShowWordPartOfSpeech,
            onBookmarkedOnlyChanged:
                widget.controller.setWordListBookmarkedOnly,
            onExcludeKnownChanged: widget.controller.setWordListExcludeKnown,
            onKnownOnlyChanged: widget.controller.setWordListKnownOnly,
          ),
        ),
        SliverToBoxAdapter(
          child: _ResultSummary(
            count: words.length,
            total: sourceWords.length,
            query: _query.trim(),
            filtersActive:
                widget.controller.wordListBookmarkedOnly ||
                widget.controller.wordListExcludeKnown ||
                widget.controller.wordListKnownOnly,
          ),
        ),
        if (words.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              key: const ValueKey('word-list-empty'),
              icon: _filtersActive
                  ? Icons.filter_alt_off_rounded
                  : Icons.search_off_rounded,
              title: _filtersActive ? '필터에 맞는 단어가 없어요' : '검색 결과가 없어요',
              message: _filtersActive
                  ? '필터를 해제하거나 다른 데모 묶음을 선택해 보세요.'
                  : '검색어를 지우거나 상단에서 다른 데모 묶음을 선택해 보세요.',
              action: _query.trim().isNotEmpty
                  ? OutlinedButton.icon(
                      key: const ValueKey('clear-word-search'),
                      onPressed: _clearQuery,
                      icon: const Icon(Icons.backspace_outlined),
                      label: const Text('검색어 지우기'),
                    )
                  : _filtersActive
                  ? OutlinedButton.icon(
                      key: const ValueKey('clear-word-filters'),
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text('필터 해제'),
                    )
                  : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.lg,
              AppSpacing.screenHorizontal,
              AppSpacing.screenBottom,
            ),
            sliver: SliverList.separated(
              itemCount: words.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.listGap),
              itemBuilder: (context, index) {
                final word = words[index];
                return _WordCard(
                  key: ValueKey('word-card-${word.id}'),
                  controller: widget.controller,
                  active: widget.active,
                  word: word,
                  showFurigana: widget.controller.showWordFurigana,
                  showMeaning: widget.controller.showWordMeaning,
                  showPartOfSpeech: widget.controller.showWordPartOfSpeech,
                  onOpen: () => widget.onOpenWord(word),
                  onKnownToggle: () {
                    widget.controller.toggleKnown(word.id);
                  },
                  onBookmarkToggle: () {
                    widget.controller.toggleBookmark(word.id);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  void _updateControllerSubscription() {
    if (widget.active && !_listening) {
      widget.controller.addListener(_handleControllerChanged);
      _listening = true;
    } else if (!widget.active && _listening) {
      widget.controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
  }

  void _handleControllerChanged() {
    if (!mounted || !widget.active) return;
    final next = _WordListConfiguration.from(widget.controller);
    final listMembershipMayHaveChanged =
        next.bookmarkedOnly || next.excludeKnown || next.knownOnly;
    if (next == _configuration && !listMembershipMayHaveChanged) return;
    setState(() {
      _configuration = next;
      if (listMembershipMayHaveChanged) _cachedFilteredWords = null;
    });
  }

  List<JapaneseWord> _filteredWords(List<JapaneseWord> sourceWords) {
    final normalizedQuery = normalizeVocabularySearch(_query);
    final sort = widget.controller.wordSort;
    final direction = widget.controller.wordSortDirection;
    final sortDataRevision = _sortDataRevision(sort);
    final bookmarkedOnly = widget.controller.wordListBookmarkedOnly;
    final excludeKnown = widget.controller.wordListExcludeKnown;
    final knownOnly = widget.controller.wordListKnownOnly;
    final searchScopeMask = widget.controller.wordSearchScopeMask;
    final cached = _cachedFilteredWords;
    if (cached != null &&
        identical(sourceWords, _cachedSourceWords) &&
        normalizedQuery == _cachedNormalizedQuery &&
        sort == _cachedSort &&
        direction == _cachedDirection &&
        sortDataRevision == _cachedSortDataRevision &&
        bookmarkedOnly == _cachedBookmarkedOnly &&
        excludeKnown == _cachedExcludeKnown &&
        knownOnly == _cachedKnownOnly &&
        searchScopeMask == _cachedSearchScopeMask &&
        _randomSeed == _cachedRandomSeed) {
      return cached;
    }

    final result =
        _wordsInSortOrder(sourceWords, sort, direction, sortDataRevision)
            .where(
              (word) =>
                  !bookmarkedOnly || widget.controller.isBookmarked(word.id),
            )
            .where(
              (word) => !excludeKnown || !widget.controller.isKnown(word.id),
            )
            .where((word) => !knownOnly || widget.controller.isKnown(word.id))
            .where(
              (word) => word.matchesNormalized(
                normalizedQuery,
                scopeMask: searchScopeMask,
              ),
            )
            .toList(growable: false);
    _cachedSourceWords = sourceWords;
    _cachedFilteredWords = result;
    _cachedNormalizedQuery = normalizedQuery;
    _cachedSort = sort;
    _cachedDirection = direction;
    _cachedSortDataRevision = sortDataRevision;
    _cachedBookmarkedOnly = bookmarkedOnly;
    _cachedExcludeKnown = excludeKnown;
    _cachedKnownOnly = knownOnly;
    _cachedSearchScopeMask = searchScopeMask;
    _cachedRandomSeed = _randomSeed;
    return result;
  }

  List<JapaneseWord> _wordsInSortOrder(
    List<JapaneseWord> sourceWords,
    WordSortOption sort,
    WordSortDirection direction,
    int sortDataRevision,
  ) {
    final cached = _cachedOrderedWords;
    if (cached != null &&
        identical(sourceWords, _cachedOrderedSourceWords) &&
        sort == _cachedOrderedSort &&
        direction == _cachedOrderedDirection &&
        sortDataRevision == _cachedOrderedSortDataRevision &&
        _randomSeed == _cachedOrderedRandomSeed) {
      return cached;
    }

    Map<String, int>? basicOrderByWordId;
    int basicOrder(JapaneseWord left, JapaneseWord right) {
      final orders = basicOrderByWordId ??= <String, int>{
        for (var index = 0; index < sourceWords.length; index++)
          sourceWords[index].id: index,
      };
      final order = (orders[left.id] ?? 0).compareTo(orders[right.id] ?? 0);
      return order != 0 ? order : left.id.compareTo(right.id);
    }

    int directed(int order) =>
        direction == WordSortDirection.ascending ? order : -order;

    int statusTimeOrder(
      JapaneseWord left,
      JapaneseWord right, {
      required int? Function(String id) timestampFor,
      required bool Function(String id) isActive,
    }) {
      final leftTimestamp = timestampFor(left.id);
      final rightTimestamp = timestampFor(right.id);
      if ((leftTimestamp != null) != (rightTimestamp != null)) {
        // Entries recorded by this version always precede legacy/untagged
        // entries, regardless of the selected chronological direction.
        return leftTimestamp != null ? -1 : 1;
      }
      if (leftTimestamp != null && rightTimestamp != null) {
        final timestampOrder = leftTimestamp.compareTo(rightTimestamp);
        return timestampOrder != 0
            ? directed(timestampOrder)
            : basicOrder(left, right);
      }

      final leftLegacyActive = isActive(left.id);
      final rightLegacyActive = isActive(right.id);
      if (leftLegacyActive != rightLegacyActive) {
        // Preserve older true states whose original time is unknowable, while
        // still keeping them ahead of words that never had the state.
        return leftLegacyActive ? -1 : 1;
      }
      return basicOrder(left, right);
    }

    final result = switch (sort) {
      WordSortOption.basic =>
        direction == WordSortDirection.ascending
            ? sourceWords
            : sourceWords.reversed.toList(growable: false),
      WordSortOption.gojuon =>
        [...sourceWords]..sort((left, right) {
          final leftKey = _gojuonKeyByWordId.putIfAbsent(
            left.id,
            () => gojuonSortKey(left.reading),
          );
          final rightKey = _gojuonKeyByWordId.putIfAbsent(
            right.id,
            () => gojuonSortKey(right.reading),
          );
          final readingOrder = leftKey.compareTo(rightKey);
          if (readingOrder != 0) return directed(readingOrder);
          final exactReadingOrder = left.reading.compareTo(right.reading);
          if (exactReadingOrder != 0) return directed(exactReadingOrder);
          final lemmaOrder = left.lemma.compareTo(right.lemma);
          return lemmaOrder != 0
              ? directed(lemmaOrder)
              : basicOrder(left, right);
        }),
      WordSortOption.accuracy =>
        [...sourceWords]..sort((left, right) {
          final leftAttempts = widget.controller.quizAttemptsFor(left.id);
          final rightAttempts = widget.controller.quizAttemptsFor(right.id);
          final leftAttempted = leftAttempts > 0;
          final rightAttempted = rightAttempts > 0;
          if (leftAttempted != rightAttempted) {
            // Unattempted words always follow attempted words, including when
            // low accuracy is requested first.
            return leftAttempted ? -1 : 1;
          }
          if (!leftAttempted) return basicOrder(left, right);

          final leftCorrect = widget.controller.quizCorrectFor(left.id);
          final rightCorrect = widget.controller.quizCorrectFor(right.id);
          final accuracyOrder = (leftCorrect * rightAttempts).compareTo(
            rightCorrect * leftAttempts,
          );
          return accuracyOrder != 0
              ? directed(accuracyOrder)
              : basicOrder(left, right);
        }),
      WordSortOption.bookmarkTime =>
        [...sourceWords]..sort(
          (left, right) => statusTimeOrder(
            left,
            right,
            timestampFor: widget.controller.bookmarkTimestampFor,
            isActive: widget.controller.isBookmarked,
          ),
        ),
      WordSortOption.knownTime =>
        [...sourceWords]..sort(
          (left, right) => statusTimeOrder(
            left,
            right,
            timestampFor: widget.controller.knownTimestampFor,
            isActive: widget.controller.isKnown,
          ),
        ),
      WordSortOption.random => _randomlySorted(sourceWords),
    };
    _cachedOrderedSourceWords = sourceWords;
    _cachedOrderedWords = result;
    _cachedOrderedSort = sort;
    _cachedOrderedDirection = direction;
    _cachedOrderedSortDataRevision = sortDataRevision;
    _cachedOrderedRandomSeed = _randomSeed;
    return result;
  }

  List<JapaneseWord> _randomlySorted(List<JapaneseWord> words) {
    final randomKeyByWordId = <String, int>{
      for (final word in words) word.id: Object.hash(_randomSeed, word.id),
    };
    return [...words]..sort((left, right) {
      final leftKey = randomKeyByWordId[left.id]!;
      final rightKey = randomKeyByWordId[right.id]!;
      final order = leftKey.compareTo(rightKey);
      return order != 0 ? order : left.id.compareTo(right.id);
    });
  }

  void _setSort(WordSortOption value) {
    if (value == WordSortOption.random) {
      var nextSeed = DateTime.now().microsecondsSinceEpoch;
      if (nextSeed == _randomSeed) nextSeed += 1;
      setState(() => _randomSeed = nextSeed);
      widget.controller.setWordSort(value);
      return;
    }
    if (widget.controller.wordSort == value) {
      widget.controller.toggleWordSortDirection();
    } else {
      widget.controller.setWordSort(value);
    }
  }

  void _clearQuery() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _clearFilters() {
    widget.controller.setWordListBookmarkedOnly(false);
    widget.controller.setWordListExcludeKnown(false);
    widget.controller.setWordListKnownOnly(false);
  }

  int _sortDataRevision(WordSortOption sort) => switch (sort) {
    WordSortOption.accuracy => widget.controller.totalQuizAnswers,
    WordSortOption.bookmarkTime ||
    WordSortOption.knownTime => widget.controller.wordStatusRevision,
    _ => 0,
  };

  Future<void> _showSearchScopeSheet() async {
    var selected = Set<VocabularySearchScope>.of(
      widget.controller.wordSearchScopes,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.screenBottom + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '검색 범위',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '하나 이상의 범위를 선택해 주세요.',
                  style: TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final scope in VocabularySearchScope.values)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      side: const BorderSide(color: AppColors.cardOutline),
                    ),
                    child: CheckboxListTile(
                      key: ValueKey('word-search-scope-${scope.name}'),
                      value: selected.contains(scope),
                      onChanged:
                          selected.length == 1 && selected.contains(scope)
                          ? null
                          : (value) {
                              setSheetState(() {
                                if (value ?? false) {
                                  selected.add(scope);
                                } else {
                                  selected.remove(scope);
                                }
                              });
                            },
                      title: Text(scope.labelKo),
                      subtitle: Text(_searchScopeDescription(scope)),
                      secondary: Icon(_searchScopeIcon(scope)),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('apply-word-search-scopes'),
                  onPressed: () {
                    final next = Set<VocabularySearchScope>.of(selected);
                    Navigator.of(sheetContext).pop();
                    widget.controller.setWordSearchScopes(next);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text('${_searchScopeSummary(selected)} 범위 적용'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordListConfiguration {
  const _WordListConfiguration({
    required this.levelMask,
    required this.sort,
    required this.sortDirection,
    required this.sortDataRevision,
    required this.searchScopeMask,
    required this.showFurigana,
    required this.showMeaning,
    required this.showPartOfSpeech,
    required this.bookmarkedOnly,
    required this.excludeKnown,
    required this.knownOnly,
  });

  factory _WordListConfiguration.from(StudyController controller) {
    var levelMask = 0;
    for (final level in controller.selectedWordLevels) {
      levelMask |= 1 << level.index;
    }
    return _WordListConfiguration(
      levelMask: levelMask,
      sort: controller.wordSort,
      sortDirection: controller.wordSortDirection,
      sortDataRevision: switch (controller.wordSort) {
        WordSortOption.accuracy => controller.totalQuizAnswers,
        WordSortOption.bookmarkTime ||
        WordSortOption.knownTime => controller.wordStatusRevision,
        _ => 0,
      },
      searchScopeMask: controller.wordSearchScopeMask,
      showFurigana: controller.showWordFurigana,
      showMeaning: controller.showWordMeaning,
      showPartOfSpeech: controller.showWordPartOfSpeech,
      bookmarkedOnly: controller.wordListBookmarkedOnly,
      excludeKnown: controller.wordListExcludeKnown,
      knownOnly: controller.wordListKnownOnly,
    );
  }

  final int levelMask;
  final WordSortOption sort;
  final WordSortDirection sortDirection;
  final int sortDataRevision;
  final int searchScopeMask;
  final bool showFurigana;
  final bool showMeaning;
  final bool showPartOfSpeech;
  final bool bookmarkedOnly;
  final bool excludeKnown;
  final bool knownOnly;

  @override
  bool operator ==(Object other) =>
      other is _WordListConfiguration &&
      other.levelMask == levelMask &&
      other.sort == sort &&
      other.sortDirection == sortDirection &&
      other.sortDataRevision == sortDataRevision &&
      other.searchScopeMask == searchScopeMask &&
      other.showFurigana == showFurigana &&
      other.showMeaning == showMeaning &&
      other.showPartOfSpeech == showPartOfSpeech &&
      other.bookmarkedOnly == bookmarkedOnly &&
      other.excludeKnown == excludeKnown &&
      other.knownOnly == knownOnly;

  @override
  int get hashCode => Object.hash(
    levelMask,
    sort,
    sortDirection,
    sortDataRevision,
    searchScopeMask,
    showFurigana,
    showMeaning,
    showPartOfSpeech,
    bookmarkedOnly,
    excludeKnown,
    knownOnly,
  );
}

class _WordListControls extends StatelessWidget {
  const _WordListControls({
    required this.searchController,
    required this.query,
    required this.sort,
    required this.sortDirection,
    required this.searchScopes,
    required this.showFurigana,
    required this.showMeaning,
    required this.showPartOfSpeech,
    required this.bookmarkedOnly,
    required this.excludeKnown,
    required this.knownOnly,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onOpenSearchScopes,
    required this.onSortChanged,
    required this.onShowFuriganaChanged,
    required this.onShowMeaningChanged,
    required this.onShowPartOfSpeechChanged,
    required this.onBookmarkedOnlyChanged,
    required this.onExcludeKnownChanged,
    required this.onKnownOnlyChanged,
  });

  final TextEditingController searchController;
  final String query;
  final WordSortOption sort;
  final WordSortDirection sortDirection;
  final Set<VocabularySearchScope> searchScopes;
  final bool showFurigana;
  final bool showMeaning;
  final bool showPartOfSpeech;
  final bool bookmarkedOnly;
  final bool excludeKnown;
  final bool knownOnly;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onOpenSearchScopes;
  final ValueChanged<WordSortOption> onSortChanged;
  final ValueChanged<bool> onShowFuriganaChanged;
  final ValueChanged<bool> onShowMeaningChanged;
  final ValueChanged<bool> onShowPartOfSpeechChanged;
  final ValueChanged<bool> onBookmarkedOnlyChanged;
  final ValueChanged<bool> onExcludeKnownChanged;
  final ValueChanged<bool> onKnownOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('word-search-field'),
                  controller: searchController,
                  onChanged: onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '단어·읽기·뜻·예문 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '검색어 지우기',
                            onPressed: onClearQuery,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                button: true,
                label: '검색 범위, ${_searchScopeSummary(searchScopes)}',
                child: IconButton.outlined(
                  key: const ValueKey('word-search-scope-button'),
                  tooltip: '검색 범위 선택',
                  onPressed: onOpenSearchScopes,
                  icon: const Icon(Icons.manage_search_rounded),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.outline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 14,
                color: AppColors.mutedBlue,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '검색 범위 · ${_searchScopeSummary(searchScopes)}',
                  key: const ValueKey('word-search-scope-summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _ControlTitle(title: '단어 옵션'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CompactToggle(
                key: const ValueKey('word-sort-basic'),
                label: _orderedSortLabel(
                  '기본순',
                  selected: sort == WordSortOption.basic,
                  direction: sortDirection,
                ),
                semanticsLabel: _orderedSortSemantics(
                  '기본순',
                  selected: sort == WordSortOption.basic,
                  direction: sortDirection,
                ),
                value: sort == WordSortOption.basic,
                selectedIcon: _sortDirectionIcon(sortDirection),
                unselectedIcon: Icons.format_list_numbered_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.basic),
              ),
              CompactToggle(
                key: const ValueKey('word-sort-gojuon'),
                label: _orderedSortLabel(
                  '오십음순',
                  selected: sort == WordSortOption.gojuon,
                  direction: sortDirection,
                ),
                semanticsLabel: _orderedSortSemantics(
                  '오십음순',
                  selected: sort == WordSortOption.gojuon,
                  direction: sortDirection,
                ),
                value: sort == WordSortOption.gojuon,
                selectedIcon: _sortDirectionIcon(sortDirection),
                unselectedIcon: Icons.sort_by_alpha_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.gojuon),
              ),
              CompactToggle(
                key: const ValueKey('word-sort-accuracy'),
                label: _orderedSortLabel(
                  '정답률순',
                  selected: sort == WordSortOption.accuracy,
                  direction: sortDirection,
                ),
                semanticsLabel: _orderedSortSemantics(
                  '정답률순',
                  selected: sort == WordSortOption.accuracy,
                  direction: sortDirection,
                ),
                value: sort == WordSortOption.accuracy,
                selectedIcon: _sortDirectionIcon(sortDirection),
                unselectedIcon: Icons.query_stats_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.accuracy),
              ),
              CompactToggle(
                key: const ValueKey('word-sort-bookmark-time'),
                label: _orderedTimeSortLabel(
                  '북마크순',
                  selected: sort == WordSortOption.bookmarkTime,
                  direction: sortDirection,
                ),
                semanticsLabel: _orderedTimeSortSemantics(
                  '북마크순',
                  selected: sort == WordSortOption.bookmarkTime,
                  direction: sortDirection,
                ),
                value: sort == WordSortOption.bookmarkTime,
                selectedIcon: _sortDirectionIcon(sortDirection),
                unselectedIcon: Icons.bookmark_added_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.bookmarkTime),
              ),
              CompactToggle(
                key: const ValueKey('word-sort-known-time'),
                label: _orderedTimeSortLabel(
                  '외운순',
                  selected: sort == WordSortOption.knownTime,
                  direction: sortDirection,
                ),
                semanticsLabel: _orderedTimeSortSemantics(
                  '외운순',
                  selected: sort == WordSortOption.knownTime,
                  direction: sortDirection,
                ),
                value: sort == WordSortOption.knownTime,
                selectedIcon: _sortDirectionIcon(sortDirection),
                unselectedIcon: Icons.task_alt_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.knownTime),
              ),
              CompactToggle(
                key: const ValueKey('word-sort-random'),
                label: sort == WordSortOption.random ? '랜덤 · 다시 섞기' : '랜덤',
                semanticsLabel: sort == WordSortOption.random
                    ? '랜덤 정렬 사용 중. 다시 누르면 순서를 다시 섞습니다.'
                    : '랜덤 정렬',
                value: sort == WordSortOption.random,
                selectedIcon: Icons.shuffle_rounded,
                unselectedIcon: Icons.shuffle_rounded,
                onChanged: (_) => onSortChanged(WordSortOption.random),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _SortStatus(sort: sort, direction: sortDirection),
          const SizedBox(height: AppSpacing.xl),
          const _ControlTitle(title: '필터'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CompactToggle(
                key: const ValueKey('word-filter-bookmarked-only'),
                label: '북마크만',
                semanticsLabel: '북마크한 단어만 표시',
                value: bookmarkedOnly,
                selectedIcon: Icons.bookmark_rounded,
                unselectedIcon: Icons.bookmark_border_rounded,
                onChanged: onBookmarkedOnlyChanged,
              ),
              CompactToggle(
                key: const ValueKey('word-filter-known-only'),
                label: '외운 단어만',
                semanticsLabel: '외운 단어만 표시',
                value: knownOnly,
                selectedIcon: Icons.check_circle_rounded,
                unselectedIcon: Icons.check_circle_outline_rounded,
                onChanged: onKnownOnlyChanged,
              ),
              CompactToggle(
                key: const ValueKey('word-filter-exclude-known'),
                label: '외운 단어 제외',
                semanticsLabel: '외운 단어 제외',
                value: excludeKnown,
                selectedIcon: Icons.visibility_off_rounded,
                unselectedIcon: Icons.visibility_outlined,
                onChanged: onExcludeKnownChanged,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _ControlTitle(title: '표시 옵션'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CompactToggle(
                key: const ValueKey('word-show-furigana'),
                label: '후리가나',
                semanticsLabel: '후리가나 표시',
                value: showFurigana,
                selectedIcon: Icons.text_fields_rounded,
                unselectedIcon: Icons.text_fields_rounded,
                onChanged: onShowFuriganaChanged,
              ),
              CompactToggle(
                key: const ValueKey('word-show-meaning'),
                label: '뜻',
                semanticsLabel: '뜻 표시',
                value: showMeaning,
                selectedIcon: Icons.translate_rounded,
                unselectedIcon: Icons.translate_rounded,
                onChanged: onShowMeaningChanged,
              ),
              CompactToggle(
                key: const ValueKey('word-show-part-of-speech'),
                label: '품사',
                semanticsLabel: '품사 표시',
                value: showPartOfSpeech,
                selectedIcon: Icons.category_rounded,
                unselectedIcon: Icons.category_outlined,
                onChanged: onShowPartOfSpeechChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _searchScopeSummary(Iterable<VocabularySearchScope> scopes) {
  final selected = scopes.toSet();
  if (selected.length == VocabularySearchScope.values.length) return '전체';
  return VocabularySearchScope.values
      .where(selected.contains)
      .map((scope) => scope.labelKo)
      .join(' · ');
}

String _searchScopeDescription(VocabularySearchScope scope) => switch (scope) {
  VocabularySearchScope.lemma => '표제어·대체 표기·활용 표기',
  VocabularySearchScope.reading => '기본 읽기·활용 읽기',
  VocabularySearchScope.meaning => '한국어 뜻·관련 뜻 메모',
  VocabularySearchScope.example => '일본어 예문·후리가나·직역·의역',
};

IconData _searchScopeIcon(VocabularySearchScope scope) => switch (scope) {
  VocabularySearchScope.lemma => Icons.translate_rounded,
  VocabularySearchScope.reading => Icons.text_fields_rounded,
  VocabularySearchScope.meaning => Icons.notes_rounded,
  VocabularySearchScope.example => Icons.format_quote_rounded,
};

class _SortStatus extends StatelessWidget {
  const _SortStatus({required this.sort, required this.direction});

  final WordSortOption sort;
  final WordSortDirection direction;

  @override
  Widget build(BuildContext context) {
    final random = sort == WordSortOption.random;
    final timeBased =
        sort == WordSortOption.bookmarkTime || sort == WordSortOption.knownTime;
    final sortLabel = switch (sort) {
      WordSortOption.basic => '기본순',
      WordSortOption.gojuon => '오십음순',
      WordSortOption.accuracy => '정답률순',
      WordSortOption.bookmarkTime => '북마크순',
      WordSortOption.knownTime => '외운순',
      WordSortOption.random => '랜덤',
    };
    final directionLabel = timeBased
        ? _timeSortDirectionLabel(direction)
        : _sortDirectionLabel(direction);
    final text = random
        ? '현재 정렬 · 랜덤 · 다시 누르면 재섞기'
        : '현재 정렬 · $sortLabel · $directionLabel';
    return Semantics(
      key: const ValueKey('word-sort-direction-status'),
      liveRegion: true,
      label: random
          ? '현재 랜덤 정렬. 랜덤을 다시 누르면 순서를 다시 섞습니다.'
          : '현재 $sortLabel $directionLabel 정렬',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              random ? Icons.shuffle_rounded : _sortDirectionIcon(direction),
              size: 15,
              color: AppColors.mutedBlue,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 10,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _orderedSortLabel(
  String label, {
  required bool selected,
  required WordSortDirection direction,
}) => selected ? '$label · ${_sortDirectionLabel(direction)}' : label;

String _orderedSortSemantics(
  String label, {
  required bool selected,
  required WordSortDirection direction,
}) {
  if (!selected) return '$label 정렬. 선택하면 오름차순으로 정렬합니다.';
  final next = direction == WordSortDirection.ascending
      ? WordSortDirection.descending
      : WordSortDirection.ascending;
  return '$label 정렬 사용 중, ${_sortDirectionLabel(direction)}. '
      '다시 누르면 ${_sortDirectionLabel(next)}으로 바뀌니다.';
}

String _orderedTimeSortLabel(
  String label, {
  required bool selected,
  required WordSortDirection direction,
}) => selected ? '$label · ${_timeSortDirectionLabel(direction)}' : label;

String _orderedTimeSortSemantics(
  String label, {
  required bool selected,
  required WordSortDirection direction,
}) {
  if (!selected) return '$label 정렬. 선택하면 최신순으로 정렬합니다.';
  final next = direction == WordSortDirection.ascending
      ? WordSortDirection.descending
      : WordSortDirection.ascending;
  return '$label 정렬 사용 중, ${_timeSortDirectionLabel(direction)}. '
      '다시 누르면 ${_timeSortDirectionLabel(next)}으로 바뀝니다.';
}

String _sortDirectionLabel(WordSortDirection direction) =>
    direction == WordSortDirection.ascending ? '오름차순' : '내림차순';

String _timeSortDirectionLabel(WordSortDirection direction) =>
    direction == WordSortDirection.ascending ? '오래된순' : '최신순';

IconData _sortDirectionIcon(WordSortDirection direction) =>
    direction == WordSortDirection.ascending
    ? Icons.arrow_upward_rounded
    : Icons.arrow_downward_rounded;

class _ControlTitle extends StatelessWidget {
  const _ControlTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.count,
    required this.total,
    required this.query,
    required this.filtersActive,
  });

  final int count;
  final int total;
  final String query;
  final bool filtersActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Text(
        query.isNotEmpty
            ? '“$query” 검색 결과 $count개 · 전체 $total개'
            : filtersActive
            ? '필터 결과 $count개 · 전체 $total개'
            : '단어 $count개',
        key: const ValueKey('word-result-summary'),
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WordCard extends StatefulWidget {
  const _WordCard({
    super.key,
    required this.controller,
    required this.active,
    required this.word,
    required this.showFurigana,
    required this.showMeaning,
    required this.showPartOfSpeech,
    required this.onOpen,
    required this.onKnownToggle,
    required this.onBookmarkToggle,
  });

  final StudyController controller;
  final bool active;
  final JapaneseWord word;
  final bool showFurigana;
  final bool showMeaning;
  final bool showPartOfSpeech;
  final VoidCallback onOpen;
  final VoidCallback onKnownToggle;
  final VoidCallback onBookmarkToggle;

  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard> {
  late bool _bookmarked;
  late bool _known;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _readStatus();
    _updateControllerSubscription();
  }

  @override
  void didUpdateWidget(covariant _WordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_listening) {
        oldWidget.controller.removeListener(_handleControllerChanged);
        _listening = false;
      }
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.word.id != widget.word.id ||
        (!oldWidget.active && widget.active)) {
      _readStatus();
    }
    _updateControllerSubscription();
  }

  @override
  void dispose() {
    if (_listening) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    super.dispose();
  }

  void _readStatus() {
    _bookmarked = widget.controller.isBookmarked(widget.word.id);
    _known = widget.controller.isKnown(widget.word.id);
  }

  void _updateControllerSubscription() {
    if (widget.active && !_listening) {
      widget.controller.addListener(_handleControllerChanged);
      _listening = true;
    } else if (!widget.active && _listening) {
      widget.controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
  }

  void _handleControllerChanged() {
    if (!mounted || !widget.active) return;
    final bookmarked = widget.controller.isBookmarked(widget.word.id);
    final known = widget.controller.isKnown(widget.word.id);
    if (bookmarked == _bookmarked && known == _known) return;
    setState(() {
      _bookmarked = bookmarked;
      _known = known;
    });
  }

  @override
  Widget build(BuildContext context) {
    final semanticsParts = <String>[
      widget.word.lemma,
      if (widget.showFurigana && widget.word.reading != widget.word.lemma)
        widget.word.readings.join(', '),
      if (widget.showMeaning) widget.word.meanings.join(', '),
      if (widget.showPartOfSpeech) widget.word.partOfSpeech.labelKo,
      if (widget.showPartOfSpeech && widget.word.conjugationClass.isVerb)
        widget.word.conjugationClass.labelKo,
      if (_known) '외웠어요',
      '상세 보기',
    ];
    return Semantics(
      button: true,
      label: semanticsParts.join(', '),
      onTap: widget.onOpen,
      explicitChildNodes: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.cardOutline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: AozoraRubyText(
                              _wordRubySource(widget.word),
                              key: ValueKey('word-ruby-${widget.word.id}'),
                              showRuby: widget.showFurigana,
                              baseStyle: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 21,
                                height: 1.3,
                                fontWeight: FontWeight.w800,
                              ),
                              rubyStyle: const TextStyle(
                                color: AppColors.reading,
                                fontSize: 10,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                              onTap: () => speakJapaneseWithFeedback(
                                context,
                                _wordSpeech(widget.word),
                                reading: widget.word.reading,
                                pitchAccent: widget.word
                                    .unambiguousPitchAccentForReading(
                                      widget.word.reading,
                                    ),
                              ),
                              tapSemanticsLabel:
                                  '${widget.word.lemma}, 일본어 발음 듣기',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          JapaneseTtsButton(
                            key: ValueKey('word-list-tts-${widget.word.id}'),
                            text: _wordSpeech(widget.word),
                            reading: widget.word.reading,
                            pitchAccent: widget.word
                                .unambiguousPitchAccentForReading(
                                  widget.word.reading,
                                ),
                            tooltip: '${widget.word.lemma} 일본어 발음 듣기',
                            iconSize: 18,
                            constraints: const BoxConstraints.tightFor(
                              width: 42,
                              height: 42,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('known-${widget.word.id}'),
                      tooltip: _known ? '외웠어요 해제' : '외웠어요',
                      onPressed: widget.onKnownToggle,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: Icon(
                        _known
                            ? Icons.check_circle_rounded
                            : Icons.check_circle_outline_rounded,
                        color: _known ? AppColors.success : AppColors.mutedBlue,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('bookmark-${widget.word.id}'),
                      tooltip: _bookmarked ? '북마크 해제' : '북마크',
                      onPressed: widget.onBookmarkToggle,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: Icon(
                        _bookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: _bookmarked
                            ? AppColors.bookmark
                            : AppColors.mutedBlue,
                      ),
                    ),
                  ],
                ),
                if (widget.showMeaning) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    widget.word.meanings.join(' · '),
                    key: ValueKey('word-meaning-${widget.word.id}'),
                    style: const TextStyle(
                      color: Color(0xFF4D586A),
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (widget.showPartOfSpeech || _known) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.showPartOfSpeech)
                        _WordBadge(
                          key: ValueKey(
                            'word-part-of-speech-${widget.word.id}',
                          ),
                          label: widget.word.partOfSpeech.labelKo,
                        ),
                      if (widget.showPartOfSpeech &&
                          widget.word.conjugationClass.isVerb)
                        _WordBadge(
                          key: ValueKey(
                            'word-conjugation-class-${widget.word.id}',
                          ),
                          label: widget.word.conjugationClass.labelKo,
                        ),
                      if (_known)
                        _WordBadge(
                          key: ValueKey('known-word-badge-${widget.word.id}'),
                          label: '외웠어요',
                          icon: Icons.check_circle_rounded,
                          highlighted: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordBadge extends StatelessWidget {
  const _WordBadge({
    super.key,
    required this.label,
    this.icon,
    this.highlighted = false,
  });

  final String label;
  final IconData? icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final foreground = highlighted ? AppColors.successText : AppColors.body;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.successContainer : AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _wordRubySource(JapaneseWord word) {
  return buildAozoraRubySourceForReadings(word.lemma, word.readings);
}

String _wordSpeech(JapaneseWord word) {
  final reading = word.reading.trim().isEmpty ? word.lemma : word.reading;
  return word.speechTextForReading(reading);
}
