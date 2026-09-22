import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import '../widgets/aozora_ruby_text.dart';
import '../widgets/common_widgets.dart';
import '../widgets/japanese_tts_button.dart';
import '../widgets/linked_aozora_ruby_text.dart';
import '../widgets/word_match_candidate_sheet.dart';

/// A persistent flash-card deck built from the demo groups shared by all tabs.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.linkIndex,
    this.active = true,
    this.onOpenLevel,
    this.onStartQuiz,
    this.onOpenWord,
  });

  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final bool active;

  // Kept optional while callers migrate from the previous dashboard API.
  final ValueChanged<JlptLevel>? onOpenLevel;
  final ValueChanged<JlptLevel>? onStartQuiz;
  final ValueChanged<JapaneseWord>? onOpenWord;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _TodayCardMode { word, example }

class _TodayExampleDeckEntry {
  _TodayExampleDeckEntry({required this.word, required this.example})
    : identity = '${word.id}\u001f${example.id}';

  final JapaneseWord word;
  final ExampleSentence example;
  final String identity;
}

class _HomePageState extends State<HomePage> {
  static const _carouselAnchor = 100000;

  int? _flippedVirtualPage;
  String? _lastWordId;
  late PageController _wordPageController;
  late PageController _examplePageController;
  late int _visibleWordVirtualPage;
  late int _visibleExampleVirtualPage;
  late int _lastDeckSeed;
  late List<JapaneseWord> _lastDeckWords;
  late List<_TodayExampleDeckEntry> _exampleDeck;
  bool _listening = false;
  _TodayCardMode _cardMode = _TodayCardMode.word;
  Timer? _knownAdvanceTimer;
  int? _knownAdvanceSeconds;
  String? _pendingKnownWordId;
  List<JapaneseWord>? _pendingWordDeck;
  List<_TodayExampleDeckEntry>? _pendingExampleDeck;
  bool _applyingKnownMutation = false;

  bool get _usingExampleDeck =>
      _cardMode == _TodayCardMode.example && _visibleExampleDeck.isNotEmpty;

  int get _visibleVirtualPage =>
      _usingExampleDeck ? _visibleExampleVirtualPage : _visibleWordVirtualPage;

  PageController get _pageController =>
      _usingExampleDeck ? _examplePageController : _wordPageController;

  bool get _flipped => _flippedVirtualPage == _visibleVirtualPage;

  List<JapaneseWord> get _visibleWordDeck =>
      _pendingWordDeck ?? _controller.todayDeckWords;

  List<_TodayExampleDeckEntry> get _visibleExampleDeck =>
      _pendingExampleDeck ?? _exampleDeck;

  StudyController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _lastWordId = _controller.todayWord?.id;
    _lastDeckSeed = _controller.todayDeckSeed;
    _lastDeckWords = _controller.todayDeckWords;
    _exampleDeck = _buildExampleDeck(_lastDeckWords, seed: _lastDeckSeed);
    _visibleWordVirtualPage = _initialVirtualPage(
      _controller.todayDeckIndex,
      _lastDeckWords.length,
    );
    _visibleExampleVirtualPage = _initialVirtualPage(0, _exampleDeck.length);
    _wordPageController = _createPageController(_visibleWordVirtualPage);
    _examplePageController = _createPageController(_visibleExampleVirtualPage);
    _updateControllerSubscription();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      if (oldWidget.active != widget.active) {
        if (!widget.active) _cancelPendingKnownAdvance();
        _updateControllerSubscription();
        if (widget.active) _refreshAfterActivation();
      }
      return;
    }
    if (_listening) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
    _cancelPendingKnownAdvance();
    final oldWordPageController = _wordPageController;
    final oldExamplePageController = _examplePageController;
    _lastWordId = _controller.todayWord?.id;
    _lastDeckSeed = _controller.todayDeckSeed;
    _lastDeckWords = _controller.todayDeckWords;
    _exampleDeck = _buildExampleDeck(_lastDeckWords, seed: _lastDeckSeed);
    _visibleWordVirtualPage = _initialVirtualPage(
      _controller.todayDeckIndex,
      _lastDeckWords.length,
    );
    _visibleExampleVirtualPage = _initialVirtualPage(0, _exampleDeck.length);
    _wordPageController = _createPageController(_visibleWordVirtualPage);
    _examplePageController = _createPageController(_visibleExampleVirtualPage);
    _updateControllerSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldWordPageController.dispose();
      oldExamplePageController.dispose();
    });
  }

  @override
  void dispose() {
    if (_listening) _controller.removeListener(_handleControllerChanged);
    _knownAdvanceTimer?.cancel();
    _wordPageController.dispose();
    _examplePageController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final wordId = _controller.todayWord?.id;
    final deck = _controller.todayDeckWords;
    final seedChanged = _controller.todayDeckSeed != _lastDeckSeed;
    final deckChanged = seedChanged || !identical(deck, _lastDeckWords);
    if (_pendingKnownWordId != null && deckChanged && !_applyingKnownMutation) {
      _clearPendingKnownAdvanceState();
    }
    // Marking a word as known removes it (and all of its examples) from the
    // controller deck synchronously. While the three-second undo window is
    // visible, however, the PageView is deliberately rendering the snapshot
    // in [_pendingExampleDeck]. Replacing the live example deck here would
    // also recalculate [_visibleExampleVirtualPage] against a shorter list,
    // making the still-visible snapshot card non-interactive. Defer that
    // replacement until the countdown commits so the same on-screen button
    // remains the undo target.
    final deferExampleDeckChange =
        deckChanged &&
        _cardMode == _TodayCardMode.example &&
        _pendingKnownWordId != null &&
        _applyingKnownMutation;
    final shouldSyncPage =
        deck.isNotEmpty &&
        _positiveModulo(_visibleWordVirtualPage, deck.length) !=
            _controller.todayDeckIndex;
    setState(() {
      if (_cardMode == _TodayCardMode.word && wordId != _lastWordId) {
        _flippedVirtualPage = null;
      }
      if (deckChanged && !deferExampleDeckChange) {
        _replaceExampleDeck(deck, resetToStart: seedChanged);
        if (_cardMode == _TodayCardMode.example) {
          _flippedVirtualPage = null;
        }
      }
      _lastWordId = wordId;
      _lastDeckSeed = _controller.todayDeckSeed;
      _lastDeckWords = deck;
    });
    final holdCurrentCard = _pendingKnownWordId != null;
    if (!holdCurrentCard && (deckChanged || shouldSyncPage)) {
      _syncWordPageToController(jump: deckChanged);
    }
    if (deckChanged && !holdCurrentCard) _syncExamplePage();
  }

  void _updateControllerSubscription() {
    if (widget.active && !_listening) {
      _controller.addListener(_handleControllerChanged);
      _listening = true;
    } else if (!widget.active && _listening) {
      _controller.removeListener(_handleControllerChanged);
      _listening = false;
    }
  }

  void _refreshAfterActivation() {
    final wordId = _controller.todayWord?.id;
    final deck = _controller.todayDeckWords;
    final seedChanged = _controller.todayDeckSeed != _lastDeckSeed;
    final deckChanged = seedChanged || !identical(deck, _lastDeckWords);
    if (_cardMode == _TodayCardMode.word && wordId != _lastWordId) {
      _flippedVirtualPage = null;
    }
    if (deckChanged) {
      _replaceExampleDeck(deck, resetToStart: seedChanged);
      if (_cardMode == _TodayCardMode.example) _flippedVirtualPage = null;
    }
    _lastWordId = wordId;
    _lastDeckSeed = _controller.todayDeckSeed;
    _lastDeckWords = deck;
    if (deck.isNotEmpty) _syncWordPageToController(jump: deckChanged);
    if (deckChanged) _syncExamplePage();
  }

  @override
  Widget build(BuildContext context) {
    final deck = _visibleWordDeck;
    final word = deck.isEmpty
        ? null
        : deck[_positiveModulo(_visibleWordVirtualPage, deck.length)];
    if (word == null || deck.isEmpty) {
      final allSelectedWordsKnown =
          _controller.selectedWordListWords.isNotEmpty &&
          _controller.selectedStudyWords.isEmpty;
      return EmptyState(
        key: const ValueKey('today-empty'),
        icon: allSelectedWordsKnown
            ? Icons.workspace_premium_rounded
            : Icons.style_outlined,
        title: allSelectedWordsKnown ? '오늘 볼 단어를 모두 외웠어요' : '표시할 단어가 없어요',
        message: allSelectedWordsKnown
            ? '외운 단어는 오늘 덱에서 빠져요. 단어장이나 상세 화면에서 언제든 해제할 수 있어요.'
            : '상단에서 하나 이상의 데모 묶음을 선택해 보세요.',
      );
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return ColoredBox(
      color: AppColors.paper,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A regular phone has enough room for the complete deck chrome and a
          // useful card without a page-level vertical gesture. Keep scrolling
          // solely as an overflow fallback for genuinely small viewports and
          // accessibility text sizes.
          final useScrollableFallback =
              constraints.maxWidth < 350 ||
              constraints.maxHeight < 590 ||
              textScale > 1.25;

          Widget buildCardPager({required bool allowVerticalScroll}) {
            final showsExamples = _usingExampleDeck;
            final examples = _visibleExampleDeck;
            final activeDeckLength = showsExamples
                ? examples.length
                : deck.length;
            return PageView.builder(
              key: const ValueKey('today-card-page-view'),
              controller: _pageController,
              physics: const PageScrollPhysics(),
              allowImplicitScrolling: true,
              onPageChanged: (virtualPage) =>
                  _handlePageChanged(virtualPage, showsExamples: showsExamples),
              itemBuilder: (context, virtualPage) {
                final logicalIndex = _positiveModulo(
                  virtualPage,
                  activeDeckLength,
                );
                final entry = showsExamples ? examples[logicalIndex] : null;
                final cardWord = entry?.word ?? deck[logicalIndex];
                final example = entry?.example;
                final isCurrent = virtualPage == _visibleVirtualPage;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _FlipCard(
                    key: example == null
                        ? ValueKey('today-card-$virtualPage-${cardWord.id}')
                        : ValueKey(
                            'today-example-card-$virtualPage-${example.id}',
                          ),
                    gestureKey: isCurrent
                        ? const ValueKey('today-flash-card')
                        : ValueKey('today-flash-card-$virtualPage'),
                    word: cardWord,
                    example: example,
                    flipped: _flippedVirtualPage == virtualPage,
                    controller: _controller,
                    linkIndex: widget.linkIndex,
                    interactive: isCurrent,
                    allowVerticalScroll: allowVerticalScroll,
                    onTap: isCurrent ? _toggleCard : () {},
                    onOpenWord: widget.onOpenWord,
                    knownCountdown:
                        _pendingKnownWordId == cardWord.id && isCurrent
                        ? _knownAdvanceSeconds
                        : null,
                    onToggleKnown: () => _toggleKnown(cardWord),
                  ),
                );
              },
            );
          }

          final activeDeckLength = _usingExampleDeck
              ? _visibleExampleDeck.length
              : deck.length;
          final activeVirtualPage = _usingExampleDeck
              ? _visibleExampleVirtualPage
              : _visibleWordVirtualPage;
          List<Widget> deckChrome() => [
            _DeckHeader(
              current: _positiveModulo(activeVirtualPage, activeDeckLength) + 1,
              total: activeDeckLength,
              onShuffle: _shuffle,
            ),
            const SizedBox(height: AppSpacing.sm),
            _TodayCardModeTabs(mode: _cardMode, onChanged: _setCardMode),
            const SizedBox(height: AppSpacing.sm),
            _FrontDisplayControls(controller: _controller),
            const SizedBox(height: AppSpacing.sm),
          ];

          final gestureHint = Text(
            _cardMode == _TodayCardMode.word
                ? '탭: 뜻 보기 · 왼쪽: 다음 · 오른쪽: 이전'
                : '탭: 해석·단어 보기 · 왼쪽: 다음 · 오른쪽: 이전',
            key: const ValueKey('today-gesture-hint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.subtleText,
              fontSize: 11,
              height: 1.35,
            ),
          );

          if (useScrollableFallback) {
            final cardHeight = (constraints.maxHeight - 218).clamp(
              430.0,
              540.0,
            );
            return SingleChildScrollView(
              key: const PageStorageKey<String>('today-scroll-view'),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.lg,
                AppSpacing.screenHorizontal,
                AppSpacing.screenBottom + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...deckChrome(),
                  SizedBox(
                    height: cardHeight,
                    child: buildCardPager(allowVerticalScroll: true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  gestureHint,
                ],
              ),
            );
          }

          return Padding(
            key: const ValueKey('today-fixed-layout'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.lg,
              AppSpacing.screenHorizontal,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...deckChrome(),
                Expanded(child: buildCardPager(allowVerticalScroll: false)),
                const SizedBox(height: AppSpacing.xs),
                gestureHint,
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggleCard() => setState(() {
    _flippedVirtualPage = _flipped ? null : _visibleVirtualPage;
  });

  void _toggleKnown(JapaneseWord word) {
    if (_controller.isKnown(word.id)) {
      final undoingPendingWord = _pendingKnownWordId == word.id;
      final pendingExampleIdentity =
          undoingPendingWord &&
              _cardMode == _TodayCardMode.example &&
              _pendingExampleDeck != null &&
              _pendingExampleDeck!.isNotEmpty
          ? _pendingExampleDeck![_positiveModulo(
                  _visibleExampleVirtualPage,
                  _pendingExampleDeck!.length,
                )]
                .identity
          : null;
      if (undoingPendingWord) _clearPendingKnownAdvanceState();
      _applyingKnownMutation = true;
      try {
        _controller.setKnown(word.id, false);
      } finally {
        _applyingKnownMutation = false;
      }
      if (undoingPendingWord) {
        final restoredWordIndex = _controller.todayDeckWords.indexWhere(
          (candidate) => candidate.id == word.id,
        );
        if (restoredWordIndex >= 0) {
          _controller.setTodayDeckIndex(restoredWordIndex);
        }
        if (pendingExampleIdentity != null) {
          final restoredExampleIndex = _exampleDeck.indexWhere(
            (entry) => entry.identity == pendingExampleIdentity,
          );
          if (restoredExampleIndex >= 0) {
            _visibleExampleVirtualPage = _nearestVirtualPage(
              currentPage: _visibleExampleVirtualPage,
              logicalIndex: restoredExampleIndex,
              deckLength: _exampleDeck.length,
            );
            _syncExamplePage();
          }
        }
      }
      if (undoingPendingWord && mounted) setState(() {});
      return;
    }

    _clearPendingKnownAdvanceState();
    _pendingKnownWordId = word.id;
    _pendingWordDeck = _controller.todayDeckWords;
    _pendingExampleDeck = _exampleDeck;
    _knownAdvanceSeconds = 3;

    _applyingKnownMutation = true;
    try {
      _controller.setKnown(word.id, true);
    } finally {
      _applyingKnownMutation = false;
    }
    if (!mounted) return;
    setState(() {});
    _knownAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _pendingKnownWordId != word.id) {
        timer.cancel();
        return;
      }
      final remaining = _knownAdvanceSeconds ?? 0;
      if (remaining <= 1) {
        timer.cancel();
        setState(() {
          _clearPendingKnownAdvanceState();
          if (_cardMode == _TodayCardMode.example) {
            _replaceExampleDeck(
              _controller.todayDeckWords,
              resetToStart: false,
            );
            _flippedVirtualPage = null;
          }
        });
        if (_cardMode == _TodayCardMode.example) {
          _syncExamplePage();
        } else {
          _syncWordPageToController(jump: true);
        }
        return;
      }
      setState(() => _knownAdvanceSeconds = remaining - 1);
    });
  }

  void _clearPendingKnownAdvanceState() {
    _knownAdvanceTimer?.cancel();
    _knownAdvanceTimer = null;
    _knownAdvanceSeconds = null;
    _pendingKnownWordId = null;
    _pendingWordDeck = null;
    _pendingExampleDeck = null;
  }

  void _cancelPendingKnownAdvance() {
    if (_pendingKnownWordId == null) return;
    final reconcileExampleDeck = _cardMode == _TodayCardMode.example;
    _clearPendingKnownAdvanceState();
    // Cancelling the scheduled advance (by swiping, switching modes, or
    // leaving the page) does not undo the known state. If the live deck update
    // was deferred for the example undo window, reconcile it now so examples
    // belonging to the known word cannot remain in the carousel.
    if (reconcileExampleDeck) {
      _replaceExampleDeck(_controller.todayDeckWords, resetToStart: false);
    }
  }

  void _setCardMode(_TodayCardMode mode) {
    if (_cardMode == mode) return;
    _cancelPendingKnownAdvance();
    setState(() {
      _cardMode = mode;
      _flippedVirtualPage = null;
    });
    if (mode == _TodayCardMode.example) {
      _syncExamplePage();
    } else {
      _syncWordPageToController(jump: true);
    }
  }

  void _shuffle() {
    _cancelPendingKnownAdvance();
    setState(() {
      _flippedVirtualPage = null;
    });
    _controller.shuffleTodayDeck();
  }

  PageController _createPageController(int initialPage) {
    return PageController(
      initialPage: initialPage,
      viewportFraction: 0.94,
      keepPage: false,
    );
  }

  int _initialVirtualPage(int logicalIndex, int deckLength) {
    if (deckLength <= 0) return _carouselAnchor;
    final alignedAnchor =
        _carouselAnchor - _positiveModulo(_carouselAnchor, deckLength);
    return alignedAnchor + logicalIndex;
  }

  void _handlePageChanged(int virtualPage, {required bool showsExamples}) {
    final cancelledKnownAdvance = _pendingKnownWordId != null;
    if (showsExamples && cancelledKnownAdvance) {
      // Preserve the card the user explicitly swiped to when reconciling the
      // deferred example deck. If that card belongs to the newly-known word,
      // _replaceExampleDeck selects the nearest remaining entry instead.
      _visibleExampleVirtualPage = virtualPage;
      _cancelPendingKnownAdvance();
    } else if (cancelledKnownAdvance) {
      _cancelPendingKnownAdvance();
    }
    if (showsExamples) {
      if (_exampleDeck.isEmpty) {
        if (cancelledKnownAdvance) setState(() {});
        return;
      }
      if (!cancelledKnownAdvance) {
        _visibleExampleVirtualPage = virtualPage;
      }
      setState(() {
        _flippedVirtualPage = null;
      });
      if (cancelledKnownAdvance) _syncExamplePage();
      return;
    }
    final deckLength = _controller.todayDeckWords.length;
    if (deckLength == 0) {
      if (cancelledKnownAdvance) setState(() {});
      return;
    }
    // PageView calls this only after the selected page changes. Clear the
    // outgoing card's own back-face state at that point. Its existing tween
    // animates back to the front while the incoming card stays at angle zero.
    // A cancelled short drag never reaches here, so it keeps the back face.
    final hadFlippedCard = _flippedVirtualPage != null;
    _visibleWordVirtualPage = virtualPage;
    if (hadFlippedCard) _flippedVirtualPage = null;
    final logicalIndex = _positiveModulo(virtualPage, deckLength);
    if (logicalIndex == _controller.todayDeckIndex) {
      setState(() {});
      return;
    }
    // setTodayDeckIndex notifies synchronously; the active listener above
    // performs the single rebuild needed for this page transition.
    _controller.setTodayDeckIndex(logicalIndex);
  }

  void _syncWordPageToController({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_wordPageController.hasClients) return;
      final deckLength = _controller.todayDeckWords.length;
      if (deckLength == 0) return;
      final currentPage =
          _wordPageController.page?.round() ?? _visibleWordVirtualPage;
      final targetPage = _nearestVirtualPage(
        currentPage: currentPage,
        logicalIndex: _controller.todayDeckIndex,
        deckLength: deckLength,
      );
      if (targetPage == currentPage) return;
      _visibleWordVirtualPage = targetPage;
      if (jump) {
        _wordPageController.jumpToPage(targetPage);
      } else {
        _wordPageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 330),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _replaceExampleDeck(
    List<JapaneseWord> words, {
    required bool resetToStart,
  }) {
    final previousIdentity = _exampleDeck.isEmpty
        ? null
        : _exampleDeck[_positiveModulo(
                _visibleExampleVirtualPage,
                _exampleDeck.length,
              )]
              .identity;
    final nextDeck = _buildExampleDeck(words, seed: _controller.todayDeckSeed);
    if (nextDeck.isEmpty) {
      _exampleDeck = nextDeck;
      _visibleExampleVirtualPage = _carouselAnchor;
      return;
    }
    var logicalIndex = 0;
    if (!resetToStart && previousIdentity != null) {
      final preservedIndex = nextDeck.indexWhere(
        (entry) => entry.identity == previousIdentity,
      );
      if (preservedIndex >= 0) logicalIndex = preservedIndex;
    }
    _visibleExampleVirtualPage = resetToStart
        ? _initialVirtualPage(logicalIndex, nextDeck.length)
        : _nearestVirtualPage(
            currentPage: _visibleExampleVirtualPage,
            logicalIndex: logicalIndex,
            deckLength: nextDeck.length,
          );
    _exampleDeck = nextDeck;
  }

  void _syncExamplePage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_examplePageController.hasClients) return;
      if (_exampleDeck.isEmpty) return;
      final currentPage =
          _examplePageController.page?.round() ?? _visibleExampleVirtualPage;
      if (currentPage == _visibleExampleVirtualPage) return;
      _examplePageController.jumpToPage(_visibleExampleVirtualPage);
    });
  }
}

class _CardLearningActions extends StatelessWidget {
  const _CardLearningActions({
    required this.word,
    required this.bookmarked,
    required this.known,
    required this.interactive,
    required this.onToggleBookmark,
    required this.onToggleKnown,
    required this.knownCountdown,
  });

  final JapaneseWord word;
  final bool bookmarked;
  final bool known;
  final bool interactive;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleKnown;
  final int? knownCountdown;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !interactive,
      child: ExcludeSemantics(
        excluding: !interactive,
        child: Row(
          key: interactive ? ValueKey('today-card-actions-${word.id}') : null,
          children: [
            Expanded(
              child: _CardActionButton(
                key: interactive
                    ? const ValueKey('today-bookmark-button')
                    : null,
                selected: bookmarked,
                icon: bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: bookmarked ? '북마크 해제' : '북마크',
                semanticsLabel: bookmarked
                    ? '${word.lemma} 북마크 해제'
                    : '${word.lemma} 북마크 설정',
                color: AppColors.bookmark,
                onPressed: onToggleBookmark,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CardActionButton(
                key: interactive ? const ValueKey('today-known-button') : null,
                selected: known,
                icon: known
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                label: knownCountdown == null
                    ? (known ? '외웠어요 해제' : '외웠어요')
                    : '외웠어요 · ${knownCountdown!}초',
                semanticsLabel: known
                    ? '${word.lemma} 외웠어요 해제'
                    : '${word.lemma} 외웠어요로 표시',
                color: AppColors.success,
                onPressed: onToggleKnown,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.color,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: selected,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: selected ? Colors.white : AppColors.onDarkMuted,
            backgroundColor: selected
                ? color
                : Colors.white.withValues(alpha: 0.07),
            side: BorderSide(
              color: selected ? color : Colors.white.withValues(alpha: 0.2),
            ),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
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

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({
    required this.current,
    required this.total,
    required this.onShuffle,
  });

  final int current;
  final int total;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '오늘의 카드 덱',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$current / $total · 범위를 바꾸기 전까지 이 순서가 유지돼요.',
          key: const ValueKey('today-deck-progress'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.subtleText, fontSize: 11),
        ),
      ],
    );

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: AppSpacing.sm),
        IconButton.outlined(
          key: const ValueKey('today-shuffle-button'),
          tooltip: '순서 섞기',
          onPressed: onShuffle,
          icon: const Icon(Icons.shuffle_rounded, size: 19),
        ),
      ],
    );
  }
}

class _TodayCardModeTabs extends StatelessWidget {
  const _TodayCardModeTabs({required this.mode, required this.onChanged});

  final _TodayCardMode mode;
  final ValueChanged<_TodayCardMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('today-card-mode-tabs'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.toggleSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TodayCardModeTab(
              key: const ValueKey('today-card-mode-word'),
              label: '단어',
              icon: Icons.style_rounded,
              selected: mode == _TodayCardMode.word,
              onTap: () => onChanged(_TodayCardMode.word),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _TodayCardModeTab(
              key: const ValueKey('today-card-mode-example'),
              label: '예문',
              icon: Icons.format_quote_rounded,
              selected: mode == _TodayCardMode.example,
              onTap: () => onChanged(_TodayCardMode.example),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCardModeTab extends StatelessWidget {
  const _TodayCardModeTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.body;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 카드',
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.inner),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.inner),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.inner),
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 17),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({
    super.key,
    required this.gestureKey,
    required this.word,
    required this.example,
    required this.flipped,
    required this.controller,
    required this.linkIndex,
    required this.interactive,
    required this.allowVerticalScroll,
    required this.onTap,
    required this.onOpenWord,
    required this.knownCountdown,
    required this.onToggleKnown,
  });

  final Key gestureKey;
  final JapaneseWord word;
  final ExampleSentence? example;
  final bool flipped;
  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final bool interactive;
  final bool allowVerticalScroll;
  final VoidCallback onTap;
  final ValueChanged<JapaneseWord>? onOpenWord;
  final int? knownCountdown;
  final VoidCallback onToggleKnown;

  @override
  Widget build(BuildContext context) {
    final cardExample = example;
    // Keep both expensive ruby/example trees stable while only the transform
    // changes on animation frames. Flutter can then reuse the current face and
    // swap to the other prebuilt face once at the halfway point.
    final Widget front;
    final Widget back;
    if (cardExample == null) {
      front = _CardFront(
        word: word,
        controller: controller,
        interactive: interactive,
        allowVerticalScroll: allowVerticalScroll,
        onOpenWord: onOpenWord,
        knownCountdown: knownCountdown,
        onToggleKnown: onToggleKnown,
      );
      back = _CardBack(
        word: word,
        controller: controller,
        linkIndex: linkIndex,
        interactive: interactive,
        allowVerticalScroll: allowVerticalScroll,
        onOpenWord: onOpenWord,
      );
    } else {
      front = _ExampleCardFront(
        word: word,
        example: cardExample,
        controller: controller,
        interactive: interactive,
        onOpenWord: onOpenWord,
        knownCountdown: knownCountdown,
        onToggleKnown: onToggleKnown,
      );
      back = _ExampleCardBack(
        word: word,
        example: cardExample,
        linkIndex: linkIndex,
        interactive: interactive,
        onOpenWord: onOpenWord,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: cardExample == null
          ? (flipped
                ? '${word.lemma}, 뜻과 학습 정보. 누르면 단어로 돌아갑니다.'
                : '${word.lemma}, 누르면 뜻을 확인합니다.')
          : (flipped
                ? '${cardExample.original}, 해석과 문장 속 단어. 누르면 예문으로 돌아갑니다.'
                : '${cardExample.original}, 누르면 해석과 문장 속 단어를 확인합니다.'),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: flipped ? math.pi : 0),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
        builder: (context, angle, _) {
          final showBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: Transform(
              alignment: Alignment.center,
              transform: showBack
                  ? (Matrix4.identity()..rotateY(math.pi))
                  : Matrix4.identity(),
              child: GestureDetector(
                key: gestureKey,
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: interactive ? onTap : null,
                child: showBack ? back : front,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.word,
    required this.controller,
    required this.interactive,
    required this.allowVerticalScroll,
    required this.onOpenWord,
    required this.knownCountdown,
    required this.onToggleKnown,
  });

  final JapaneseWord word;
  final StudyController controller;
  final bool interactive;
  final bool allowVerticalScroll;
  final ValueChanged<JapaneseWord>? onOpenWord;
  final int? knownCountdown;
  final VoidCallback onToggleKnown;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -44,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.moon.withValues(alpha: 0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.moon,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _CardPartOfSpeechLabel(
                        key: interactive
                            ? ValueKey('today-front-part-of-speech-${word.id}')
                            : null,
                        word: word,
                        dark: true,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final content = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AozoraRubyText(
                              _wordRuby(word),
                              key: interactive
                                  ? ValueKey('today-word-ruby-${word.id}')
                                  : null,
                              showRuby: controller.showTodayFurigana,
                              textAlign: TextAlign.center,
                              baseStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                              rubyStyle: const TextStyle(
                                color: AppColors.moon,
                                fontSize: 13,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                              onTap: interactive
                                  ? () => speakJapaneseWithFeedback(
                                      context,
                                      _wordSpeech(word),
                                      reading: word.reading,
                                      pitchAccent: word
                                          .unambiguousPitchAccentForReading(
                                            word.reading,
                                          ),
                                    )
                                  : null,
                              tapSemanticsLabel: '${word.lemma}, 일본어 발음 듣기',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                IgnorePointer(
                                  ignoring: !interactive,
                                  child: ExcludeSemantics(
                                    excluding: !interactive,
                                    child: JapaneseTtsButton(
                                      key: interactive
                                          ? ValueKey('today-tts-${word.id}')
                                          : null,
                                      text: _wordSpeech(word),
                                      reading: word.reading,
                                      pitchAccent: word
                                          .unambiguousPitchAccentForReading(
                                            word.reading,
                                          ),
                                      tooltip: '${word.lemma} 일본어 발음 듣기',
                                      iconSize: 18,
                                      dark: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                _CardDetailButton(
                                  key: interactive
                                      ? ValueKey(
                                          'today-word-front-detail-${word.id}',
                                        )
                                      : null,
                                  word: word,
                                  interactive: interactive,
                                  onOpenWord: onOpenWord,
                                  dark: true,
                                ),
                              ],
                            ),
                            if (controller.showTodayFrontMeaning) ...[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                word.meanings.join(' · '),
                                key: interactive
                                    ? ValueKey('today-front-meaning-${word.id}')
                                    : null,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.45,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app_rounded,
                                  color: AppColors.moon,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '카드를 눌러 활용형과 예문 보기',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.onDarkMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (allowVerticalScroll) {
                        return SingleChildScrollView(
                          key: interactive
                              ? ValueKey('today-card-front-scroll-${word.id}')
                              : null,
                          child: content,
                        );
                      }
                      return Center(
                        child: FittedBox(
                          key: interactive
                              ? ValueKey('today-card-front-fitted-${word.id}')
                              : null,
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: content,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _CardLearningActions(
                  word: word,
                  bookmarked: controller.isBookmarked(word.id),
                  known: controller.isKnown(word.id),
                  interactive: interactive,
                  onToggleBookmark: () => controller.toggleBookmark(word.id),
                  onToggleKnown: onToggleKnown,
                  knownCountdown: knownCountdown,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleCardFront extends StatelessWidget {
  const _ExampleCardFront({
    required this.word,
    required this.example,
    required this.controller,
    required this.interactive,
    required this.onOpenWord,
    required this.knownCountdown,
    required this.onToggleKnown,
  });

  final JapaneseWord word;
  final ExampleSentence example;
  final StudyController controller;
  final bool interactive;
  final ValueChanged<JapaneseWord>? onOpenWord;
  final int? knownCountdown;
  final VoidCallback onToggleKnown;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -44,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.moon.withValues(alpha: 0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.format_quote_rounded,
                      color: AppColors.moon,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '예문 · ${word.level.label} · ${word.lemma}',
                        key: interactive
                            ? ValueKey('today-example-card-owner-${example.id}')
                            : null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.onDarkMuted,
                          fontFamily: AppFonts.japanese,
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        key: interactive
                            ? ValueKey(
                                'today-example-card-front-scroll-${example.id}',
                              )
                            : null,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0, constraints.maxHeight - 16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AozoraRubyText(
                                _exampleRuby(example),
                                key: interactive
                                    ? ValueKey(
                                        'today-example-card-front-ruby-${example.id}',
                                      )
                                    : null,
                                showRuby: controller.showTodayFurigana,
                                textAlign: TextAlign.center,
                                baseStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  height: 1.42,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                                rubyStyle: const TextStyle(
                                  color: AppColors.moon,
                                  fontSize: 10,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                ),
                                onTap: interactive
                                    ? () => speakJapaneseWithFeedback(
                                        context,
                                        _exampleSpeech(example),
                                      )
                                    : null,
                                tapSemanticsLabel:
                                    '${example.original}, 일본어 예문 발음 듣기',
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  IgnorePointer(
                                    ignoring: !interactive,
                                    child: ExcludeSemantics(
                                      excluding: !interactive,
                                      child: JapaneseTtsButton(
                                        key: interactive
                                            ? ValueKey(
                                                'today-example-card-front-tts-${example.id}',
                                              )
                                            : null,
                                        text: _exampleSpeech(example),
                                        tooltip: '예문 일본어 발음 듣기',
                                        iconSize: 18,
                                        dark: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  _CardDetailButton(
                                    key: interactive
                                        ? ValueKey(
                                            'today-example-front-detail-${example.id}',
                                          )
                                        : null,
                                    word: word,
                                    interactive: interactive,
                                    onOpenWord: onOpenWord,
                                    dark: true,
                                  ),
                                ],
                              ),
                              if (controller.showTodayFrontMeaning) ...[
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  example.naturalTranslation,
                                  key: interactive
                                      ? ValueKey(
                                          'today-example-card-front-meaning-${example.id}',
                                        )
                                      : null,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    height: 1.45,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    color: AppColors.moon,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '카드를 눌러 해석과 문장 속 단어 보기',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.onDarkMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _CardLearningActions(
                  word: word,
                  bookmarked: controller.isBookmarked(word.id),
                  known: controller.isKnown(word.id),
                  interactive: interactive,
                  onToggleBookmark: () => controller.toggleBookmark(word.id),
                  onToggleKnown: onToggleKnown,
                  knownCountdown: knownCountdown,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleCardBack extends StatefulWidget {
  const _ExampleCardBack({
    required this.word,
    required this.example,
    required this.linkIndex,
    required this.interactive,
    required this.onOpenWord,
  });

  final JapaneseWord word;
  final ExampleSentence example;
  final ExampleWordLinkIndex linkIndex;
  final bool interactive;
  final ValueChanged<JapaneseWord>? onOpenWord;

  @override
  State<_ExampleCardBack> createState() => _ExampleCardBackState();
}

class _ExampleCardBackState extends State<_ExampleCardBack> {
  late List<ExampleWordMatch> _wordMatches;

  @override
  void initState() {
    super.initState();
    _wordMatches = _buildWordMatches();
  }

  @override
  void didUpdateWidget(covariant _ExampleCardBack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.id != widget.word.id ||
        oldWidget.example.id != widget.example.id ||
        oldWidget.linkIndex != widget.linkIndex) {
      _wordMatches = _buildWordMatches();
    }
  }

  List<ExampleWordMatch> _buildWordMatches() {
    final matches = widget.linkIndex.match(
      widget.example.original,
      preferredWord: widget.word,
      preferredSurface: widget.example.focusSurface,
    );
    final unique = <ExampleWordMatch>[];
    final seenCandidateSets = <String>{};
    for (final match in matches) {
      final candidateIds =
          (match.candidateWords.isEmpty
                  ? <JapaneseWord>[match.word]
                  : match.candidateWords)
              .map((word) => word.id)
              .toList(growable: false)
            ..sort();
      if (seenCandidateSets.add(candidateIds.join('\u0000'))) {
        unique.add(match);
      }
    }

    final ownerIndex = unique.indexWhere(
      (match) => match.word.id == widget.word.id,
    );
    if (ownerIndex > 0) {
      unique.insert(0, unique.removeAt(ownerIndex));
    } else if (ownerIndex < 0) {
      final surface = widget.example.focusSurface.trim().isEmpty
          ? widget.word.lemma
          : widget.example.focusSurface.trim();
      final foundAt = widget.example.original.indexOf(surface);
      unique.insert(
        0,
        ExampleWordMatch(
          word: widget.word,
          surface: surface,
          start: foundAt < 0 ? 0 : foundAt,
          end: foundAt < 0 ? surface.length : foundAt + surface.length,
          readings: widget.word.readings,
          candidateWords: [widget.word],
        ),
      );
    }
    return List<ExampleWordMatch>.unmodifiable(unique);
  }

  Future<void> _openMatch(ExampleWordMatch match) async {
    final openWord = widget.onOpenWord;
    if (!widget.interactive || openWord == null) return;
    final selected = await showWordMatchCandidateSheet(context, match: match);
    if (selected != null && mounted) openWord(selected);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.interactive;
    final canOpenWords = interactive && widget.onOpenWord != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        child: SingleChildScrollView(
          key: interactive
              ? ValueKey('today-example-card-back-scroll-${widget.example.id}')
              : null,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: canOpenWords
                        ? LinkedAozoraRubyText(
                            _exampleRuby(widget.example),
                            key: ValueKey(
                              'today-example-card-back-ruby-${widget.example.id}',
                            ),
                            linkIndex: widget.linkIndex,
                            preferredWord: widget.word,
                            preferredSurface: widget.example.focusSurface,
                            onWordTap: widget.onOpenWord!,
                            onMatchTap: _openMatch,
                            onUnlinkedTap: () => speakJapaneseWithFeedback(
                              context,
                              _exampleSpeech(widget.example),
                            ),
                            unlinkedTapSemanticsLabel:
                                '${widget.example.original}, 일본어 예문 발음 듣기',
                            showRuby: true,
                            baseStyle: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                            ),
                            rubyStyle: const TextStyle(
                              color: AppColors.reading,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : AozoraRubyText(
                            _exampleRuby(widget.example),
                            showRuby: true,
                            baseStyle: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                            ),
                            rubyStyle: const TextStyle(
                              color: AppColors.reading,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                            onTap: interactive
                                ? () => speakJapaneseWithFeedback(
                                    context,
                                    _exampleSpeech(widget.example),
                                  )
                                : null,
                            tapSemanticsLabel:
                                '${widget.example.original}, 일본어 예문 발음 듣기',
                          ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IgnorePointer(
                    ignoring: !interactive,
                    child: ExcludeSemantics(
                      excluding: !interactive,
                      child: JapaneseTtsButton(
                        key: interactive
                            ? ValueKey(
                                'today-example-card-back-tts-${widget.example.id}',
                              )
                            : null,
                        text: _exampleSpeech(widget.example),
                        tooltip: '예문 일본어 발음 듣기',
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  _CardDetailButton(
                    key: interactive
                        ? ValueKey(
                            'today-example-back-detail-${widget.example.id}',
                          )
                        : null,
                    word: widget.word,
                    interactive: interactive,
                    onOpenWord: widget.onOpenWord,
                    dark: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _BackSectionTitle(
                icon: Icons.translate_rounded,
                title: '해석',
              ),
              const SizedBox(height: AppSpacing.sm),
              _ExampleTranslationPanel(
                key: interactive
                    ? ValueKey(
                        'today-example-card-literal-${widget.example.id}',
                      )
                    : null,
                label: '직역',
                text: widget.example.literalTranslation,
                emphasized: false,
              ),
              const SizedBox(height: AppSpacing.sm),
              _ExampleTranslationPanel(
                key: interactive
                    ? ValueKey(
                        'today-example-card-natural-${widget.example.id}',
                      )
                    : null,
                label: '의역',
                text: widget.example.naturalTranslation,
                emphasized: true,
              ),
              const SizedBox(height: AppSpacing.xxl),
              _BackSectionTitle(
                icon: Icons.menu_book_rounded,
                title: '문장 속 수록 단어',
                action: Text(
                  '${_wordMatches.length}개',
                  key: interactive
                      ? ValueKey(
                          'today-example-card-word-count-${widget.example.id}',
                        )
                      : null,
                  style: const TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                '단어를 누르면 자세히 볼 수 있어요.',
                style: TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final match in _wordMatches)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ExampleWordSummary(
                    key: interactive
                        ? ValueKey(
                            'today-example-card-word-${widget.example.id}-${match.word.id}-${match.start}',
                          )
                        : null,
                    match: match,
                    owner:
                        match.word.id == widget.word.id && !match.isAmbiguous,
                    interactive: canOpenWords,
                    onTap: () => _openMatch(match),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleTranslationPanel extends StatelessWidget {
  const _ExampleTranslationPanel({
    super.key,
    required this.label,
    required this.text,
    required this.emphasized,
  });

  final String label;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.warmSurface : AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              label,
              style: TextStyle(
                color: emphasized ? AppColors.bookmark : AppColors.subtleText,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: emphasized ? AppColors.ink : AppColors.body,
                fontSize: emphasized ? 12 : 11,
                height: 1.45,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleWordSummary extends StatelessWidget {
  const _ExampleWordSummary({
    super.key,
    required this.match,
    required this.owner,
    required this.interactive,
    required this.onTap,
  });

  final ExampleWordMatch match;
  final bool owner;
  final bool interactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final word = match.word;
    final meaning = word.meanings.isEmpty ? '뜻 정보 없음' : word.meanings.first;
    final hasDifferentSurface = match.surface != word.lemma;
    final ambiguous = match.isAmbiguous;
    return ExcludeSemantics(
      excluding: !interactive,
      child: Semantics(
        button: true,
        label: ambiguous
            ? '${match.surface}, 단어 후보 ${match.candidateWords.length}개 보기'
            : '${word.lemma}, ${word.readings.join('·')}, $meaning, 단어 자세히 보기',
        child: Material(
          color: owner
              ? AppColors.moon.withValues(alpha: 0.14)
              : AppColors.softSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            side: BorderSide(
              color: owner
                  ? AppColors.moon.withValues(alpha: 0.75)
                  : AppColors.cardOutline,
            ),
          ),
          child: InkWell(
            onTap: interactive ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AozoraRubyText(
                              _wordRuby(word),
                              showRuby: true,
                              baseStyle: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                              ),
                              rubyStyle: const TextStyle(
                                color: AppColors.reading,
                                fontSize: 7,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasDifferentSurface
                                  ? '문장: ${match.surface} · $meaning'
                                  : meaning,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.body,
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (owner)
                      const _ExampleWordBadge(label: '중심 단어')
                    else if (ambiguous)
                      _ExampleWordBadge(
                        label: '후보 ${match.candidateWords.length}개',
                      ),
                    const SizedBox(width: AppSpacing.xxs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.mutedBlue,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleWordBadge extends StatelessWidget {
  const _ExampleWordBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.body,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CardPartOfSpeechLabel extends StatelessWidget {
  const _CardPartOfSpeechLabel({
    super.key,
    required this.word,
    required this.dark,
  });

  final JapaneseWord word;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(
      word.conjugationClass.isVerb
          ? '${word.partOfSpeech.labelKo} · ${word.conjugationClass.labelKo}'
          : word.partOfSpeech.labelKo,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: dark ? AppColors.onDarkMuted : AppColors.subtleText,
        fontSize: 11,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CardDetailButton extends StatelessWidget {
  const _CardDetailButton({
    super.key,
    required this.word,
    required this.interactive,
    required this.onOpenWord,
    required this.dark,
  });

  final JapaneseWord word;
  final bool interactive;
  final ValueChanged<JapaneseWord>? onOpenWord;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final canOpen = interactive && onOpenWord != null;
    return IgnorePointer(
      ignoring: !interactive,
      child: ExcludeSemantics(
        excluding: !interactive,
        child: IconButton(
          tooltip: '${word.lemma} 자세히 보기',
          onPressed: canOpen ? () => onOpenWord!(word) : null,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: dark ? AppColors.moon : AppColors.mutedBlue,
            backgroundColor: dark
                ? Colors.white.withValues(alpha: 0.09)
                : AppColors.softSurface,
            disabledForegroundColor: dark
                ? AppColors.onDarkMuted
                : AppColors.subtleText,
            disabledBackgroundColor: dark
                ? Colors.white.withValues(alpha: 0.05)
                : AppColors.softSurface,
            side: BorderSide(
              color: dark
                  ? AppColors.moon.withValues(alpha: 0.28)
                  : AppColors.cardOutline,
            ),
            shape: const CircleBorder(),
          ),
          icon: const Icon(Icons.article_outlined, size: 17),
        ),
      ),
    );
  }
}

class _FrontDisplayControls extends StatelessWidget {
  const _FrontDisplayControls({required this.controller});

  final StudyController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('today-front-display-controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '표시 옵션',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            CompactToggle(
              key: const ValueKey('today-show-furigana'),
              label: '후리가나',
              semanticsLabel: '카드 앞면 후리가나 표시',
              value: controller.showTodayFurigana,
              selectedIcon: Icons.text_fields_rounded,
              unselectedIcon: Icons.text_fields_rounded,
              onChanged: controller.setShowTodayFurigana,
            ),
            CompactToggle(
              key: const ValueKey('today-show-meaning'),
              label: '뜻',
              semanticsLabel: '카드 앞면 뜻 표시',
              value: controller.showTodayFrontMeaning,
              selectedIcon: Icons.translate_rounded,
              unselectedIcon: Icons.translate_rounded,
              onChanged: controller.setShowTodayFrontMeaning,
            ),
          ],
        ),
      ],
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.word,
    required this.controller,
    required this.linkIndex,
    required this.interactive,
    required this.allowVerticalScroll,
    required this.onOpenWord,
  });

  final JapaneseWord word;
  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final bool interactive;
  final bool allowVerticalScroll;
  final ValueChanged<JapaneseWord>? onOpenWord;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = SizedBox(
              width: constraints.maxWidth,
              child: Padding(
                padding: allowVerticalScroll
                    ? const EdgeInsets.fromLTRB(22, 20, 22, 24)
                    : const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: _CardBackContent(
                  word: word,
                  controller: controller,
                  linkIndex: linkIndex,
                  interactive: interactive,
                  compact: !allowVerticalScroll,
                  onOpenWord: onOpenWord,
                ),
              ),
            );
            return SingleChildScrollView(
              key: interactive
                  ? ValueKey('today-card-back-scroll-${word.id}')
                  : null,
              child: content,
            );
          },
        ),
      ),
    );
  }
}

class _CardBackContent extends StatefulWidget {
  const _CardBackContent({
    required this.word,
    required this.controller,
    required this.linkIndex,
    required this.interactive,
    required this.compact,
    required this.onOpenWord,
  });

  final JapaneseWord word;
  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final bool interactive;
  final bool compact;
  final ValueChanged<JapaneseWord>? onOpenWord;

  @override
  State<_CardBackContent> createState() => _CardBackContentState();
}

class _CardBackContentState extends State<_CardBackContent> {
  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final interactive = widget.interactive;
    final compact = widget.compact;
    final formsExpanded = widget.controller.showTodayForms;
    final examplesExpanded = widget.controller.showTodayExamples;
    final sectionGap = compact ? AppSpacing.lg : AppSpacing.xxl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: AozoraRubyText(
                      _wordRuby(word),
                      key: interactive
                          ? ValueKey('today-back-word-ruby-${word.id}')
                          : null,
                      showRuby: true,
                      baseStyle: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                      rubyStyle: const TextStyle(
                        color: AppColors.reading,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                      onTap: interactive
                          ? () => speakJapaneseWithFeedback(
                              context,
                              _wordSpeech(word),
                              reading: word.reading,
                              pitchAccent: word
                                  .unambiguousPitchAccentForReading(
                                    word.reading,
                                  ),
                            )
                          : null,
                      tapSemanticsLabel: '${word.lemma}, 일본어 발음 듣기',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IgnorePointer(
                    ignoring: !interactive,
                    child: ExcludeSemantics(
                      excluding: !interactive,
                      child: JapaneseTtsButton(
                        key: interactive
                            ? ValueKey('today-back-tts-${word.id}')
                            : null,
                        text: _wordSpeech(word),
                        reading: word.reading,
                        pitchAccent: word.unambiguousPitchAccentForReading(
                          word.reading,
                        ),
                        tooltip: '${word.lemma} 일본어 발음 듣기',
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  _CardDetailButton(
                    key: interactive
                        ? ValueKey('today-word-back-detail-${word.id}')
                        : null,
                    word: word,
                    interactive: interactive,
                    onOpenWord: widget.onOpenWord,
                    dark: false,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _CardPartOfSpeechLabel(
                key: interactive
                    ? ValueKey('today-back-part-of-speech-${word.id}')
                    : null,
                word: word,
                dark: false,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
        const _BackSectionTitle(icon: Icons.translate_rounded, title: '뜻'),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
        Text(
          word.meanings.join(' · '),
          key: interactive ? ValueKey('today-meaning-${word.id}') : null,
          style: TextStyle(
            color: AppColors.ink,
            fontSize: compact ? 14 : 16,
            height: compact ? 1.3 : 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (word.examples.isNotEmpty) ...[
          SizedBox(height: sectionGap),
          _BackSectionTitle(
            icon: Icons.format_quote_rounded,
            title: '예문',
            onTitleTap: interactive
                ? () =>
                      widget.controller.setShowTodayExamples(!examplesExpanded)
                : null,
            action: IconButton(
              key: interactive
                  ? ValueKey('today-examples-toggle-${word.id}')
                  : null,
              tooltip: examplesExpanded ? '예문 접기' : '예문 펼치기',
              onPressed: interactive
                  ? () => widget.controller.setShowTodayExamples(
                      !examplesExpanded,
                    )
                  : null,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              icon: Icon(
                examplesExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.subtleText,
                size: 20,
              ),
            ),
          ),
          if (examplesExpanded) ...[
            SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
            for (final example in word.examples)
              _TodayExample(
                word: word,
                example: example,
                linkIndex: widget.linkIndex,
                compact: compact,
                interactive: interactive,
                onOpenWord: widget.onOpenWord,
              ),
          ],
        ],
        if (word.forms.isNotEmpty) ...[
          SizedBox(height: sectionGap),
          _BackSectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: '활용형',
            onTitleTap: interactive
                ? () => widget.controller.setShowTodayForms(!formsExpanded)
                : null,
            action: IconButton(
              key: interactive
                  ? ValueKey('today-forms-toggle-${word.id}')
                  : null,
              tooltip: formsExpanded ? '활용형 접기' : '활용형 펼치기',
              onPressed: interactive
                  ? () => widget.controller.setShowTodayForms(!formsExpanded)
                  : null,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              icon: Icon(
                formsExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.subtleText,
                size: 20,
              ),
            ),
          ),
          if (formsExpanded) ...[
            SizedBox(height: compact ? 2 : AppSpacing.xs),
            for (final form in word.forms)
              _FormRow(
                word: word,
                form: form,
                interactive: interactive,
                compact: compact,
              ),
          ],
        ],
      ],
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.word,
    required this.form,
    required this.interactive,
    required this.compact,
  });

  final JapaneseWord word;
  final ConjugationForm form;
  final bool interactive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: interactive
          ? ValueKey('today-form-row-${word.id}-${form.kind.name}')
          : null,
      padding: EdgeInsets.only(bottom: compact ? 2 : AppSpacing.xs),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 11,
          vertical: compact ? 3 : 7,
        ),
        decoration: BoxDecoration(
          color: AppColors.warmSurface,
          borderRadius: BorderRadius.circular(AppRadii.inner),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                form.kind.labelKo,
                style: const TextStyle(
                  color: AppColors.body,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: _FormRuby(
                word: word,
                form: form,
                interactive: interactive,
                compact: compact,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IgnorePointer(
              ignoring: !interactive,
              child: ExcludeSemantics(
                excluding: !interactive,
                child: JapaneseTtsButton(
                  key: interactive
                      ? ValueKey(
                          'today-form-tts-${word.id}-${form.kind.name}-${form.surface}',
                        )
                      : null,
                  text: _formSpeech(form),
                  tooltip: '${form.surface} 일본어 발음 듣기',
                  iconSize: compact ? 14 : 15,
                  constraints: BoxConstraints.tightFor(
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormRuby extends StatelessWidget {
  const _FormRuby({
    required this.word,
    required this.form,
    required this.interactive,
    required this.compact,
  });

  final JapaneseWord word;
  final ConjugationForm form;
  final bool interactive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AozoraRubyText(
      _formRuby(form),
      key: interactive
          ? ValueKey(
              'today-form-ruby-${word.id}-${form.kind.name}-${form.surface}',
            )
          : null,
      showRuby: true,
      textAlign: TextAlign.right,
      baseStyle: TextStyle(
        color: AppColors.ink,
        fontSize: compact ? 11 : 12,
        fontWeight: FontWeight.w800,
      ),
      rubyStyle: TextStyle(
        color: AppColors.reading,
        fontSize: compact ? 7 : 7.5,
        height: 1,
        fontWeight: FontWeight.w700,
      ),
      onTap: interactive
          ? () => speakJapaneseWithFeedback(context, _formSpeech(form))
          : null,
      tapSemanticsLabel: '${form.surface}, 일본어 발음 듣기',
    );
  }
}

class _BackSectionTitle extends StatelessWidget {
  const _BackSectionTitle({
    required this.icon,
    required this.title,
    this.action,
    this.onTitleTap,
  });

  final IconData icon;
  final String title;
  final Widget? action;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.bookmark, size: 17),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            button: onTitleTap != null,
            child: InkWell(
              onTap: onTitleTap,
              borderRadius: BorderRadius.circular(AppRadii.inner),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _TodayExample extends StatelessWidget {
  const _TodayExample({
    required this.word,
    required this.example,
    required this.linkIndex,
    required this.interactive,
    required this.onOpenWord,
    this.compact = false,
  });

  final JapaneseWord word;
  final ExampleSentence example;
  final ExampleWordLinkIndex linkIndex;
  final bool interactive;
  final ValueChanged<JapaneseWord>? onOpenWord;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: interactive ? ValueKey('today-example-${example.id}') : null,
      margin: EdgeInsets.only(bottom: compact ? AppSpacing.xs : AppSpacing.md),
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: interactive && onOpenWord != null
                    ? LinkedAozoraRubyText(
                        example.ruby.trim().isEmpty
                            ? example.original
                            : example.ruby,
                        key: ValueKey('today-example-ruby-${example.id}'),
                        linkIndex: linkIndex,
                        preferredWord: word,
                        preferredSurface: example.focusSurface,
                        onWordTap: onOpenWord!,
                        onUnlinkedTap: () => speakJapaneseWithFeedback(
                          context,
                          _exampleSpeech(example),
                        ),
                        unlinkedTapSemanticsLabel:
                            '${example.original}, 일본어 예문 발음 듣기',
                        showRuby: true,
                        baseStyle: TextStyle(
                          color: AppColors.ink,
                          fontSize: compact ? 12 : 14,
                          height: compact ? 1.3 : 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                        rubyStyle: TextStyle(
                          color: AppColors.reading,
                          fontSize: compact ? 7 : 8,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : AozoraRubyText(
                        example.ruby.trim().isEmpty
                            ? example.original
                            : example.ruby,
                        showRuby: true,
                        baseStyle: TextStyle(
                          color: AppColors.ink,
                          fontSize: compact ? 12 : 14,
                          height: compact ? 1.3 : 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                        rubyStyle: TextStyle(
                          color: AppColors.reading,
                          fontSize: compact ? 7 : 8,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                        onTap: interactive
                            ? () => speakJapaneseWithFeedback(
                                context,
                                _exampleSpeech(example),
                              )
                            : null,
                        tapSemanticsLabel: '${example.original}, 일본어 예문 발음 듣기',
                      ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IgnorePointer(
                ignoring: !interactive,
                child: ExcludeSemantics(
                  excluding: !interactive,
                  child: JapaneseTtsButton(
                    key: interactive
                        ? ValueKey('today-example-tts-${example.id}')
                        : null,
                    text: _exampleSpeech(example),
                    tooltip: '예문 일본어 발음 듣기',
                    iconSize: compact ? 14 : 16,
                    constraints: BoxConstraints.tightFor(
                      width: compact ? 28 : 34,
                      height: compact ? 28 : 34,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
          Text(
            '직역 · ${example.literalTranslation}',
            key: interactive
                ? ValueKey('today-example-literal-${example.id}')
                : null,
            style: TextStyle(
              color: AppColors.body,
              fontSize: compact ? 9.5 : 11,
              height: compact ? 1.3 : 1.45,
            ),
          ),
          SizedBox(height: compact ? 3 : AppSpacing.xs),
          Text(
            '의역 · ${example.naturalTranslation}',
            key: interactive
                ? ValueKey('today-example-natural-${example.id}')
                : null,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: compact ? 10.5 : 12,
              height: compact ? 1.3 : 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _wordRuby(JapaneseWord word) =>
    buildAozoraRubySourceForReadings(word.lemma, word.readings);

String _formRuby(ConjugationForm form) =>
    buildAozoraRubySource(form.surface, form.reading);

String _exampleRuby(ExampleSentence example) =>
    example.ruby.trim().isEmpty ? example.original : example.ruby;

String _wordSpeech(JapaneseWord word) {
  final reading = word.reading.trim().isEmpty ? word.lemma : word.reading;
  return word.speechTextForReading(reading);
}

String _formSpeech(ConjugationForm form) =>
    form.reading.trim().isEmpty ? form.surface : form.reading;

String _exampleSpeech(ExampleSentence example) {
  final ruby = example.ruby.trim();
  return ruby.isEmpty ? example.original : spokenAozoraRuby(ruby);
}

List<_TodayExampleDeckEntry> _buildExampleDeck(
  List<JapaneseWord> words, {
  required int seed,
}) {
  final entries = <_TodayExampleDeckEntry>[
    for (final word in words)
      for (final example in word.examples)
        _TodayExampleDeckEntry(word: word, example: example),
  ];
  final orderByIdentity = <String, int>{
    for (final entry in entries)
      entry.identity: _stableTodayExampleKey(entry.identity, seed),
  };
  entries.sort((left, right) {
    final order = orderByIdentity[left.identity]!.compareTo(
      orderByIdentity[right.identity]!,
    );
    return order != 0 ? order : left.identity.compareTo(right.identity);
  });
  return List<_TodayExampleDeckEntry>.unmodifiable(entries);
}

int _stableTodayExampleKey(String identity, int seed) {
  var hash = 0x811c9dc5 ^ seed;
  for (final rune in identity.runes) {
    hash ^= rune;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

int _positiveModulo(int value, int divisor) {
  if (divisor <= 0) return 0;
  return value % divisor;
}

int _nearestVirtualPage({
  required int currentPage,
  required int logicalIndex,
  required int deckLength,
}) {
  final cycleStart = currentPage - _positiveModulo(currentPage, deckLength);
  final sameCycle = cycleStart + logicalIndex;
  final candidates = <int>[
    sameCycle - deckLength,
    sameCycle,
    sameCycle + deckLength,
  ];
  candidates.sort(
    (left, right) =>
        (left - currentPage).abs().compareTo((right - currentPage).abs()),
  );
  return candidates.first;
}
