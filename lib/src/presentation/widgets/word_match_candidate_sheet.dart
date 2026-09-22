import 'package:flutter/material.dart';

import '../../domain/vocabulary.dart';
import '../../theme/app_theme.dart';
import 'linked_aozora_ruby_text.dart';

/// Returns the selected dictionary word for [match].
///
/// A match with one candidate resolves immediately. Homographs are presented
/// in a bottom sheet so the user can choose the word that fits the context.
Future<JapaneseWord?> showWordMatchCandidateSheet(
  BuildContext context, {
  required ExampleWordMatch match,
}) {
  final candidates = match.candidateWords.isEmpty
      ? <JapaneseWord>[match.word]
      : match.candidateWords;
  if (candidates.length == 1) {
    return Future<JapaneseWord?>.value(candidates.first);
  }

  return showModalBottomSheet<JapaneseWord>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.72,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.xxs,
                AppSpacing.xxl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '「${match.surface}」 단어 선택',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    '문맥에 맞는 표제어를 선택해 주세요.',
                    style: TextStyle(color: AppColors.subtleText, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                itemCount: candidates.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final word = candidates[index];
                  return Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      side: const BorderSide(color: AppColors.cardOutline),
                    ),
                    child: ListTile(
                      key: ValueKey('sentence-candidate-${word.id}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                      ),
                      title: Text(
                        '${word.lemma}【${word.readings.join('・')}】',
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontFamily: AppFonts.japanese,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        '${word.level.label} · ${word.partOfSpeech.labelKo}\n'
                        '${word.meanings.join(' · ')}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(sheetContext).pop(word),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
