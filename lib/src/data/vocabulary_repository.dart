import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/vocabulary.dart';

class VocabularyRepository {
  const VocabularyRepository({AssetBundle? assetBundle})
    : _assetBundle = assetBundle;

  static const assetPaths = <String>[
    'assets/data/n5.json',
    'assets/data/n4.json',
    'assets/data/n3.json',
    'assets/data/n2.json',
    'assets/data/n1.json',
  ];
  static const directConversationExamplesAssetPath =
      'assets/data/direct_conversation_examples.json';
  static const _assetLevels = <JlptLevel>[
    JlptLevel.n5,
    JlptLevel.n4,
    JlptLevel.n3,
    JlptLevel.n2,
    JlptLevel.n1,
  ];

  final AssetBundle? _assetBundle;

  AssetBundle get _bundle => _assetBundle ?? rootBundle;

  _VocabularyRepositoryCache get _cache => _assetBundle == null
      ? _defaultRepositoryCache
      : _repositoryCaches[this] ??= _VocabularyRepositoryCache();

  Future<List<VocabularyPack>> loadPacks() {
    final cache = _cache;
    return cache.packs ??= _loadPacksMemoized(cache);
  }

  Future<List<VocabularyPack>> _loadPacksMemoized(
    _VocabularyRepositoryCache cache,
  ) async {
    try {
      return await _loadPacksUncached();
    } catch (_) {
      cache.packs = null;
      cache.allWords = null;
      rethrow;
    }
  }

  Future<List<VocabularyPack>> _loadPacksUncached() async {
    final sources = await Future.wait<String>([
      for (final assetPath in assetPaths) _bundle.loadString(assetPath),
      _bundle.loadString(directConversationExamplesAssetPath),
    ]);
    // JSON decoding, model construction, search-document normalization, and
    // debug validation are the expensive part of loading vocabulary. Keep
    // them off the animation/UI isolate while retaining parallel asset reads.
    return compute(
      _parseVocabularyPacks,
      _VocabularyParseRequest(
        assetPaths,
        _assetLevels,
        sources.take(assetPaths.length).toList(growable: false),
        sources[assetPaths.length],
      ),
      debugLabel: '별빛 단어 어휘 파싱',
    );
  }

  Future<List<JapaneseWord>> loadAll() {
    final cache = _cache;
    return cache.allWords ??= _loadAllMemoized(cache);
  }

  Future<List<JapaneseWord>> _loadAllMemoized(
    _VocabularyRepositoryCache cache,
  ) async {
    try {
      final packs = await loadPacks();
      return List.unmodifiable(packs.expand((pack) => pack.words));
    } catch (_) {
      cache.allWords = null;
      rethrow;
    }
  }

  Future<List<JapaneseWord>> loadLevel(JlptLevel level) async {
    final packs = await loadPacks();
    return packs.singleWhere((pack) => pack.level == level).words;
  }

  Future<List<JapaneseWord>> search(String query) async {
    return searchIn(await loadAll(), query);
  }

  List<JapaneseWord> searchIn(Iterable<JapaneseWord> words, String query) {
    final normalized = normalizeVocabularySearch(query);
    if (normalized.isEmpty) return List.unmodifiable(words);
    return List.unmodifiable(
      words.where((word) => word.matchesNormalized(normalized)),
    );
  }
}

List<VocabularyPack> _parseVocabularyPacks(_VocabularyParseRequest request) {
  final directExamples = _parseDirectConversationExamples(
    request.directConversationExamplesSource,
    assetPath: VocabularyRepository.directConversationExamplesAssetPath,
    idSuffix: 'e2',
    note: '직접 작성 · 회화 예문',
  );
  final packs = <VocabularyPack>[];
  final ids = <String>{};
  for (var index = 0; index < request.paths.length; index++) {
    final assetPath = request.paths[index];
    late final VocabularyPack pack;
    try {
      final decoded = jsonDecode(request.sources[index]);
      if (decoded is! Map) {
        throw const FormatException('최상위 JSON 값은 객체여야 합니다.');
      }
      pack = VocabularyPack.fromJson(
        decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded),
        assetPath: assetPath,
      );
    } on FormatException catch (error) {
      throw FormatException('$assetPath: ${error.message}');
    }

    final expectedLevel = request.levels[index];
    if (pack.level != expectedLevel) {
      throw FormatException(
        '$assetPath 레벨이 ${expectedLevel.label}이 아니라 '
        '${pack.level.label}입니다.',
      );
    }
    final enrichedWords = <JapaneseWord>[];
    for (final baseWord in pack.words) {
      final word = baseWord.withAdditionalExamples([
        ...(directExamples.remove(baseWord.id) ?? const <ExampleSentence>[]),
      ]);
      if (!ids.add(word.id)) {
        throw FormatException('중복 단어 ID입니다: ${word.id}');
      }
      // Bundled assets are exhaustively validated by the repository tests.
      // Release startup still performs all structural parsing above; only the
      // expensive semantic audit of immutable, shipped data is debug-only.
      if (kDebugMode) {
        final errors = word.validate();
        if (errors.isNotEmpty) {
          throw FormatException('${word.id}: ${errors.join(' / ')}');
        }
      }
      enrichedWords.add(word);
    }
    packs.add(
      VocabularyPack(
        schemaVersion: pack.schemaVersion,
        level: pack.level,
        assetPath: pack.assetPath,
        words: List<JapaneseWord>.unmodifiable(enrichedWords),
      ),
    );
  }
  if (directExamples.isNotEmpty) {
    throw FormatException(
      '추가 회화 예문의 단어 ID가 카탈로그에 없습니다: '
      '${directExamples.keys.take(5).join(', ')}',
    );
  }
  return List<VocabularyPack>.unmodifiable(packs);
}

Map<String, List<ExampleSentence>> _parseDirectConversationExamples(
  String source, {
  required String assetPath,
  required String idSuffix,
  required String note,
}) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('$assetPath: ${error.message}');
  }
  if (decoded is! Map || decoded['schemaVersion'] != 1) {
    throw const FormatException('추가 회화 예문 스키마가 올바르지 않습니다.');
  }
  final rawExamples = decoded['examplesByWordId'];
  if (rawExamples is! Map) {
    throw const FormatException('examplesByWordId는 객체여야 합니다.');
  }
  final result = <String, List<ExampleSentence>>{};
  for (final entry in rawExamples.entries) {
    final wordId = entry.key;
    final fields = entry.value;
    if (wordId is! String || wordId.trim().isEmpty) {
      throw const FormatException('추가 회화 예문의 단어 ID가 올바르지 않습니다.');
    }
    if (fields is! List ||
        fields.length != 5 ||
        fields.any((field) => field is! String || field.trim().isEmpty)) {
      throw FormatException('$wordId 추가 회화 예문은 문자열 5개여야 합니다.');
    }
    result[wordId] = <ExampleSentence>[
      ExampleSentence(
        id: '$wordId-$idSuffix',
        original: fields[0] as String,
        ruby: fields[1] as String,
        focusSurface: fields[2] as String,
        literalTranslation: fields[3] as String,
        naturalTranslation: fields[4] as String,
        note: note,
      ),
    ];
  }
  return result;
}

class _VocabularyParseRequest {
  const _VocabularyParseRequest(
    this.paths,
    this.levels,
    this.sources,
    this.directConversationExamplesSource,
  );

  final List<String> paths;
  final List<JlptLevel> levels;
  final List<String> sources;
  final String directConversationExamplesSource;
}

final Expando<_VocabularyRepositoryCache> _repositoryCaches =
    Expando<_VocabularyRepositoryCache>('VocabularyRepository.cache');
final _defaultRepositoryCache = _VocabularyRepositoryCache();

class _VocabularyRepositoryCache {
  Future<List<VocabularyPack>>? packs;
  Future<List<JapaneseWord>>? allWords;
}
