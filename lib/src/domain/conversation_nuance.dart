/// One naturally occurring sentence-final or utterance-final conversation
/// pattern and the pragmatic choices that make it sound appropriate.
class ConversationNuancePoint {
  const ConversationNuancePoint({
    required this.id,
    required this.pattern,
    required this.shortMeaning,
    required this.registerLabel,
    required this.toneLabel,
    required this.formation,
    required this.explanation,
    required this.caution,
    required this.contrast,
    required this.examples,
  });

  final String id;
  final String pattern;
  final String shortMeaning;
  final String registerLabel;
  final String toneLabel;
  final String formation;
  final String explanation;
  final String caution;
  final String contrast;
  final List<ConversationNuanceExample> examples;
}

/// A first-party example written for a concrete conversational situation.
class ConversationNuanceExample {
  const ConversationNuanceExample({
    required this.sentence,
    required this.sentenceRuby,
    required this.translation,
    required this.situation,
  });

  final String sentence;
  final String sentenceRuby;
  final String translation;
  final String situation;
}
