/// Normalizes a Japanese reading for learner-friendly gojuon ordering.
///
/// Katakana, small kana, voiced kana, and prolonged sound marks are folded so
/// the same ordering can be reused by the wordbook and native-surface deck.
String gojuonSortKey(String value) {
  final hiragana = String.fromCharCodes(
    value.runes.map(
      (rune) => rune >= 0x30A1 && rune <= 0x30F6 ? rune - 0x60 : rune,
    ),
  );
  final normalized = hiragana
      .replaceAll('ぁ', 'あ')
      .replaceAll('ぃ', 'い')
      .replaceAll('ぅ', 'う')
      .replaceAll('ぇ', 'え')
      .replaceAll('ぉ', 'お')
      .replaceAll('っ', 'つ')
      .replaceAll('ゃ', 'や')
      .replaceAll('ゅ', 'ゆ')
      .replaceAll('ょ', 'よ')
      .replaceAll('ゎ', 'わ')
      .replaceAll('ゕ', 'か')
      .replaceAll('ゖ', 'け')
      .replaceAll('が', 'か')
      .replaceAll('ぎ', 'き')
      .replaceAll('ぐ', 'く')
      .replaceAll('げ', 'け')
      .replaceAll('ご', 'こ')
      .replaceAll('ざ', 'さ')
      .replaceAll('じ', 'し')
      .replaceAll('ず', 'す')
      .replaceAll('ぜ', 'せ')
      .replaceAll('ぞ', 'そ')
      .replaceAll('だ', 'た')
      .replaceAll('ぢ', 'ち')
      .replaceAll('づ', 'つ')
      .replaceAll('で', 'て')
      .replaceAll('ど', 'と')
      .replaceAll('ば', 'は')
      .replaceAll('び', 'ひ')
      .replaceAll('ぶ', 'ふ')
      .replaceAll('べ', 'へ')
      .replaceAll('ぼ', 'ほ')
      .replaceAll('ぱ', 'は')
      .replaceAll('ぴ', 'ひ')
      .replaceAll('ぷ', 'ふ')
      .replaceAll('ぺ', 'へ')
      .replaceAll('ぽ', 'ほ')
      .replaceAll('ゔ', 'う');
  final buffer = StringBuffer();
  var previous = '';
  for (final rune in normalized.runes) {
    final character = String.fromCharCode(rune);
    if (character == 'ー') {
      final vowel = _vowelForKana(previous);
      if (vowel.isNotEmpty) buffer.write(vowel);
      continue;
    }
    buffer.write(character);
    previous = character;
  }
  return buffer.toString();
}

/// A deterministic, process-independent key for stable shuffled word decks.
int stableWordOrderKey(String id, int seed) {
  var hash = 0x811c9dc5 ^ seed;
  for (final rune in id.runes) {
    hash ^= rune;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

String _vowelForKana(String kana) {
  if ('あかがさざただなはばぱまやらわ'.contains(kana)) return 'あ';
  if ('いきぎしじちぢにひびぴみり'.contains(kana)) return 'い';
  if ('うくぐすずつづぬふぶぷむゆる'.contains(kana)) return 'う';
  if ('えけげせぜてでねへべぺめれ'.contains(kana)) return 'え';
  if ('おこごそぞとどのほぼぽもよろを'.contains(kana)) return 'お';
  return '';
}
