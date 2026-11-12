import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/contact_matcher.dart';

ContactEntry person(String name, {String? nickname, String number = '0912'}) =>
    ContactEntry(name: name, nickname: nickname, numbers: [number]);

List<String> names(List<ContactEntry> contacts) => [
  for (final contact in contacts) contact.name,
];

void main() {
  final book = [
    person('阿明'),
    person('王小明'),
    person('媽媽'),
    person('陳志明'),
    person('女兒小美'),
    person('李大華', nickname: '華哥'),
    const ContactEntry(name: '沒有電話', numbers: []),
  ];

  test('an exact name wins over partial matches', () {
    expect(names(matchContacts('阿明', book)), ['阿明']);
  });

  test('a shortened name offers every close match to choose from', () {
    final others = book.where((c) => c.name != '阿明');
    expect(names(matchContacts('阿明', others)), ['王小明', '陳志明']);
  });

  test('family words match how the contact was saved', () {
    expect(names(matchContacts('阿母', book)), ['媽媽']);
    expect(names(matchContacts('女兒', book)), ['女兒小美']);
  });

  test('nicknames and titles are understood', () {
    expect(names(matchContacts('華哥', book)), ['李大華']);
    expect(names(matchContacts('王小明先生', book)), ['王小明']);
  });

  test('contacts without a phone number are never offered', () {
    expect(matchContacts('沒有電話', book), isEmpty);
    expect(matchContacts('不存在的人', book), isEmpty);
    expect(matchContacts('', book), isEmpty);
  });
}
