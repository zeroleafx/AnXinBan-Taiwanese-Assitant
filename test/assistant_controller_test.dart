import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/phone_actions.dart';
import 'package:an_xin_ban/voice_command.dart';

class FakePhone implements PhoneActions {
  final installed = {PhoneApp.line, PhoneApp.maps};
  bool contactsAllowed = true;
  List<ContactEntry> contacts = const [
    ContactEntry(name: '阿明', numbers: ['0912 345 678']),
    ContactEntry(name: '王小明', numbers: ['0922']),
    ContactEntry(name: '陳志明', numbers: ['0933']),
  ];
  final opened = <PhoneApp>[];
  final dialed = <String>[];
  final places = <String>[];
  final searches = <String>[];
  bool? torch;
  int settingsOpened = 0;

  @override
  Future<bool> openApp(PhoneApp app) async {
    opened.add(app);
    return installed.contains(app);
  }

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    return true;
  }

  @override
  Future<ContactsAccess> loadContacts() async => contactsAllowed
      ? ContactsAccess.granted(contacts)
      : const ContactsAccess.denied();

  @override
  Future<bool> setTorch({required bool on}) async {
    torch = on;
    return true;
  }

  @override
  Future<bool> navigate(String place) async {
    places.add(place);
    return true;
  }

  @override
  Future<bool> searchVideo(String query) async {
    searches.add(query);
    return true;
  }

  @override
  Future<bool> searchWeb(String query) async {
    searches.add(query);
    return true;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  late FakePhone phone;
  late AssistantController assistant;
  setUp(() {
    phone = FakePhone();
    assistant = AssistantController(
      phone,
      now: () => DateTime(2026, 11, 10, 15, 5),
    );
  });
  tearDown(() => assistant.dispose());

  test('"幫我開 LINE" really opens LINE', () async {
    await assistant.handle('幫我開LINE');
    expect(phone.opened, [PhoneApp.line]);
    expect(assistant.outcome!.tone, OutcomeTone.done);
    expect(assistant.outcome!.title, '已打開 LINE');
    expect(assistant.outcome!.heard, '幫我開LINE');
    expect(assistant.working, false);
  });

  test('a missing app is reported instead of failing silently', () async {
    await assistant.handle('開YouTube');
    expect(assistant.outcome!.tone, OutcomeTone.problem);
    expect(assistant.outcome!.title, '手機裡找不到 YouTube');
  });

  test('calling a unique contact dials their number', () async {
    phone.contacts = phone.contacts.take(1).toList();
    await assistant.handle('打電話給阿明');
    expect(phone.dialed, ['0912 345 678']);
    expect(assistant.outcome!.title, '打給 阿明');
  });

  test('a name with several matches asks which one, then calls it', () async {
    phone.contacts = phone.contacts.skip(1).toList();
    await assistant.handle('打給阿明');
    expect(phone.dialed, isEmpty);
    expect(names(assistant.outcome!.choices), ['王小明', '陳志明']);

    await assistant.call(assistant.outcome!.choices.last);
    expect(phone.dialed, ['0933']);
    expect(assistant.outcome!.title, '打給 陳志明');
    expect(assistant.outcome!.choices, isEmpty);
  });

  test('without contacts permission it offers the settings button', () async {
    phone.contactsAllowed = false;
    await assistant.handle('打給阿明');
    expect(assistant.outcome!.action, OutcomeAction.openSettings);
    await assistant.runAction(OutcomeAction.openSettings);
    expect(phone.settingsOpened, 1);
  });

  test('spoken numbers are dialed directly', () async {
    await assistant.handle('撥一一九');
    expect(phone.dialed, ['119']);
  });

  test('flashlight turns on with a one-tap off button', () async {
    await assistant.handle('開手電筒');
    expect(phone.torch, true);
    expect(assistant.outcome!.action, OutcomeAction.torchOff);

    await assistant.runAction(OutcomeAction.torchOff);
    expect(phone.torch, false);
    expect(assistant.outcome!.title, '手電筒關了');
    expect(assistant.outcome!.action, isNull);
  });

  test('a short "關掉" after switching on turns the light off', () async {
    await assistant.handle('開手電筒');
    expect(assistant.torchOn, true);
    assistant.clear();

    await assistant.handle('關掉');
    expect(phone.torch, false);
    expect(assistant.torchOn, false);
    expect(assistant.outcome!.title, '手電筒關了');

    // With the light off, "關掉" alone means nothing yet.
    await assistant.handle('關掉');
    expect(assistant.outcome!.title, '這句我還不會');
  });

  test('saying just "手電筒" switches it over', () async {
    await assistant.handle('手電筒');
    expect(phone.torch, true);
    await assistant.handle('手電筒');
    expect(phone.torch, false);
  });

  test('navigation, songs and weather open the right place', () async {
    await assistant.handle('帶我去台北車站');
    expect(phone.places, ['台北車站']);
    await assistant.handle('我想聽鄧麗君的歌');
    await assistant.handle('今天會下雨嗎');
    expect(phone.searches, ['鄧麗君的歌', '今天天氣']);
  });

  test('time and date are answered on screen', () async {
    await assistant.handle('現在幾點');
    expect(assistant.outcome!.title, '現在是下午 3:05');
    await assistant.handle('今天禮拜幾');
    expect(assistant.outcome!.title, '今天 11 月 10 日');
    expect(assistant.outcome!.detail, '星期二');
  });

  test('unknown requests explain what can be said', () async {
    await assistant.handle('今天心情不錯');
    expect(assistant.outcome!.title, '這句我還不會');
    assistant.clear();
    expect(assistant.outcome, isNull);
  });
}

List<String> names(List<ContactEntry> contacts) => [
  for (final contact in contacts) contact.name,
];
