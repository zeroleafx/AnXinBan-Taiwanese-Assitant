import 'dart:math';

import 'voice_command.dart';

class ContactEntry {
  const ContactEntry({
    required this.name,
    required this.numbers,
    this.nickname,
  });

  final String name;
  final String? nickname;
  final List<String> numbers;

  String get number => numbers.first;
}

/// Contacts that best match a spoken name, best first.
///
/// More than one result means the names tie and the person should pick.
List<ContactEntry> matchContacts(
  String spoken,
  Iterable<ContactEntry> contacts, {
  int limit = 5,
}) {
  final query = normalizeTranscript(spoken);
  if (query.isEmpty) return const [];
  final asked = {query: 0, for (final word in _sameAs[query] ?? const []) word: 10};
  final scored = <(int, ContactEntry)>[];
  for (final contact in contacts) {
    if (contact.numbers.isEmpty) continue;
    var best = 0;
    for (final label in [contact.name, ?contact.nickname]) {
      final name = normalizeTranscript(label);
      if (name.isEmpty) continue;
      for (final MapEntry(key: word, value: penalty) in asked.entries) {
        final score = _score(word, name);
        if (score > 0) best = max(best, score - penalty);
      }
    }
    if (best > 0) scored.add((best, contact));
  }
  if (scored.isEmpty) return const [];
  final top = scored.map((entry) => entry.$1).reduce(max);
  final winners = [
    for (final (score, contact) in scored)
      if (score == top) contact,
  ]..sort((a, b) => a.name.length.compareTo(b.name.length));
  return winners.take(limit).toList();
}

int _score(String query, String name) {
  if (name == query) return 100;
  if (name.contains(query) || (name.length >= 2 && query.contains(name))) {
    return 80;
  }
  final core = _core(query);
  if (core != query && (name.contains(core) || _core(name) == core)) return 60;
  return 0;
}

/// "阿明" and "明哥" both come down to "明".
String _core(String name) {
  var core = name;
  for (final prefix in const ['阿', '小', '老']) {
    if (core.length > prefix.length && core.startsWith(prefix)) {
      core = core.substring(prefix.length);
      break;
    }
  }
  for (final suffix in _titles) {
    if (core.length > suffix.length && core.endsWith(suffix)) {
      return core.substring(0, core.length - suffix.length);
    }
  }
  return core;
}

const _titles = [
  '先生', '小姐', '太太', '女士', '老師', '醫生', '哥哥', '姊姊', '姐姐', //
  '阿姨', '伯伯', '叔叔', '哥', '姊', '姐', '仔', '伯', '叔', '姨', '嬸',
];

/// Family words Breeze may write differently from how they are saved.
const _sameAs = {
  '阿母': ['媽媽', '老媽', '母親', '媽'],
  '媽媽': ['阿母', '老媽', '母親', '媽'],
  '阿爸': ['爸爸', '老爸', '父親', '爸'],
  '爸爸': ['阿爸', '老爸', '父親', '爸'],
  '後生': ['兒子'],
  '兒子': ['後生'],
  '查某囝': ['女兒'],
  '女兒': ['查某囝'],
  '阿公': ['爺爺', '外公'],
  '阿嬤': ['奶奶', '外婆'],
  '牽手': ['老婆', '太太', '老公', '先生'],
};
