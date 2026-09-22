import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import 'aozora_ruby_text.dart';
import 'common_widgets.dart';
import 'japanese_tts_button.dart';
import 'linked_aozora_ruby_text.dart';

Future<void> showWordDetailPage(
  BuildContext context, {
  required JapaneseWord word,
  required StudyController controller,
  ExampleWordLinkIndex? linkIndex,
  bool revealExamplesOnOpen = false,
}) {
  final resolvedLinkIndex = linkIndex ?? ExampleWordLinkIndex(controller.words);
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: '/word/${word.id}'),
      builder: (context) => _WordDetailSessionPage(
        initialWord: word,
        controller: controller,
        linkIndex: resolvedLinkIndex,
        revealExamplesOnOpen: revealExamplesOnOpen,
      ),
    ),
  );
}

class _WordDetailSessionPage extends StatefulWidget {
  const _WordDetailSessionPage({
    required this.initialWord,
    required this.controller,
    required this.linkIndex,
    required this.revealExamplesOnOpen,
  });

  final JapaneseWord initialWord;
  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final bool revealExamplesOnOpen;

  @override
  State<_WordDetailSessionPage> createState() => _WordDetailSessionPageState();
}

class _WordDetailSessionPageState extends State<_WordDetailSessionPage> {
  final ScrollController _breadcrumbController = ScrollController();
  final List<_WordDetailHistoryEntry> _history = [];
  var _historyIndex = 0;
  var _nextSerial = 0;

  _WordDetailHistoryEntry get _current => _history[_historyIndex];

  bool get _canGoBack => _historyIndex > 0;

  bool get _canGoForward => _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _history.add(_entryFor(widget.initialWord));
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  _WordDetailHistoryEntry _entryFor(JapaneseWord word) {
    return _WordDetailHistoryEntry(
      word: word,
      serial: _nextSerial++,
      chipKey: GlobalKey(),
    );
  }

  void _openWord(JapaneseWord word) {
    if (word.id == _current.word.id) return;
    setState(() {
      if (_canGoForward) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(_entryFor(word));
      _historyIndex = _history.length - 1;
    });
    _revealCurrentChip();
  }

  void _goBackOrClose() {
    if (_canGoBack) {
      _navigateTo(_historyIndex - 1);
      return;
    }
    _close();
  }

  void _goForward() {
    if (!_canGoForward) return;
    _navigateTo(_historyIndex + 1);
  }

  void _navigateTo(int index) {
    if (index < 0 || index >= _history.length || index == _historyIndex) return;
    setState(() => _historyIndex = index);
    _revealCurrentChip();
  }

  void _revealCurrentChip() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _current.chipKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: AppDurations.standard,
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PopScope<void>(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBackOrClose();
      },
      child: Scaffold(
        key: const ValueKey('word-detail-session'),
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          leadingWidth: 96,
          leading: Row(
            children: [
              IconButton(
                key: const ValueKey('word-detail-history-back'),
                tooltip: _canGoBack ? '이전 단어' : '자세히 보기 닫기',
                onPressed: _goBackOrClose,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                key: const ValueKey('word-detail-history-forward'),
                tooltip: '다음 단어',
                onPressed: _canGoForward ? _goForward : null,
                style: IconButton.styleFrom(
                  disabledForegroundColor: AppColors.onDarkMuted,
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          titleSpacing: 0,
          title: SingleChildScrollView(
            key: const ValueKey('word-detail-breadcrumb-scroll'),
            controller: _breadcrumbController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < _history.length; index++) ...[
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.onDarkMuted,
                      ),
                    ),
                  _WordHistoryChip(
                    key: _history[index].chipKey,
                    entry: _history[index],
                    selected: index == _historyIndex,
                    onPressed: () => _navigateTo(index),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            IconButton(
              key: const ValueKey('word-detail-close'),
              tooltip: '자세히 보기 닫기',
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: KeyedSubtree(
          key: ValueKey('word-detail-page-${current.word.id}'),
          child: _WordDetailContent(
            key: ValueKey(
              'word-detail-content-${current.serial}-${current.word.id}',
            ),
            word: current.word,
            controller: widget.controller,
            linkIndex: widget.linkIndex,
            onOpenWord: _openWord,
            revealExamplesOnOpen:
                widget.revealExamplesOnOpen && current.serial == 0,
          ),
        ),
      ),
    );
  }
}

class _WordDetailHistoryEntry {
  const _WordDetailHistoryEntry({
    required this.word,
    required this.serial,
    required this.chipKey,
  });

  final JapaneseWord word;
  final int serial;
  final GlobalKey chipKey;
}

class _WordHistoryChip extends StatelessWidget {
  const _WordHistoryChip({
    super.key,
    required this.entry,
    required this.selected,
    required this.onPressed,
  });

  final _WordDetailHistoryEntry entry;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: ValueKey('word-detail-breadcrumb-${entry.serial}'),
      selected: selected,
      showCheckmark: false,
      tooltip: selected
          ? '${entry.word.lemma}, 현재 단어'
          : '${entry.word.lemma}로 이동',
      onSelected: (_) => onPressed(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white.withValues(alpha: 0.88),
      selectedColor: AppColors.moon,
      side: BorderSide(
        color: selected ? AppColors.moon : AppColors.onDarkMuted,
      ),
      label: Text(
        entry.word.lemma,
        style: TextStyle(
          color: AppColors.ink,
          fontFamily: AppFonts.japanese,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _WordDetailContent extends StatefulWidget {
  const _WordDetailContent({
    super.key,
    required this.word,
    required this.controller,
    required this.linkIndex,
    required this.onOpenWord,
    required this.revealExamplesOnOpen,
  });

  final JapaneseWord word;
  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onOpenWord;
  final bool revealExamplesOnOpen;

  @override
  State<_WordDetailContent> createState() => _WordDetailContentState();
}

class _WordDetailContentState extends State<_WordDetailContent> {
  bool _showExampleFurigana = true;
  bool _showLiteralTranslation = true;
  bool _showNaturalTranslation = true;
  bool _areExamplesExpanded = true;
  late bool _areFormsExpanded;
  late JapaneseWord _word;
  late final ScrollController _scrollController;
  final GlobalKey _examplesSectionKey = GlobalKey();

  JapaneseWord get word => _word;

  @override
  void initState() {
    super.initState();
    _word = widget.word;
    _areFormsExpanded = widget.controller.showDetailForms;
    _scrollController = ScrollController();
    widget.controller.addListener(_handleDetailFormsChanged);
    if (widget.revealExamplesOnOpen) {
      _scheduleRevealExamples();
    }
  }

  @override
  void didUpdateWidget(covariant _WordDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleDetailFormsChanged);
      widget.controller.addListener(_handleDetailFormsChanged);
      _areFormsExpanded = widget.controller.showDetailForms;
    }
    if (oldWidget.word.id != widget.word.id) {
      _word = widget.word;
    }
    if (!oldWidget.revealExamplesOnOpen && widget.revealExamplesOnOpen) {
      _areExamplesExpanded = true;
      _scheduleRevealExamples();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleDetailFormsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDetailFormsChanged() {
    if (!mounted) return;
    final next = widget.controller.showDetailForms;
    if (next == _areFormsExpanded) return;
    setState(() => _areFormsExpanded = next);
  }

  void _setExamplesExpanded(bool value) {
    if (_areExamplesExpanded == value) return;
    setState(() => _areExamplesExpanded = value);
  }

  void _scheduleRevealExamples() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_areExamplesExpanded) {
        setState(() => _areExamplesExpanded = true);
        _scheduleRevealExamples();
        return;
      }
      final targetContext = _examplesSectionKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: AppDurations.standard,
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView(
        controller: _scrollController,
        key: ValueKey('word-detail-scroll-${word.id}'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          KeyedSubtree(
            key: ValueKey('word-detail-content-${word.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReactiveWordHeading(
                  word: word,
                  controller: widget.controller,
                  onInfoPressed: () => _showWordInfo(context, word),
                ),
                const SizedBox(height: AppSpacing.xl),
                _MeaningPanel(word: word),
                if (word.usageNotes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.section),
                  _DetailSectionHeader(
                    key: ValueKey('word-detail-usage-notes-${word.id}'),
                    icon: Icons.lightbulb_outline_rounded,
                    title: '부연 설명',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _UsageNotesPanel(word: word),
                ],
                const SizedBox(height: AppSpacing.section),
                KeyedSubtree(
                  key: ValueKey('word-detail-examples-${word.id}'),
                  child: _DetailSectionHeader(
                    key: _examplesSectionKey,
                    icon: Icons.auto_stories_rounded,
                    title: '예문',
                    onTap: () => _setExamplesExpanded(!_areExamplesExpanded),
                    trailing: IconButton(
                      key: ValueKey('word-detail-examples-toggle-${word.id}'),
                      tooltip: _areExamplesExpanded ? '예문 접기' : '예문 펼치기',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _setExamplesExpanded(!_areExamplesExpanded),
                      icon: Icon(
                        _areExamplesExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                if (_areExamplesExpanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ExampleDisplayOptions(
                    showFurigana: _showExampleFurigana,
                    showLiteral: _showLiteralTranslation,
                    showNatural: _showNaturalTranslation,
                    onFuriganaChanged: (value) {
                      setState(() => _showExampleFurigana = value);
                    },
                    onLiteralChanged: (value) {
                      setState(() => _showLiteralTranslation = value);
                    },
                    onNaturalChanged: (value) {
                      setState(() => _showNaturalTranslation = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (word.examples.isEmpty)
                    const _InlineEmpty(message: '등록된 예문이 없습니다.')
                  else
                    for (
                      var index = 0;
                      index < word.examples.length;
                      index++
                    ) ...[
                      _ExampleCard(
                        key: ValueKey('word-example-${word.id}-$index'),
                        number: index + 1,
                        word: word,
                        example: word.examples[index],
                        linkIndex: widget.linkIndex,
                        onWordTap: _openLinkedWord,
                        showFurigana: _showExampleFurigana,
                        showLiteral: _showLiteralTranslation,
                        showNatural: _showNaturalTranslation,
                      ),
                      if (index != word.examples.length - 1)
                        const SizedBox(height: AppSpacing.md),
                    ],
                ],
                if (word.isInflectable) ...[
                  const SizedBox(height: AppSpacing.section),
                  _DetailSectionHeader(
                    key: ValueKey('word-detail-forms-${word.id}'),
                    icon: Icons.account_tree_rounded,
                    title: '활용형',
                    onTap: () => widget.controller.setShowDetailForms(
                      !_areFormsExpanded,
                    ),
                    trailing: IconButton(
                      key: ValueKey('word-detail-forms-toggle-${word.id}'),
                      tooltip: _areFormsExpanded ? '활용형 접기' : '활용형 펼치기',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => widget.controller.setShowDetailForms(
                        !_areFormsExpanded,
                      ),
                      icon: Icon(
                        _areFormsExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 22,
                      ),
                    ),
                  ),
                  if (_areFormsExpanded) ...[
                    const SizedBox(height: AppSpacing.md),
                    if (word.forms.isEmpty)
                      const _InlineEmpty(message: '등록된 활용형이 없습니다.')
                    else
                      for (
                        var index = 0;
                        index < word.forms.length;
                        index++
                      ) ...[
                        _FormCard(
                          key: ValueKey('word-form-${word.id}-$index'),
                          wordId: word.id,
                          form: word.forms[index],
                        ),
                        if (index != word.forms.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openLinkedWord(JapaneseWord linkedWord) {
    if (linkedWord.id == word.id) {
      _scrollController.animateTo(
        0,
        duration: AppDurations.standard,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    widget.onOpenWord(linkedWord);
  }
}

class _ReactiveWordHeading extends StatefulWidget {
  const _ReactiveWordHeading({
    required this.word,
    required this.controller,
    required this.onInfoPressed,
  });

  final JapaneseWord word;
  final StudyController controller;
  final VoidCallback onInfoPressed;

  @override
  State<_ReactiveWordHeading> createState() => _ReactiveWordHeadingState();
}

class _ReactiveWordHeadingState extends State<_ReactiveWordHeading> {
  late _WordHeadingSignal _signal;

  @override
  void initState() {
    super.initState();
    _signal = _WordHeadingSignal.capture(widget.controller, widget.word.id);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ReactiveWordHeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.word.id != widget.word.id) {
      _signal = _WordHeadingSignal.capture(widget.controller, widget.word.id);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final next = _WordHeadingSignal.capture(widget.controller, widget.word.id);
    if (next == _signal) return;
    setState(() => _signal = next);
  }

  @override
  Widget build(BuildContext context) {
    return _WordHeading(
      word: widget.word,
      bookmarked: _signal.bookmarked,
      known: _signal.known,
      bookmarkedAtMillis: _signal.bookmarkedAtMillis,
      knownAtMillis: _signal.knownAtMillis,
      quizAttempts: _signal.quizAttempts,
      quizCorrect: _signal.quizCorrect,
      onBookmarkChanged: (_) {
        widget.controller.toggleBookmark(widget.word.id);
      },
      onKnownChanged: (_) {
        widget.controller.toggleKnown(widget.word.id);
      },
      onInfoPressed: widget.onInfoPressed,
    );
  }
}

class _WordHeadingSignal {
  const _WordHeadingSignal({
    required this.bookmarked,
    required this.known,
    required this.bookmarkedAtMillis,
    required this.knownAtMillis,
    required this.quizAttempts,
    required this.quizCorrect,
  });

  factory _WordHeadingSignal.capture(
    StudyController controller,
    String wordId,
  ) {
    return _WordHeadingSignal(
      bookmarked: controller.isBookmarked(wordId),
      known: controller.isKnown(wordId),
      bookmarkedAtMillis: controller.bookmarkTimestampFor(wordId),
      knownAtMillis: controller.knownTimestampFor(wordId),
      quizAttempts: controller.quizAttemptsFor(wordId),
      quizCorrect: controller.quizCorrectFor(wordId),
    );
  }

  final bool bookmarked;
  final bool known;
  final int? bookmarkedAtMillis;
  final int? knownAtMillis;
  final int quizAttempts;
  final int quizCorrect;

  @override
  bool operator ==(Object other) {
    return other is _WordHeadingSignal &&
        bookmarked == other.bookmarked &&
        known == other.known &&
        bookmarkedAtMillis == other.bookmarkedAtMillis &&
        knownAtMillis == other.knownAtMillis &&
        quizAttempts == other.quizAttempts &&
        quizCorrect == other.quizCorrect;
  }

  @override
  int get hashCode => Object.hash(
    bookmarked,
    known,
    bookmarkedAtMillis,
    knownAtMillis,
    quizAttempts,
    quizCorrect,
  );
}

class _WordHeading extends StatelessWidget {
  const _WordHeading({
    required this.word,
    required this.bookmarked,
    required this.known,
    required this.bookmarkedAtMillis,
    required this.knownAtMillis,
    required this.quizAttempts,
    required this.quizCorrect,
    required this.onBookmarkChanged,
    required this.onKnownChanged,
    required this.onInfoPressed,
  });

  final JapaneseWord word;
  final bool bookmarked;
  final bool known;
  final int? bookmarkedAtMillis;
  final int? knownAtMillis;
  final int quizAttempts;
  final int quizCorrect;
  final ValueChanged<bool> onBookmarkChanged;
  final ValueChanged<bool> onKnownChanged;
  final VoidCallback onInfoPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: AozoraRubyText(
                buildAozoraRubySourceForReadings(word.lemma, word.readings),
                key: const ValueKey('word-detail-lemma'),
                baseStyle: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 30,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
                rubyStyle: const TextStyle(
                  color: AppColors.reading,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
                onTap: () => speakJapaneseWithFeedback(
                  context,
                  _wordSpeech(word),
                  reading: word.reading,
                  pitchAccent: word.unambiguousPitchAccentForReading(
                    word.reading,
                  ),
                ),
                tapSemanticsLabel: '${word.lemma}, 일본어 발음 듣기',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            JapaneseTtsButton(
              key: ValueKey('word-detail-tts-${word.id}'),
              text: _wordSpeech(word),
              reading: word.reading,
              pitchAccent: word.unambiguousPitchAccentForReading(word.reading),
              tooltip: '${word.lemma} 일본어 발음 듣기',
            ),
          ],
        ),
        if (word.alternativeReadings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: '읽기, ${word.readings.join(', ')}',
            child: Wrap(
              key: ValueKey('word-detail-readings-${word.id}'),
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '읽기',
                  style: TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final reading in word.readings)
                  ActionChip(
                    key: ValueKey('word-detail-reading-${word.id}-$reading'),
                    tooltip: '$reading 발음 듣기',
                    onPressed: () => speakJapaneseWithFeedback(
                      context,
                      word.speechTextForReading(reading),
                      reading: reading,
                      pitchAccent: word.unambiguousPitchAccentForReading(
                        reading,
                      ),
                    ),
                    avatar: const Icon(
                      Icons.volume_up_outlined,
                      size: 15,
                      color: AppColors.mutedBlue,
                    ),
                    label: Text(
                      reading,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontFamily: AppFonts.japanese,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.warmSurface,
                    side: const BorderSide(color: AppColors.cardOutline),
                  ),
              ],
            ),
          ),
        ],
        if (word.pronunciations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _PitchAccentChips(word: word),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _DetailBadge(label: word.partOfSpeech.labelKo),
            if (word.conjugationClass.isVerb)
              _DetailBadge(label: word.conjugationClass.labelKo),
            Tooltip(
              message: bookmarked ? '북마크 해제' : '북마크에 추가',
              child: CompactToggle(
                key: ValueKey('word-detail-bookmark-${word.id}'),
                label: '북마크',
                value: bookmarked,
                selectedIcon: Icons.bookmark_rounded,
                unselectedIcon: Icons.bookmark_border_rounded,
                onChanged: onBookmarkChanged,
              ),
            ),
            Tooltip(
              message: known ? '외웠어요 해제' : '외웠어요로 표시',
              child: CompactToggle(
                key: ValueKey('word-detail-known-${word.id}'),
                label: '외웠어요',
                value: known,
                selectedIcon: Icons.check_circle_rounded,
                unselectedIcon: Icons.check_circle_outline_rounded,
                onChanged: onKnownChanged,
              ),
            ),
            IconButton.outlined(
              key: const ValueKey('word-detail-info'),
              tooltip: '데모 묶음과 출처 정보',
              onPressed: onInfoPressed,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline_rounded, size: 18),
            ),
          ],
        ),
        if (bookmarked || known) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            key: ValueKey('word-detail-status-times-${word.id}'),
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              if (bookmarked)
                _StatusChangedAt(
                  key: ValueKey('word-detail-bookmarked-at-${word.id}'),
                  icon: Icons.bookmark_rounded,
                  label: '북마크',
                  timestampMillis: bookmarkedAtMillis,
                ),
              if (known)
                _StatusChangedAt(
                  key: ValueKey('word-detail-known-at-${word.id}'),
                  icon: Icons.check_circle_rounded,
                  label: '외웠어요',
                  timestampMillis: knownAtMillis,
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _QuizRecord(
          key: ValueKey('word-detail-quiz-record-${word.id}'),
          attempts: quizAttempts,
          correct: quizCorrect,
        ),
      ],
    );
  }
}

class _PitchAccentChips extends StatelessWidget {
  const _PitchAccentChips({required this.word});

  final JapaneseWord word;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      for (final pronunciation in word.pronunciations)
        for (final accent in pronunciation.pitchAccents)
          '${pronunciation.reading} [$accent]',
    ];
    return Semantics(
      label: '악센트, ${labels.join(', ')}. 각 칩을 누르면 선택한 악센트로 재생합니다.',
      child: Wrap(
        key: ValueKey('word-detail-pitch-accents-${word.id}'),
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            '악센트',
            style: TextStyle(
              color: AppColors.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final pronunciation in word.pronunciations)
            for (final accent in pronunciation.pitchAccents)
              ActionChip(
                key: ValueKey(
                  'word-detail-pitch-accent-${word.id}-'
                  '${pronunciation.reading}-$accent',
                ),
                tooltip: '${pronunciation.reading} [$accent] 악센트 듣기',
                onPressed: () => speakPitchAccentWithFeedback(
                  context,
                  pronunciation.reading,
                  accent,
                ),
                avatar: const Icon(
                  Icons.volume_up_outlined,
                  size: 15,
                  color: AppColors.mutedBlue,
                ),
                label: Text(
                  '${pronunciation.reading} [$accent]',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontFamily: AppFonts.japanese,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: AppColors.warmSurface,
                side: const BorderSide(color: AppColors.cardOutline),
              ),
        ],
      ),
    );
  }
}

class _StatusChangedAt extends StatelessWidget {
  const _StatusChangedAt({
    super.key,
    required this.icon,
    required this.label,
    required this.timestampMillis,
  });

  final IconData icon;
  final String label;
  final int? timestampMillis;

  @override
  Widget build(BuildContext context) {
    final timestampLabel = timestampMillis == null
        ? '날짜 기록 없음'
        : _formatStatusTimestamp(timestampMillis!);
    return Semantics(
      label: '$label 시각, $timestampLabel',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.subtleText),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '$label · $timestampLabel',
              style: const TextStyle(
                color: AppColors.subtleText,
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatStatusTimestamp(int timestampMillis) {
  final value = DateTime.fromMillisecondsSinceEpoch(timestampMillis).toLocal();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}년 ${value.month}월 ${value.day}일 $hour:$minute';
}

class _QuizRecord extends StatelessWidget {
  const _QuizRecord({super.key, required this.attempts, required this.correct});

  final int attempts;
  final int correct;

  @override
  Widget build(BuildContext context) {
    final record = formatQuizAccuracyRecord(
      attempts: attempts,
      correct: correct,
    );
    return Semantics(
      label: '단어별 퀴즈 기록, $record',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.warmSurface,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: AppColors.cardOutline),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.quiz_outlined,
                    color: AppColors.mutedBlue,
                    size: 18,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    '단어별 퀴즈 기록',
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                record,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeaningPanel extends StatelessWidget {
  const _MeaningPanel({required this.word});

  final JapaneseWord word;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('word-detail-meanings'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.translate_rounded, size: 17, color: AppColors.ink),
              SizedBox(width: AppSpacing.xs),
              Text(
                '뜻',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            word.meanings.join(' · '),
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageNotesPanel extends StatelessWidget {
  const _UsageNotesPanel({required this.word});

  final JapaneseWord word;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('word-detail-usage-notes-panel-${word.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < word.usageNotes.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: const BoxDecoration(
                    color: AppColors.reading,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    word.usageNotes[index],
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 13,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (index != word.usageNotes.length - 1)
              const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _DetailSectionHeader extends StatelessWidget {
  const _DetailSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.moon.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadii.inner),
                    ),
                    child: Icon(icon, size: 18, color: AppColors.ink),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _ExampleDisplayOptions extends StatelessWidget {
  const _ExampleDisplayOptions({
    required this.showFurigana,
    required this.showLiteral,
    required this.showNatural,
    required this.onFuriganaChanged,
    required this.onLiteralChanged,
    required this.onNaturalChanged,
  });

  final bool showFurigana;
  final bool showLiteral;
  final bool showNatural;
  final ValueChanged<bool> onFuriganaChanged;
  final ValueChanged<bool> onLiteralChanged;
  final ValueChanged<bool> onNaturalChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          CompactToggle(
            key: const ValueKey('example-show-furigana'),
            label: '후리가나',
            value: showFurigana,
            selectedIcon: Icons.text_fields_rounded,
            unselectedIcon: Icons.text_fields_rounded,
            onChanged: onFuriganaChanged,
          ),
          CompactToggle(
            key: const ValueKey('example-show-literal'),
            label: '직역',
            value: showLiteral,
            selectedIcon: Icons.subject_rounded,
            unselectedIcon: Icons.subject_rounded,
            onChanged: onLiteralChanged,
          ),
          CompactToggle(
            key: const ValueKey('example-show-natural'),
            label: '의역',
            value: showNatural,
            selectedIcon: Icons.chat_bubble_outline_rounded,
            unselectedIcon: Icons.chat_bubble_outline_rounded,
            onChanged: onNaturalChanged,
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({super.key, required this.wordId, required this.form});

  final String wordId;
  final ConjugationForm form;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailBadge(
            label: form.kind.labelKo,
            backgroundColor: AppColors.warmSurface,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AozoraRubyText(
                  _rubySource(form.surface, form.reading),
                  baseStyle: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                  rubyStyle: const TextStyle(
                    color: AppColors.reading,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                  onTap: () =>
                      speakJapaneseWithFeedback(context, _formSpeech(form)),
                  tapSemanticsLabel: '${form.surface}, 일본어 발음 듣기',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              JapaneseTtsButton(
                key: ValueKey(
                  'word-form-tts-$wordId-${form.kind.name}-${form.surface}',
                ),
                text: _formSpeech(form),
                tooltip: '${form.surface} 일본어 발음 듣기',
                iconSize: 17,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (form.note.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              form.note,
              style: const TextStyle(
                color: AppColors.subtleText,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({
    super.key,
    required this.number,
    required this.word,
    required this.example,
    required this.linkIndex,
    required this.onWordTap,
    required this.showFurigana,
    required this.showLiteral,
    required this.showNatural,
  });

  final int number;
  final JapaneseWord word;
  final ExampleSentence example;
  final ExampleWordLinkIndex linkIndex;
  final ValueChanged<JapaneseWord> onWordTap;
  final bool showFurigana;
  final bool showLiteral;
  final bool showNatural;

  @override
  Widget build(BuildContext context) {
    final rubySource = example.ruby.trim().isEmpty
        ? example.original
        : example.ruby;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: AppColors.moon,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (example.focusSurface.trim().isNotEmpty)
                      _DetailBadge(label: '학습 표현 · ${example.focusSurface}'),
                    if (example.formKind != null)
                      _DetailBadge(
                        label: example.formKind!.labelKo,
                        backgroundColor: AppColors.moon.withValues(alpha: 0.22),
                      ),
                  ],
                ),
              ),
              if (example.note.trim().isNotEmpty)
                IconButton(
                  key: ValueKey('example-info-${example.id}'),
                  tooltip: '예문 출처 정보',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showExampleInfo(context, example),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LinkedAozoraRubyText(
                  rubySource,
                  key: ValueKey('example-ruby-${example.id}'),
                  linkIndex: linkIndex,
                  preferredWord: word,
                  preferredSurface: example.focusSurface,
                  onWordTap: onWordTap,
                  onUnlinkedTap: () => speakJapaneseWithFeedback(
                    context,
                    _exampleSpeech(example),
                  ),
                  unlinkedTapSemanticsLabel:
                      '${example.original}, 일본어 예문 발음 듣기',
                  showRuby: showFurigana,
                  baseStyle: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                  rubyStyle: const TextStyle(
                    color: AppColors.reading,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              JapaneseTtsButton(
                key: ValueKey('example-tts-${example.id}'),
                text: _exampleSpeech(example),
                tooltip: '예문 일본어 발음 듣기',
                iconSize: 17,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (showLiteral) ...[
            const SizedBox(height: AppSpacing.lg),
            _TranslationBlock(
              key: ValueKey('example-literal-${example.id}'),
              label: '직역',
              text: example.literalTranslation,
              icon: Icons.subject_rounded,
              color: AppColors.body,
            ),
          ],
          if (showNatural) ...[
            const SizedBox(height: AppSpacing.md),
            _TranslationBlock(
              key: ValueKey('example-natural-${example.id}'),
              label: '의역',
              text: example.naturalTranslation,
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.mutedBlue,
            ),
          ],
        ],
      ),
    );
  }
}

class _TranslationBlock extends StatelessWidget {
  const _TranslationBlock({
    super.key,
    required this.label,
    required this.text,
    required this.icon,
    required this.color,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({
    required this.label,
    this.backgroundColor = AppColors.warmSurface,
  });

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.body,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.subtleText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Future<void> _showWordInfo(BuildContext context, JapaneseWord word) {
  final note = word.note.trim();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '단어 정보',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _InfoRow(label: '데모 묶음', value: word.level.displayName),
            _InfoRow(label: '품사', value: word.partOfSpeech.labelKo),
            _InfoRow(label: '활용', value: word.conjugationClass.labelKo),
            if (note.isNotEmpty) _InfoRow(label: '세부 정보', value: note),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showExampleInfo(BuildContext context, ExampleSentence example) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '예문 정보',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              example.note,
              style: const TextStyle(
                color: AppColors.body,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.subtleText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.body,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _rubySource(String surface, String reading) {
  return buildAozoraRubySource(surface, reading);
}

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
