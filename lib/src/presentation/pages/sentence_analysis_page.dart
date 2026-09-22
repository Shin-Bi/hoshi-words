import 'package:flutter/material.dart';

import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/linked_aozora_ruby_text.dart';
import '../widgets/word_match_candidate_sheet.dart';

class SentenceAnalysisPage extends StatefulWidget {
  const SentenceAnalysisPage({
    super.key,
    required this.linkIndex,
    required this.active,
    required this.onOpenWord,
  });

  final ExampleWordLinkIndex linkIndex;
  final bool active;
  final ValueChanged<JapaneseWord> onOpenWord;

  @override
  State<SentenceAnalysisPage> createState() => _SentenceAnalysisPageState();
}

class _SentenceAnalysisPageState extends State<SentenceAnalysisPage> {
  static const _maximumLength = 500;

  late final TextEditingController _inputController;
  late final FocusNode _inputFocusNode;
  SentenceWordAnalysis? _analysis;
  bool _hasInput = false;
  bool _showRuby = true;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SentenceAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _inputFocusNode.unfocus();
    if (oldWidget.linkIndex != widget.linkIndex && _analysis != null) {
      _analysis = widget.linkIndex.analyzeSentence(_inputController.text);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleInputChanged(String input) {
    final hasInput = input.trim().isNotEmpty;
    final resultIsStale = _analysis != null && _analysis!.sentence != input;
    if (hasInput == _hasInput && !resultIsStale) return;
    setState(() {
      _hasInput = hasInput;
      if (resultIsStale) _analysis = null;
    });
  }

  void _analyze() {
    if (!_hasInput) return;
    setState(() {
      _analysis = widget.linkIndex.analyzeSentence(_inputController.text);
    });
    _inputFocusNode.unfocus();
  }

  void _clear() {
    _inputController.clear();
    setState(() {
      _hasInput = false;
      _analysis = null;
    });
    _inputFocusNode.requestFocus();
  }

  Future<void> _openMatch(ExampleWordMatch match) async {
    final selected = await showWordMatchCandidateSheet(context, match: match);
    if (selected != null && mounted) widget.onOpenWord(selected);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView(
        key: const ValueKey('sentence-analysis-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.xl,
          AppSpacing.screenHorizontal,
          AppSpacing.screenBottom,
        ),
        children: [
          _buildInputCard(context),
          const SizedBox(height: AppSpacing.xl),
          AnimatedSwitcher(
            duration: AppDurations.standard,
            child: _buildResult(context),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(BuildContext context) {
    return Container(
      key: const ValueKey('sentence-input-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              AppMark(
                size: 38,
                icon: Icons.translate_rounded,
                semanticsLabel: '문장 분석',
              ),
              SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '일본어 문장',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xxs),
                    Text(
                      '전체 데모 단어장에서 일치하는 표현을 찾아요.',
                      style: TextStyle(
                        color: AppColors.subtleText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            key: const ValueKey('sentence-input'),
            controller: _inputController,
            focusNode: _inputFocusNode,
            onChanged: _handleInputChanged,
            minLines: 4,
            maxLines: 8,
            maxLength: _maximumLength,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              color: AppColors.ink,
              fontFamily: AppFonts.japanese,
              fontSize: 17,
              height: 1.55,
            ),
            decoration: const InputDecoration(
              hintText: '예: 紙に星を描きます。',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('sentence-clear-button'),
                onPressed: _hasInput ? _clear : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('지우기'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('sentence-analyze-button'),
                  onPressed: _hasInput ? _analyze : null,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('분석하기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final analysis = _analysis;
    if (analysis == null) {
      return const _AnalysisNotice(
        key: ValueKey('sentence-analysis-guide'),
        icon: Icons.auto_awesome_rounded,
        title: '문장을 입력하고 분석해 보세요',
        message: '표제어·대체 표기·등록된 활용형을 기준으로 찾아요.',
      );
    }
    if (!analysis.hasMatches) {
      return const _AnalysisNotice(
        key: ValueKey('sentence-no-matches'),
        icon: Icons.search_off_rounded,
        title: '일치하는 단어가 없어요',
        message: '단어장에 등록된 표기와 활용형을 기준으로 다시 확인해 주세요.',
      );
    }

    return Container(
      key: const ValueKey('sentence-analysis-result'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '분석 결과',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              CompactToggle(
                key: const ValueKey('sentence-ruby-toggle'),
                label: '후리가나',
                value: _showRuby,
                onChanged: (value) => setState(() => _showRuby = value),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            analysis.ambiguousMatchCount == 0
                ? '${analysis.matches.length}곳에서 '
                      '${analysis.uniqueWordCount}개 단어를 찾았어요.'
                : '${analysis.matches.length}곳에서 '
                      '${analysis.uniqueWordCount}개 후보를 찾았어요. '
                      '선택이 필요한 곳은 ${analysis.ambiguousMatchCount}곳이에요.',
            key: const ValueKey('sentence-match-summary'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.panel),
              border: Border.all(color: AppColors.divider),
            ),
            child: RepaintBoundary(
              child: LinkedAozoraRubyText(
                analysis.rubySource,
                key: const ValueKey('sentence-linked-result'),
                linkIndex: widget.linkIndex,
                showRuby: _showRuby,
                onWordTap: widget.onOpenWord,
                onMatchTap: _openMatch,
                baseStyle: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: AppFonts.japanese,
                  fontSize: 19,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
                rubyStyle: const TextStyle(
                  color: AppColors.reading,
                  fontFamily: AppFonts.japanese,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
                semanticsLabel: spokenAozoraRuby(analysis.rubySource),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 16,
                color: AppColors.mutedBlue,
              ),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '색이 표시된 단어를 누르면 자세히 보기가 열려요. '
                  '여러 단어가 같은 표기라면 먼저 후보를 선택해요.',
                  style: TextStyle(
                    color: AppColors.subtleText,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisNotice extends StatelessWidget {
  const _AnalysisNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.mutedBlue, size: 24),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
