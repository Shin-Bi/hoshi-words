import '../domain/grammar.dart';
import '../domain/vocabulary.dart';

// Newly authored demonstrations. Groups are UI themes, not exam levels.
const jlptGrammarCatalog = <GrammarPoint>[
  GrammarPoint(
    id: 'demo-place',
    level: JlptLevel.n5,
    pattern: '～にあります',
    meaning: '~에 있어요',
    formation: '장소 + に + あります',
    explanation: '이 예문에서는 물건이 놓인 장소를 に로 표시합니다.',
    example: '青い箱は窓のそばにあります。',
    exampleRuby: '｜青《あお》い｜箱《はこ》は｜窓《まど》のそばにあります。',
    translation: '파란 상자는 창문 곁에 있어요.',
    conversationExample: '鍵は小さな箱にあります。',
    conversationExampleRuby: '｜鍵《かぎ》は｜小《ちい》さな｜箱《はこ》にあります。',
    conversationTranslation: '열쇠는 작은 상자에 있어요.',
  ),
  GrammarPoint(
    id: 'demo-destination',
    level: JlptLevel.n4,
    pattern: '～まで歩きます',
    meaning: '~까지 걸어요',
    formation: '목적지 + まで + 歩きます',
    explanation: '이 예문에서는 걸어가는 구간의 끝을 まで로 표시합니다.',
    example: '花のある橋まで歩きます。',
    exampleRuby: '｜花《はな》のある｜橋《はし》まで｜歩《ある》きます。',
    translation: '꽃이 있는 다리까지 걸어요.',
    conversationExample: '今日は公園まで歩きます。',
    conversationExampleRuby: '｜今日《きょう》は｜公園《こうえん》まで｜歩《ある》きます。',
    conversationTranslation: '오늘은 공원까지 걸어요.',
  ),
];
