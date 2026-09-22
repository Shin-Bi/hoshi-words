import '../domain/conversation_nuance.dart';

// Newly authored conversation demonstration.
const conversationNuanceCatalog = <ConversationNuancePoint>[
  ConversationNuancePoint(
    id: 'demo-ne',
    pattern: '～ね',
    shortMeaning: '~네요',
    registerLabel: '함께 이야기하기',
    toneLabel: '느낌 나누기',
    formation: '문장 + ね',
    explanation: '이 장면에서는 함께 보는 꽃에 대한 느낌을 상대와 나눕니다.',
    caution: '같은 표현도 억양과 대화 상황에 따라 다르게 들릴 수 있습니다.',
    contrast: 'ね를 빼면 상대와 느낌을 나누는 색채가 덜 드러납니다.',
    examples: [
      ConversationNuanceExample(
        sentence: 'この花、きれいですね。',
        sentenceRuby: 'この｜花《はな》、きれいですね。',
        translation: '이 꽃, 예쁘네요.',
        situation: '창가의 꽃을 함께 보며 말하기',
      ),
    ],
  ),
];
