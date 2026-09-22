import 'vocabulary.dart';

class GrammarPoint {
  const GrammarPoint({
    required this.id,
    required this.level,
    required this.pattern,
    required this.meaning,
    required this.formation,
    required this.explanation,
    required this.example,
    required this.exampleRuby,
    required this.translation,
    required this.conversationExample,
    required this.conversationExampleRuby,
    required this.conversationTranslation,
  });

  final String id;
  final JlptLevel level;
  final String pattern;
  final String meaning;
  final String formation;
  final String explanation;
  final String example;
  final String exampleRuby;
  final String translation;
  final String conversationExample;
  final String conversationExampleRuby;
  final String conversationTranslation;
}
