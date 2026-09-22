enum JlptLevel { n5, n4, n3, n2, n1 }

enum VocabularySearchScope { lemma, reading, meaning, example }

extension VocabularySearchScopeX on VocabularySearchScope {
  String get labelKo => switch (this) {
    VocabularySearchScope.lemma => '단어',
    VocabularySearchScope.reading => '읽기',
    VocabularySearchScope.meaning => '뜻',
    VocabularySearchScope.example => '예문',
  };

  int get mask => 1 << index;
}

const vocabularySearchAllScopeMask = 0x0f;

int vocabularySearchScopeMask(Iterable<VocabularySearchScope> scopes) {
  var mask = 0;
  for (final scope in scopes) {
    mask |= scope.mask;
  }
  return mask;
}

extension JlptLevelX on JlptLevel {
  String get label => '데모 ${index + 1}';

  String get subtitle => switch (this) {
    JlptLevel.n5 => '하늘',
    JlptLevel.n4 => '집',
    JlptLevel.n3 => '산책',
    JlptLevel.n2 => '쉼',
    JlptLevel.n1 => '책상',
  };

  String get displayName => '$label · $subtitle';

  int get sortOrder => index;

  static JlptLevel parse(Object? value) {
    final code = _requiredString(value, 'level').toLowerCase();
    return _enumByName(_jlptLevelByName, code, 'level');
  }
}

enum WordPartOfSpeech {
  noun,
  verbalNoun,
  verb,
  iAdjective,
  naAdjective,
  adverb,
  pronoun,
  particle,
  conjunction,
  expression,
  counter,
  prefix,
  suffix,
  other,
}

extension WordPartOfSpeechX on WordPartOfSpeech {
  String get labelKo => switch (this) {
    WordPartOfSpeech.noun => '명사',
    WordPartOfSpeech.verbalNoun => '명사·する동사',
    WordPartOfSpeech.verb => '동사',
    WordPartOfSpeech.iAdjective => 'い형용사',
    WordPartOfSpeech.naAdjective => 'な형용사',
    WordPartOfSpeech.adverb => '부사',
    WordPartOfSpeech.pronoun => '대명사',
    WordPartOfSpeech.particle => '조사',
    WordPartOfSpeech.conjunction => '접속사',
    WordPartOfSpeech.expression => '표현',
    WordPartOfSpeech.counter => '조수사',
    WordPartOfSpeech.prefix => '접두사',
    WordPartOfSpeech.suffix => '접미사',
    WordPartOfSpeech.other => '기타',
  };

  static WordPartOfSpeech parse(Object? value) => _enumByName(
    _partOfSpeechByName,
    _requiredString(value, 'partOfSpeech'),
    'partOfSpeech',
  );
}

enum ConjugationClass {
  none,
  ichidan,
  godanU,
  godanKu,
  godanGu,
  godanSu,
  godanTsu,
  godanNu,
  godanBu,
  godanMu,
  godanRu,
  suru,
  zuru,
  kuru,
  irregularVerb,
  iAdjective,
  naAdjective,
}

extension ConjugationClassX on ConjugationClass {
  String get labelKo => switch (this) {
    ConjugationClass.none => '활용 없음',
    ConjugationClass.ichidan => '1단 동사',
    ConjugationClass.godanU => '5단 동사·ワ행',
    ConjugationClass.godanKu => '5단 동사·カ행',
    ConjugationClass.godanGu => '5단 동사·ガ행',
    ConjugationClass.godanSu => '5단 동사·サ행',
    ConjugationClass.godanTsu => '5단 동사·タ행',
    ConjugationClass.godanNu => '5단 동사·ナ행',
    ConjugationClass.godanBu => '5단 동사·バ행',
    ConjugationClass.godanMu => '5단 동사·マ행',
    ConjugationClass.godanRu => '5단 동사·ラ행',
    ConjugationClass.suru => 'サ변 동사',
    ConjugationClass.zuru => 'ずる 동사',
    ConjugationClass.kuru => 'カ변 동사',
    ConjugationClass.irregularVerb => '불규칙 동사',
    ConjugationClass.iAdjective => 'い형용사',
    ConjugationClass.naAdjective => 'な형용사',
  };

  bool get isVerb => switch (this) {
    ConjugationClass.ichidan ||
    ConjugationClass.godanU ||
    ConjugationClass.godanKu ||
    ConjugationClass.godanGu ||
    ConjugationClass.godanSu ||
    ConjugationClass.godanTsu ||
    ConjugationClass.godanNu ||
    ConjugationClass.godanBu ||
    ConjugationClass.godanMu ||
    ConjugationClass.godanRu ||
    ConjugationClass.suru ||
    ConjugationClass.zuru ||
    ConjugationClass.kuru ||
    ConjugationClass.irregularVerb => true,
    _ => false,
  };

  static ConjugationClass parse(Object? value) => _enumByName(
    _conjugationClassByName,
    _requiredString(value, 'conjugationClass'),
    'conjugationClass',
  );
}

enum ConjugationKind {
  plainPresent,
  plainNegative,
  plainPast,
  plainPastNegative,
  politePresent,
  politeNegative,
  politePastNegative,
  stem,
  teForm,
  potential,
  passive,
  causative,
  causativePassive,
  imperative,
  volitional,
  conditionalBa,
  conditionalTara,
  conditionalNara,
  desireTai,
  reasonKara,
  attributive,
  adverbial,
}

extension ConjugationKindX on ConjugationKind {
  String get labelKo => switch (this) {
    ConjugationKind.plainPresent => '보통형·현재',
    ConjugationKind.plainNegative => '보통형·부정',
    ConjugationKind.plainPast => '보통형·과거',
    ConjugationKind.plainPastNegative => '보통형·과거 부정',
    ConjugationKind.politePresent => '정중형·현재',
    ConjugationKind.politeNegative => '정중형·부정',
    ConjugationKind.politePastNegative => '정중형·과거 부정',
    ConjugationKind.stem => '연용형',
    ConjugationKind.teForm => 'て형',
    ConjugationKind.potential => '가능형',
    ConjugationKind.passive => '수동형',
    ConjugationKind.causative => '사역형',
    ConjugationKind.causativePassive => '사역 수동형',
    ConjugationKind.imperative => '명령형',
    ConjugationKind.volitional => '의지형',
    ConjugationKind.conditionalBa => 'ば 조건형',
    ConjugationKind.conditionalTara => '～たら 결합형',
    ConjugationKind.conditionalNara => 'なら 조건형',
    ConjugationKind.desireTai => '～たい 결합형',
    ConjugationKind.reasonKara => '～から 결합형',
    ConjugationKind.attributive => '연체형',
    ConjugationKind.adverbial => '부사형',
  };

  int get sortOrder => index;

  static ConjugationKind parse(Object? value) => _enumByName(
    _conjugationKindByName,
    _requiredString(value, 'kind'),
    'kind',
  );
}

const verbRequiredConjugations = <ConjugationKind>{
  ConjugationKind.politePresent,
  ConjugationKind.plainNegative,
  ConjugationKind.plainPast,
  ConjugationKind.plainPastNegative,
  ConjugationKind.teForm,
  ConjugationKind.potential,
  ConjugationKind.passive,
  ConjugationKind.conditionalBa,
  ConjugationKind.volitional,
  ConjugationKind.desireTai,
  ConjugationKind.conditionalTara,
  ConjugationKind.conditionalNara,
  ConjugationKind.reasonKara,
};

const iAdjectiveRequiredConjugations = <ConjugationKind>{
  ConjugationKind.plainNegative,
  ConjugationKind.plainPast,
  ConjugationKind.plainPastNegative,
  ConjugationKind.teForm,
  ConjugationKind.adverbial,
  ConjugationKind.conditionalBa,
  ConjugationKind.conditionalTara,
  ConjugationKind.conditionalNara,
  ConjugationKind.reasonKara,
};

const naAdjectiveRequiredConjugations = <ConjugationKind>{
  ConjugationKind.plainPresent,
  ConjugationKind.plainNegative,
  ConjugationKind.plainPast,
  ConjugationKind.plainPastNegative,
  ConjugationKind.teForm,
  ConjugationKind.conditionalNara,
  ConjugationKind.conditionalTara,
  ConjugationKind.reasonKara,
  ConjugationKind.attributive,
  ConjugationKind.adverbial,
};

class VocabularyPack {
  const VocabularyPack({
    required this.schemaVersion,
    required this.level,
    required this.assetPath,
    required this.words,
  });

  factory VocabularyPack.fromJson(
    Map<String, dynamic> json, {
    required String assetPath,
  }) {
    final schemaVersion = _requiredString(
      json['schemaVersion'],
      'schemaVersion',
    );
    if (schemaVersion != '3.0.0') {
      throw FormatException('지원하지 않는 어휘 스키마입니다: $schemaVersion');
    }
    final documentType = _requiredString(json['documentType'], 'documentType');
    if (documentType != 'japaneseVocabulary') {
      throw FormatException(
        '지원하지 않는 documentType입니다: $documentType ($assetPath)',
      );
    }
    final level = JlptLevelX.parse(json['level']);
    final words = List<JapaneseWord>.unmodifiable(
      _objectList(
        json['words'],
        'words',
      ).map((value) => JapaneseWord.fromJson(value, level: level)),
    );
    if (words.isEmpty) {
      throw FormatException('단어 팩이 비어 있습니다: $assetPath');
    }
    return VocabularyPack(
      schemaVersion: schemaVersion,
      level: level,
      assetPath: assetPath,
      words: words,
    );
  }

  final String schemaVersion;
  final JlptLevel level;
  final String assetPath;
  final List<JapaneseWord> words;
}

class JapaneseWord {
  JapaneseWord({
    required String id,
    required JlptLevel level,
    required String lemma,
    required String reading,
    required WordPartOfSpeech partOfSpeech,
    required ConjugationClass conjugationClass,
    required Iterable<String> meanings,
    required Iterable<ExampleSentence> examples,
    Iterable<ConjugationForm> forms = const [],
    Iterable<WordPronunciation> pronunciations = const [],
    Iterable<String> alternativeReadings = const [],
    Iterable<String> alternativeSpellings = const [],
    Iterable<String> usageNotes = const [],
    Iterable<String> tags = const [],
    String note = '',
  }) : this._(
         id: id,
         level: level,
         lemma: lemma,
         reading: reading,
         partOfSpeech: partOfSpeech,
         conjugationClass: conjugationClass,
         meanings: List<String>.unmodifiable(meanings),
         examples: List<ExampleSentence>.unmodifiable(examples),
         forms: List<ConjugationForm>.unmodifiable(forms),
         pronunciations: List<WordPronunciation>.unmodifiable(pronunciations),
         alternativeReadings: List<String>.unmodifiable(alternativeReadings),
         alternativeSpellings: List<String>.unmodifiable(alternativeSpellings),
         usageNotes: List<String>.unmodifiable(usageNotes),
         tags: List<String>.unmodifiable(tags),
         note: note,
       );

  JapaneseWord._({
    required this.id,
    required this.level,
    required this.lemma,
    required this.reading,
    required this.partOfSpeech,
    required this.conjugationClass,
    required this.meanings,
    required this.examples,
    required this.forms,
    required this.pronunciations,
    required this.alternativeReadings,
    required this.alternativeSpellings,
    required this.usageNotes,
    required this.tags,
    required this.note,
  }) : _searchIndex = _buildNormalizedWordSearchIndex(
         lemma: lemma,
         reading: reading,
         meanings: meanings,
         forms: forms,
         examples: examples,
         alternativeReadings: alternativeReadings,
         alternativeSpellings: alternativeSpellings,
         usageNotes: usageNotes,
         note: note,
       );

  factory JapaneseWord.fromJson(
    Map<String, dynamic> json, {
    required JlptLevel level,
  }) {
    final partOfSpeech = WordPartOfSpeechX.parse(json['partOfSpeech']);
    final conjugationClass = ConjugationClassX.parse(json['conjugationClass']);
    final meanings = List<String>.unmodifiable(
      _stringList(json['meanings'], 'meanings'),
    );
    if (meanings.isEmpty) {
      throw const FormatException('meanings에는 하나 이상의 뜻이 필요합니다.');
    }
    final examples = List<ExampleSentence>.unmodifiable(
      _objectList(json['examples'], 'examples').map(ExampleSentence.fromJson),
    );
    if (examples.isEmpty) {
      throw const FormatException('examples에는 하나 이상의 예문이 필요합니다.');
    }
    final forms = _withConditionalNara(
      lemma: _requiredString(json['lemma'], 'lemma'),
      reading: _requiredString(json['reading'], 'reading'),
      partOfSpeech: partOfSpeech,
      forms: _objectList(
        json['forms'] ?? const <dynamic>[],
        'forms',
      ).map(ConjugationForm.fromJson),
    );
    return JapaneseWord._(
      id: _requiredString(json['id'], 'id'),
      level: level,
      lemma: _requiredString(json['lemma'], 'lemma'),
      reading: _requiredString(json['reading'], 'reading'),
      partOfSpeech: partOfSpeech,
      conjugationClass: conjugationClass,
      meanings: meanings,
      forms: forms,
      examples: examples,
      pronunciations: List<WordPronunciation>.unmodifiable(
        _objectList(
          json['pronunciations'] ?? const <dynamic>[],
          'pronunciations',
        ).map(WordPronunciation.fromJson),
      ),
      alternativeReadings: List<String>.unmodifiable(
        _stringList(
          json['alternativeReadings'] ?? const <dynamic>[],
          'alternativeReadings',
        ),
      ),
      alternativeSpellings: List<String>.unmodifiable(
        _stringList(
          json['alternativeSpellings'] ?? const <dynamic>[],
          'alternativeSpellings',
        ),
      ),
      usageNotes: List<String>.unmodifiable(
        _stringList(json['usageNotes'] ?? const <dynamic>[], 'usageNotes'),
      ),
      tags: List<String>.unmodifiable(
        _stringList(json['tags'] ?? const <dynamic>[], 'tags'),
      ),
      note: _optionalString(json['note'], 'note'),
    );
  }

  final String id;
  final JlptLevel level;
  final String lemma;
  final String reading;
  final WordPartOfSpeech partOfSpeech;
  final ConjugationClass conjugationClass;
  final List<String> meanings;
  final List<ConjugationForm> forms;
  final List<ExampleSentence> examples;
  final List<WordPronunciation> pronunciations;
  final List<String> alternativeReadings;
  final List<String> alternativeSpellings;
  final List<String> usageNotes;
  final List<String> tags;
  final String note;
  final _VocabularySearchIndex _searchIndex;

  JapaneseWord withAdditionalExamples(Iterable<ExampleSentence> additional) {
    final additions = List<ExampleSentence>.of(additional);
    if (additions.isEmpty) return this;
    return JapaneseWord._(
      id: id,
      level: level,
      lemma: lemma,
      reading: reading,
      partOfSpeech: partOfSpeech,
      conjugationClass: conjugationClass,
      meanings: meanings,
      examples: List<ExampleSentence>.unmodifiable([...examples, ...additions]),
      forms: forms,
      pronunciations: pronunciations,
      alternativeReadings: alternativeReadings,
      alternativeSpellings: alternativeSpellings,
      usageNotes: usageNotes,
      tags: tags,
      note: note,
    );
  }

  bool get isInflectable => conjugationClass != ConjugationClass.none;

  String get primaryMeaning => meanings.first;

  List<String> get readings => List<String>.unmodifiable([
    reading,
    for (final value in alternativeReadings)
      if (value != reading) value,
  ]);

  WordPronunciation? pronunciationForReading(String value) {
    for (final pronunciation in pronunciations) {
      if (pronunciation.reading == value) return pronunciation;
    }
    return null;
  }

  String speechTextForReading(String value) {
    final ttsText = pronunciationForReading(value)?.ttsText.trim() ?? '';
    return ttsText.isEmpty ? value : ttsText;
  }

  /// Returns a pitch accent only when the catalog has one unambiguous value
  /// for [value]. Words with multiple accepted accents remain user-selectable.
  int? unambiguousPitchAccentForReading(String value) {
    final accents = pronunciationForReading(value)?.pitchAccents;
    return accents?.length == 1 ? accents!.single : null;
  }

  String get bookmarkKey => id;

  late final Set<ConjugationKind> _formKinds =
      Set<ConjugationKind>.unmodifiable(forms.map((form) => form.kind));

  Set<ConjugationKind> get formKinds => _formKinds;

  Set<ConjugationKind> get requiredFormKinds => switch (partOfSpeech) {
    WordPartOfSpeech.verb ||
    WordPartOfSpeech.verbalNoun => verbRequiredConjugations,
    WordPartOfSpeech.iAdjective => iAdjectiveRequiredConjugations,
    WordPartOfSpeech.naAdjective => naAdjectiveRequiredConjugations,
    _ => const <ConjugationKind>{},
  };

  Set<ConjugationKind> get missingRequiredFormKinds =>
      requiredFormKinds.difference(formKinds);

  bool matches(String query, {int scopeMask = vocabularySearchAllScopeMask}) =>
      matchesNormalized(normalizeVocabularySearch(query), scopeMask: scopeMask);

  bool matchesNormalized(
    String normalizedQuery, {
    int scopeMask = vocabularySearchAllScopeMask,
  }) => _searchIndex.matches(normalizedQuery, scopeMask: scopeMask);

  List<String> validate() {
    final errors = <String>[];
    if (!_kanaPattern.hasMatch(reading)) {
      errors.add('reading은 가나로만 작성해야 합니다: $reading');
    }
    final seenReadings = <String>{reading};
    for (final alternative in alternativeReadings) {
      if (!_kanaPattern.hasMatch(alternative)) {
        errors.add('alternativeReadings는 가나로만 작성해야 합니다: $alternative');
      }
      if (!seenReadings.add(alternative)) {
        errors.add('중복 읽기: $alternative');
      }
    }
    final availableReadings = readings.toSet();
    final seenPronunciationReadings = <String>{};
    for (final pronunciation in pronunciations) {
      errors.addAll(
        pronunciation.validate().map(
          (error) => '${pronunciation.reading}: $error',
        ),
      );
      if (!availableReadings.contains(pronunciation.reading)) {
        errors.add(
          'pronunciations 읽기는 기본 또는 대체 읽기여야 합니다: '
          '${pronunciation.reading}',
        );
      }
      if (!seenPronunciationReadings.add(pronunciation.reading)) {
        errors.add('중복 악센트 읽기: ${pronunciation.reading}');
      }
    }
    for (final meaning in meanings) {
      if (!_hangulPattern.hasMatch(meaning) || meaning.startsWith('영어 뜻 ·')) {
        errors.add('한국어 뜻이 필요합니다: $meaning');
      }
    }
    for (final usageNote in usageNotes) {
      if (!_hangulPattern.hasMatch(usageNote)) {
        errors.add('한국어 부연 설명이 필요합니다: $usageNote');
      }
    }
    final compatible = switch (partOfSpeech) {
      WordPartOfSpeech.verb ||
      WordPartOfSpeech.verbalNoun => conjugationClass.isVerb,
      WordPartOfSpeech.iAdjective =>
        conjugationClass == ConjugationClass.iAdjective,
      WordPartOfSpeech.naAdjective =>
        conjugationClass == ConjugationClass.naAdjective,
      _ => conjugationClass == ConjugationClass.none,
    };
    if (!compatible) {
      errors.add(
        '${partOfSpeech.labelKo}와 ${conjugationClass.labelKo} 조합이 올바르지 않습니다.',
      );
    }
    if (!isInflectable && forms.isNotEmpty) {
      errors.add('활용하지 않는 품사에 forms가 들어 있습니다.');
    }
    final missingFormKinds = missingRequiredFormKinds;
    if (missingFormKinds.isNotEmpty) {
      errors.add(
        '필수 활용형 누락: '
        '${missingFormKinds.map((kind) => kind.name).join(', ')}',
      );
    }
    final formKeys = <String>{};
    for (final form in forms) {
      errors.addAll(form.validate().map((error) => '${form.surface}: $error'));
      if (!formKeys.add('${form.kind.name}|${form.surface}')) {
        errors.add('중복 활용형: ${form.kind.name} ${form.surface}');
      }
    }
    final availableKinds = formKinds;
    for (final example in examples) {
      errors.addAll(example.validate().map((error) => '${example.id}: $error'));
      final kind = example.formKind;
      if (kind != null && !availableKinds.contains(kind)) {
        errors.add('${example.id}의 ${kind.name} 활용형이 forms에 없습니다.');
      }
    }
    return errors;
  }
}

class WordPronunciation {
  WordPronunciation({
    required this.reading,
    required Iterable<int> pitchAccents,
    this.ttsText = '',
  }) : pitchAccents = List<int>.unmodifiable(pitchAccents);

  factory WordPronunciation.fromJson(Map<String, dynamic> json) {
    return WordPronunciation(
      reading: _requiredString(json['reading'], 'pronunciation.reading'),
      pitchAccents: _intList(
        json['pitchAccents'],
        'pronunciation.pitchAccents',
      ),
      ttsText: _optionalString(json['ttsText'], 'pronunciation.ttsText'),
    );
  }

  final String reading;

  /// Tokyo-style pitch-accent downstep positions. `0` represents heiban.
  final List<int> pitchAccents;

  /// Optional lexical surface offered to the device TTS engine.
  ///
  /// Android does not expose a standard API for forcing Japanese lexical
  /// pitch accent, so this is only a pronunciation hint. Callers must fall
  /// back to [reading] when it is empty.
  final String ttsText;

  List<String> validate() {
    final errors = <String>[];
    if (!_kanaPattern.hasMatch(reading)) {
      errors.add('reading은 가나로만 작성해야 합니다: $reading');
    }
    if (pitchAccents.isEmpty) {
      errors.add('pitchAccents에는 하나 이상의 악센트 위치가 필요합니다.');
    }
    final moraCount = japaneseMoraCount(reading);
    final seenAccents = <int>{};
    for (final accent in pitchAccents) {
      if (accent < 0 || accent > moraCount) {
        errors.add('악센트 위치는 0부터 모라 수 $moraCount 사이여야 합니다: $accent');
      }
      if (!seenAccents.add(accent)) {
        errors.add('중복 악센트 위치: $accent');
      }
    }
    return errors;
  }
}

int japaneseMoraCount(String reading) {
  return japaneseMoras(reading).length;
}

List<String> japaneseMoras(String reading) {
  final moras = <String>[];
  for (final rune in reading.runes) {
    if (rune == 0x30FB) continue;
    final character = String.fromCharCode(rune);
    if (_smallMoraModifiers.contains(rune)) {
      if (moras.isNotEmpty) moras[moras.length - 1] += character;
    } else {
      moras.add(character);
    }
  }
  return List<String>.unmodifiable(moras);
}

const _smallMoraModifiers = <int>{
  0x3041, // ぁ
  0x3043, // ぃ
  0x3045, // ぅ
  0x3047, // ぇ
  0x3049, // ぉ
  0x3083, // ゃ
  0x3085, // ゅ
  0x3087, // ょ
  0x308E, // ゎ
  0x30A1, // ァ
  0x30A3, // ィ
  0x30A5, // ゥ
  0x30A7, // ェ
  0x30A9, // ォ
  0x30E3, // ャ
  0x30E5, // ュ
  0x30E7, // ョ
  0x30EE, // ヮ
};

class ConjugationForm {
  const ConjugationForm({
    required this.kind,
    required this.surface,
    required this.reading,
    this.note = '',
  });

  factory ConjugationForm.fromJson(Map<String, dynamic> json) {
    return ConjugationForm(
      kind: ConjugationKindX.parse(json['kind']),
      surface: _requiredString(json['surface'], 'surface'),
      reading: _requiredString(json['reading'], 'reading'),
      note: _optionalString(json['note'], 'note'),
    );
  }

  final ConjugationKind kind;
  final String surface;
  final String reading;
  final String note;

  List<String> validate() => [
    if (!_kanaPattern.hasMatch(reading)) 'reading은 가나로만 작성해야 합니다: $reading',
  ];
}

List<ConjugationForm> _withConditionalNara({
  required String lemma,
  required String reading,
  required WordPartOfSpeech partOfSpeech,
  required Iterable<ConjugationForm> forms,
}) {
  final values = List<ConjugationForm>.of(forms);
  final supportsNara = switch (partOfSpeech) {
    WordPartOfSpeech.verb ||
    WordPartOfSpeech.verbalNoun ||
    WordPartOfSpeech.iAdjective ||
    WordPartOfSpeech.naAdjective => true,
    _ => false,
  };
  if (!supportsNara ||
      values.any((form) => form.kind == ConjugationKind.conditionalNara)) {
    return List<ConjugationForm>.unmodifiable(values);
  }

  String baseSurface;
  String baseReading;
  if (partOfSpeech == WordPartOfSpeech.naAdjective) {
    baseSurface = lemma;
    baseReading = reading;
  } else {
    ConjugationForm? reasonForm;
    for (final form in values) {
      if (form.kind == ConjugationKind.reasonKara) {
        reasonForm = form;
        break;
      }
    }
    if (reasonForm != null &&
        reasonForm.surface.endsWith('から') &&
        reasonForm.reading.endsWith('から')) {
      baseSurface = reasonForm.surface.substring(
        0,
        reasonForm.surface.length - 2,
      );
      baseReading = reasonForm.reading.substring(
        0,
        reasonForm.reading.length - 2,
      );
    } else if (partOfSpeech == WordPartOfSpeech.verbalNoun &&
        !lemma.endsWith('する')) {
      baseSurface = '$lemmaする';
      baseReading = '$readingする';
    } else {
      baseSurface = lemma;
      baseReading = reading;
    }
  }

  final nara = ConjugationForm(
    kind: ConjugationKind.conditionalNara,
    surface: '$baseSurfaceなら',
    reading: '$baseReadingなら',
  );
  final taraIndex = values.lastIndexWhere(
    (form) => form.kind == ConjugationKind.conditionalTara,
  );
  values.insert(taraIndex < 0 ? values.length : taraIndex + 1, nara);
  return List<ConjugationForm>.unmodifiable(values);
}

class ExampleSentence {
  const ExampleSentence({
    required this.id,
    required this.original,
    required this.ruby,
    required this.literalTranslation,
    required this.naturalTranslation,
    required this.focusSurface,
    this.formKind,
    this.note = '',
  });

  factory ExampleSentence.fromJson(Map<String, dynamic> json) {
    final rawKind = json['formKind'];
    return ExampleSentence(
      id: _requiredString(json['id'], 'example.id'),
      original: _requiredString(json['original'], 'example.original'),
      ruby: _requiredString(json['ruby'], 'example.ruby'),
      literalTranslation: _requiredString(
        json['literalTranslation'],
        'example.literalTranslation',
      ),
      naturalTranslation: _requiredString(
        json['naturalTranslation'],
        'example.naturalTranslation',
      ),
      focusSurface: _requiredString(
        json['focusSurface'],
        'example.focusSurface',
      ),
      formKind: rawKind == null ? null : ConjugationKindX.parse(rawKind),
      note: _optionalString(json['note'], 'example.note'),
    );
  }

  final String id;
  final String original;
  final String ruby;
  final String literalTranslation;
  final String naturalTranslation;
  final String focusSurface;
  final ConjugationKind? formKind;
  final String note;

  List<String> validate() => [
    if (!original.contains(focusSurface))
      'focusSurface가 원문에 없습니다: $focusSurface',
    if (stripAozoraRuby(ruby) != original)
      'ruby에서 후리가나를 제거한 문장이 original과 다릅니다.',
    if (_kanjiPattern.hasMatch(original) && !ruby.contains('《'))
      '한자가 있는 예문에는 후리가나가 필요합니다: $original',
    if (!_isKoreanTranslation(literalTranslation))
      '한국어 직역이 필요합니다: $literalTranslation',
    if (!_isKoreanTranslation(naturalTranslation))
      '한국어 의역이 필요합니다: $naturalTranslation',
  ];
}

final RegExp _kanaPattern = RegExp(r'^[ぁ-ゖァ-ヺー・]+$');
final RegExp _hangulPattern = RegExp(r'[가-힣]');
final RegExp _kanjiPattern = RegExp(r'[一-龯々〆ヶ]');
final RegExp _aozoraRubyPattern = RegExp(r'｜([^《]+)《([^》]+)》');
const _translationControlTokens = ['뜻 참고 ·', '영어 뜻 ·', '<unk>', '⁇'];

bool _isKoreanTranslation(String value) =>
    _hangulPattern.hasMatch(value) &&
    !_translationControlTokens.any(value.contains);

String stripAozoraRuby(String source) =>
    source.replaceAllMapped(_aozoraRubyPattern, (match) => match.group(1)!);

/// Resolves Aozora ruby to the exact kana reading used for Japanese TTS.
String spokenAozoraRuby(String source) =>
    source.replaceAllMapped(_aozoraRubyPattern, (match) => match.group(2)!);

String normalizeVocabularySearch(String source) {
  final buffer = StringBuffer();
  _appendNormalizedVocabularySearch(buffer, source);
  return buffer.toString();
}

_VocabularySearchIndex _buildNormalizedWordSearchIndex({
  required String lemma,
  required String reading,
  required List<String> meanings,
  required List<ConjugationForm> forms,
  required List<ExampleSentence> examples,
  required List<String> alternativeReadings,
  required List<String> alternativeSpellings,
  required List<String> usageNotes,
  required String note,
}) {
  final buffer = StringBuffer();
  var hasField = false;

  void addField(String value) {
    if (hasField) buffer.write(_searchFieldSeparator);
    hasField = true;
    _appendNormalizedVocabularySearch(buffer, value);
  }

  final lemmaStart = buffer.length;
  addField(lemma);
  alternativeSpellings.forEach(addField);
  for (final form in forms) {
    addField(form.surface);
  }
  final lemmaEnd = buffer.length;

  final readingStart = buffer.length;
  addField(reading);
  alternativeReadings.forEach(addField);
  for (final form in forms) {
    addField(form.reading);
  }
  final readingEnd = buffer.length;

  final meaningStart = buffer.length;
  meanings.forEach(addField);
  usageNotes.forEach(addField);
  if (note.isNotEmpty) addField(note);
  for (final form in forms) {
    addField(form.kind.labelKo);
    addField(form.note);
  }
  final meaningEnd = buffer.length;

  final exampleStart = buffer.length;
  for (final example in examples) {
    addField(example.original);
    addField(example.ruby);
    addField(example.literalTranslation);
    addField(example.naturalTranslation);
    addField(example.focusSurface);
  }
  final exampleEnd = buffer.length;
  return _VocabularySearchIndex(
    text: buffer.toString(),
    lemmaStart: lemmaStart,
    lemmaEnd: lemmaEnd,
    readingStart: readingStart,
    readingEnd: readingEnd,
    meaningStart: meaningStart,
    meaningEnd: meaningEnd,
    exampleStart: exampleStart,
    exampleEnd: exampleEnd,
  );
}

class _VocabularySearchIndex {
  const _VocabularySearchIndex({
    required this.text,
    required this.lemmaStart,
    required this.lemmaEnd,
    required this.readingStart,
    required this.readingEnd,
    required this.meaningStart,
    required this.meaningEnd,
    required this.exampleStart,
    required this.exampleEnd,
  });

  final String text;
  final int lemmaStart;
  final int lemmaEnd;
  final int readingStart;
  final int readingEnd;
  final int meaningStart;
  final int meaningEnd;
  final int exampleStart;
  final int exampleEnd;

  bool matches(String query, {required int scopeMask}) {
    if (query.isEmpty) return true;
    if (scopeMask == vocabularySearchAllScopeMask) return text.contains(query);
    return ((scopeMask & VocabularySearchScope.lemma.mask) != 0 &&
            _containsInRange(query, lemmaStart, lemmaEnd)) ||
        ((scopeMask & VocabularySearchScope.reading.mask) != 0 &&
            _containsInRange(query, readingStart, readingEnd)) ||
        ((scopeMask & VocabularySearchScope.meaning.mask) != 0 &&
            _containsInRange(query, meaningStart, meaningEnd)) ||
        ((scopeMask & VocabularySearchScope.example.mask) != 0 &&
            _containsInRange(query, exampleStart, exampleEnd));
  }

  bool _containsInRange(String query, int start, int end) {
    final match = text.indexOf(query, start);
    return match >= start && match + query.length <= end;
  }
}

const _searchFieldSeparator = '\u0000';

void _appendNormalizedVocabularySearch(StringBuffer buffer, String source) {
  // Removing whitespace makes a separate trim pass unnecessary. Checking the
  // rune directly also avoids allocating a one-character String and running a
  // RegExp for every character in all search documents during startup.
  for (final rune in source.toLowerCase().runes) {
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else if (!_isSearchWhitespaceRune(rune)) {
      buffer.writeCharCode(rune);
    }
  }
}

bool _isSearchWhitespaceRune(int rune) =>
    (rune >= 0x0009 && rune <= 0x000D) ||
    rune == 0x0020 ||
    rune == 0x0085 ||
    rune == 0x00A0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000 ||
    rune == 0xFEFF;

final _jlptLevelByName = <String, JlptLevel>{
  for (final value in JlptLevel.values) value.name: value,
};
final _partOfSpeechByName = <String, WordPartOfSpeech>{
  for (final value in WordPartOfSpeech.values) value.name: value,
};
final _conjugationClassByName = <String, ConjugationClass>{
  for (final value in ConjugationClass.values) value.name: value,
};
final _conjugationKindByName = <String, ConjugationKind>{
  for (final value in ConjugationKind.values) value.name: value,
};

T _enumByName<T extends Enum>(
  Map<String, T> values,
  String name,
  String field,
) {
  final value = values[name];
  if (value != null) return value;
  throw FormatException('$field 값이 올바르지 않습니다: $name');
}

String _requiredString(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field 값은 비어 있지 않은 문자열이어야 합니다.');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw FormatException('$field 값은 비어 있지 않은 문자열이어야 합니다.');
  }
  return trimmed;
}

String _optionalString(Object? value, String field) {
  if (value == null) return '';
  if (value is! String) {
    throw FormatException('$field 값은 문자열이어야 합니다.');
  }
  return value.trim();
}

Iterable<String> _stringList(Object? value, String field) sync* {
  if (value is! List) {
    throw FormatException('$field 값은 문자열 배열이어야 합니다.');
  }
  for (final item in value) {
    yield _requiredString(item, '$field 항목');
  }
}

Iterable<int> _intList(Object? value, String field) sync* {
  if (value is! List) {
    throw FormatException('$field 값은 정수 배열이어야 합니다.');
  }
  for (final item in value) {
    if (item is! int) {
      throw FormatException('$field 항목은 정수여야 합니다.');
    }
    yield item;
  }
}

Iterable<Map<String, dynamic>> _objectList(Object? value, String field) sync* {
  if (value is! List) {
    throw FormatException('$field 값은 객체 배열이어야 합니다.');
  }
  for (final item in value) {
    if (item is Map<String, dynamic>) {
      // jsonDecode already creates string-keyed maps. Reusing them avoids
      // copying every word, example, and conjugation object.
      yield item;
    } else if (item is Map) {
      yield Map<String, dynamic>.from(item);
    } else {
      throw FormatException('$field 항목은 객체여야 합니다.');
    }
  }
}
