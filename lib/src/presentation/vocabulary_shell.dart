import 'dart:async';

import 'package:flutter/material.dart';

import '../application/study_controller.dart';
import '../domain/vocabulary.dart';
import '../services/live_wallpaper_service.dart';
import '../services/word_widget_service.dart';
import '../theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/quiz_page.dart';
import 'pages/study_page.dart';
import 'pages/word_list_page.dart';
import 'widgets/common_widgets.dart';
import 'widgets/linked_aozora_ruby_text.dart';
import 'widgets/settings_hub_sheet.dart';
import 'widgets/word_detail_sheet.dart';

class VocabularyShell extends StatefulWidget {
  const VocabularyShell({
    super.key,
    required this.controller,
    this.liveWallpaperService,
    this.wordWidgetService,
  });

  final StudyController controller;
  final LiveWallpaperService? liveWallpaperService;
  final WordWidgetService? wordWidgetService;

  @override
  State<VocabularyShell> createState() => _VocabularyShellState();
}

class _VocabularyShellState extends State<VocabularyShell>
    with WidgetsBindingObserver {
  int _destination = 0;
  late ExampleWordLinkIndex _exampleWordLinkIndex;
  late LiveWallpaperService _liveWallpaperService;
  late bool _ownsLiveWallpaperService;
  late WordWidgetService _wordWidgetService;
  late bool _ownsWordWidgetService;
  bool _detailNavigationScheduled = false;

  StudyController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _exampleWordLinkIndex = ExampleWordLinkIndex(_controller.words);
    _configureLiveWallpaperService();
    _configureWordWidgetService();
  }

  @override
  void didUpdateWidget(covariant VocabularyShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveWallpaperService != widget.liveWallpaperService) {
      _releaseLiveWallpaperService(oldWidget.controller);
      _configureLiveWallpaperService();
    } else if (oldWidget.controller != widget.controller) {
      _liveWallpaperService.connect(widget.controller);
    }
    if (oldWidget.wordWidgetService != widget.wordWidgetService) {
      _releaseWordWidgetService();
      _configureWordWidgetService();
    }
    if (oldWidget.controller != widget.controller) {
      _exampleWordLinkIndex = ExampleWordLinkIndex(_controller.words);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_liveWallpaperService.refreshStatus());
      unawaited(_wordWidgetService.refreshStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseLiveWallpaperService(widget.controller);
    _releaseWordWidgetService();
    super.dispose();
  }

  void _configureLiveWallpaperService() {
    _ownsLiveWallpaperService = widget.liveWallpaperService == null;
    _liveWallpaperService =
        widget.liveWallpaperService ?? LiveWallpaperService();
    _liveWallpaperService.addListener(_handleLiveWallpaperUpdate);
    _liveWallpaperService.connect(_controller);
  }

  void _releaseLiveWallpaperService(StudyController controller) {
    _liveWallpaperService.removeListener(_handleLiveWallpaperUpdate);
    if (_ownsLiveWallpaperService) {
      _liveWallpaperService.dispose();
    } else {
      _liveWallpaperService.disconnect(controller);
    }
  }

  void _configureWordWidgetService() {
    _ownsWordWidgetService = widget.wordWidgetService == null;
    _wordWidgetService = widget.wordWidgetService ?? WordWidgetService();
    unawaited(_wordWidgetService.refreshStatus());
  }

  void _releaseWordWidgetService() {
    if (_ownsWordWidgetService) _wordWidgetService.dispose();
  }

  void _handleLiveWallpaperUpdate() {
    if (!_liveWallpaperService.hasPendingDetailRequest ||
        _detailNavigationScheduled) {
      return;
    }
    _detailNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detailNavigationScheduled = false;
      if (!mounted) return;
      final request = _liveWallpaperService.takeNextDetailRequest();
      if (request == null) return;
      final word = _controller.wordById(request.wordId);
      if (word != null) {
        unawaited(
          showWordDetailPage(
            context,
            word: word,
            controller: _controller,
            linkIndex: _exampleWordLinkIndex,
            revealExamplesOnOpen: request.revealExamples,
          ),
        );
      }
      unawaited(_liveWallpaperService.acknowledgeDetailRequest(request));
      _handleLiveWallpaperUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final suffixes = ['오늘의 단어', '단어장', '학습', '퀴즈'];
    final selectorKeys = <Key>[
      const ValueKey('today-level-selector'),
      const ValueKey('wordbook-level-selector'),
      const ValueKey('study-level-selector'),
      const ValueKey('quiz-level-selector'),
    ];
    final showAppBarSubtitle = MediaQuery.textScalerOf(context).scale(1) <= 1.4;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const Padding(
          padding: EdgeInsets.only(left: 20, top: 16, bottom: 16),
          child: AppMark(),
        ),
        titleSpacing: 8,
        title: _ControllerLevelRangeTitle(
          controller: _controller,
          selectorKey: selectorKeys[_destination],
          suffix: suffixes[_destination],
          showSubtitle: showAppBarSubtitle,
          onTap: _showStudyLevelSheet,
        ),
        actions: [
          IconButton(
            key: const ValueKey('settings-button'),
            tooltip: '설정',
            onPressed: () => showSettingsHub(
              context,
              controller: _controller,
              liveWallpaperService: _liveWallpaperService,
              widgetService: _wordWidgetService,
              linkIndex: _exampleWordLinkIndex,
            ),
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _destination,
        children: [
          TickerMode(
            enabled: _destination == 0,
            child: HomePage(
              controller: _controller,
              linkIndex: _exampleWordLinkIndex,
              active: _destination == 0,
              onOpenWord: _openWord,
            ),
          ),
          TickerMode(
            enabled: _destination == 1,
            child: WordListPage(
              controller: _controller,
              active: _destination == 1,
              onOpenWord: _openWord,
            ),
          ),
          TickerMode(
            enabled: _destination == 2,
            child: StudyPage(
              controller: _controller,
              linkIndex: _exampleWordLinkIndex,
              active: _destination == 2,
              onOpenWord: _openWord,
            ),
          ),
          TickerMode(
            enabled: _destination == 3,
            child: QuizPage(
              controller: _controller,
              active: _destination == 3,
              onOpenWord: _openWord,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('main-navigation'),
        selectedIndex: _destination,
        onDestinationSelected: (index) {
          if (_destination == index) return;
          setState(() => _destination = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '오늘',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style_rounded),
            label: '단어장',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: '학습',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz_rounded),
            label: '퀴즈',
          ),
        ],
      ),
    );
  }

  void _openWord(JapaneseWord word) {
    showWordDetailPage(
      context,
      word: word,
      controller: _controller,
      linkIndex: _exampleWordLinkIndex,
    );
  }

  Future<void> _showStudyLevelSheet() async {
    var selected = Set<JlptLevel>.of(_controller.selectedWordLevels);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '데모 묶음 선택',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '선택한 범위는 오늘·단어장·퀴즈에 함께 적용돼요.',
                            style: TextStyle(
                              color: AppColors.body,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('select-all-word-levels'),
                      onPressed: () => setSheetState(
                        () => selected = Set.of(JlptLevel.values),
                      ),
                      child: const Text('전체 선택'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final level in JlptLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Material(
                      color: selected.contains(level)
                          ? AppColors.moon.withValues(alpha: 0.24)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        side: BorderSide(
                          color: selected.contains(level)
                              ? AppColors.moon
                              : AppColors.cardOutline,
                        ),
                      ),
                      child: CheckboxListTile(
                        key: ValueKey('word-level-${level.name}'),
                        value: selected.contains(level),
                        enabled:
                            !selected.contains(level) || selected.length > 1,
                        controlAffinity: ListTileControlAffinity.trailing,
                        title: Text(
                          level.label,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(level.subtitle),
                        activeColor: AppColors.ink,
                        checkColor: AppColors.moon,
                        onChanged: (value) {
                          setSheetState(() {
                            if (value ?? false) {
                              selected.add(level);
                            } else if (selected.length > 1) {
                              selected.remove(level);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('apply-word-levels'),
                  onPressed: () {
                    _controller.setWordLevels(selected);
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text('${selected.length}개 레벨 적용'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the shell itself independent from frequent study-state updates.
///
/// Deck swipes and per-word toggles notify the shared controller. Listening
/// only around the title prevents those events from rebuilding the complete
/// [IndexedStack] (including every inactive tab).
class _ControllerLevelRangeTitle extends StatefulWidget {
  const _ControllerLevelRangeTitle({
    required this.controller,
    required this.selectorKey,
    required this.suffix,
    required this.showSubtitle,
    required this.onTap,
  });

  final StudyController controller;
  final Key selectorKey;
  final String suffix;
  final bool showSubtitle;
  final VoidCallback onTap;

  @override
  State<_ControllerLevelRangeTitle> createState() =>
      _ControllerLevelRangeTitleState();
}

class _ControllerLevelRangeTitleState
    extends State<_ControllerLevelRangeTitle> {
  late int _levelMask;

  @override
  void initState() {
    super.initState();
    _levelMask = _maskOf(widget.controller.selectedWordLevels);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ControllerLevelRangeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _levelMask = _maskOf(widget.controller.selectedWordLevels);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final nextMask = _maskOf(widget.controller.selectedWordLevels);
    if (!mounted || nextMask == _levelMask) return;
    setState(() => _levelMask = nextMask);
  }

  @override
  Widget build(BuildContext context) {
    return _LevelRangeAppBarTitle(
      selectorKey: widget.selectorKey,
      title: _rangeTitle(widget.controller.selectedWordLevels, widget.suffix),
      showSubtitle: widget.showSubtitle,
      onTap: widget.onTap,
    );
  }
}

class _LevelRangeAppBarTitle extends StatelessWidget {
  const _LevelRangeAppBarTitle({
    required this.selectorKey,
    required this.title,
    required this.showSubtitle,
    required this.onTap,
  });

  final Key selectorKey;
  final String title;
  final bool showSubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, 공용 데모 범위 선택',
      child: InkWell(
        key: selectorKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.moon,
                    size: 20,
                  ),
                ],
              ),
              if (showSubtitle)
                const Text(
                  '눌러서 공용 데모 범위 선택',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _rangeTitle(Set<JlptLevel> levels, String suffix) {
  final ordered = JlptLevel.values.where(levels.contains).toList();
  if (ordered.length == JlptLevel.values.length) return '전체 레벨 $suffix';
  return '${ordered.map((level) => level.label).join(' · ')} $suffix';
}

int _maskOf(Set<JlptLevel> levels) {
  var mask = 0;
  for (final level in levels) {
    mask |= 1 << level.index;
  }
  return mask;
}
