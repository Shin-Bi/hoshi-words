import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsuki_words/src/app.dart';
import 'package:tsuki_words/src/application/study_controller.dart';
import 'package:tsuki_words/src/data/vocabulary_repository.dart';
import 'package:tsuki_words/src/data/jlpt_grammar_catalog.dart';
import 'package:tsuki_words/src/data/conversation_nuance_catalog.dart';
import 'package:tsuki_words/src/services/japanese_tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'demo vocabulary parses, validates and searches Japanese and Korean',
    () async {
      const repository = VocabularyRepository();
      final words = await repository.loadAll();
      expect(words, hasLength(10));
      expect(words.map((word) => word.id).toSet(), hasLength(10));
      for (final word in words) {
        expect(word.validate(), isEmpty, reason: word.id);
        expect(word.id, startsWith('demo-'));
      }
      expect(
        (await repository.search('별')).map((word) => word.id),
        contains('demo-star'),
      );
      expect(
        (await repository.search('ほし')).map((word) => word.id),
        contains('demo-star'),
      );
      expect(jlptGrammarCatalog, hasLength(2));
      expect(conversationNuanceCatalog, hasLength(1));
    },
  );

  test('bookmark and known state survive controller reload', () async {
    final words = await const VocabularyRepository().loadAll();
    final first = await StudyController.create(words);
    first.toggleBookmark('demo-star');
    first.toggleKnown('demo-paper');
    await first.flushPendingWrites(throwOnError: true);
    first.dispose();
    final restored = await StudyController.create(words);
    expect(restored.isBookmarked('demo-star'), isTrue);
    expect(restored.isKnown('demo-paper'), isTrue);
    restored.dispose();
  });

  test('Japanese TTS sends only text to the device engine', () async {
    const channel = MethodChannel('demo-test-tts');
    MethodCall? request;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          request = call;
          return {'status': 'completed', 'engine': 'android'};
        });
    const service = JapaneseTtsService(
      channel: channel,
      platformOverride: TargetPlatform.android,
    );
    expect((await service.speak('  ほし  ')).isSuccess, isTrue);
    expect(request?.method, 'speak');
    expect(request?.arguments, {'text': 'ほし'});
    expect((await service.speak(' ')).status, JapaneseTtsStatus.invalidText);
  });

  testWidgets('demo opens and navigates to vocabulary and quiz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = (await tester.runAsync(() async {
      final words = await const VocabularyRepository().loadAll();
      return StudyController.create(words);
    }))!;
    addTearDown(controller.dispose);
    await tester.pumpWidget(VocabularyApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-flash-card')), findsOneWidget);
    await tester.tap(find.text('단어장').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('퀴즈').last);
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('quiz-start'));
    await tester.scrollUntilVisible(
      start,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('quiz-settings-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
