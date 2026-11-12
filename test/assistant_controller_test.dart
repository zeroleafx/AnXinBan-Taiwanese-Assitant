import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/emergency_store.dart';
import 'package:an_xin_ban/place.dart';
import 'package:an_xin_ban/voice_command.dart';

import 'support/fake_phone.dart';

const daughter = ContactEntry(name: '女兒', numbers: ['0911-111-111']);

void main() {
  late FakePhone phone;
  late MemoryEmergencyStore store;
  late AssistantController assistant;

  AssistantOutcome shown() => assistant.outcome!;
  List<String> buttons() => [for (final b in shown().buttons) b.label];
  Future<void> tap(String label) =>
      assistant.press(shown().buttons.singleWhere((b) => b.label == label));

  setUp(() {
    phone = FakePhone()
      ..contacts = const [
        ContactEntry(name: '阿明', numbers: ['0912 345 678']),
        ContactEntry(name: '王小明', numbers: ['0922']),
        ContactEntry(name: '陳志明', numbers: ['0933']),
      ];
    store = MemoryEmergencyStore();
    assistant = AssistantController(
      phone,
      store: store,
      now: () => DateTime(2026, 11, 10, 15, 5),
    );
  });
  tearDown(() => assistant.dispose());

  group('apps', () {
    test('"幫我開 LINE" really opens LINE', () async {
      await assistant.handle('幫我開LINE');
      expect(phone.opened, [PhoneApp.line]);
      expect(shown().tone, OutcomeTone.done);
      expect(shown().title, '已打開 LINE');
      expect(shown().heard, '幫我開LINE');
      expect(assistant.working, false);
    });

    test('a missing app is reported instead of failing silently', () async {
      await assistant.handle('開YouTube');
      expect(shown().tone, OutcomeTone.problem);
      expect(shown().title, '手機裡找不到 YouTube');
    });

    test('any installed app opens by its name', () async {
      await assistant.handle('打開相機');
      expect(phone.openedNamed, ['相機']);
      expect(shown().title, '已打開相機');

      await assistant.handle('幫我打開 Instagram');
      expect(shown().title, '已打開 Instagram');
    });

    test('an app that is not there is named in the answer', () async {
      await assistant.handle('打開股票');
      expect(shown().tone, OutcomeTone.problem);
      expect(shown().title, '找不到「股票」');
    });

    test('"開冷氣" is not treated as a missing app', () async {
      await assistant.handle('開冷氣');
      expect(shown().title, '這句我還不會');
      expect(shown().showExamples, true);
    });
  });

  group('calls', () {
    test('calling a unique contact dials their number', () async {
      phone.contacts = phone.contacts.take(1).toList();
      await assistant.handle('打電話給阿明');
      expect(phone.dialed, ['0912 345 678']);
      expect(shown().title, '打給 阿明');
    });

    test('several matches ask which one, then call it', () async {
      phone.contacts = phone.contacts.skip(1).toList();
      await assistant.handle('打給阿明');
      expect(phone.dialed, isEmpty);
      expect(shown().title, '要打給哪一位？');
      expect(names(shown().choices), ['王小明', '陳志明']);

      await assistant.choose(shown().choices.last);
      expect(phone.dialed, ['0933']);
      expect(shown().title, '打給 陳志明');
      expect(shown().choices, isEmpty);
    });

    test('without contacts permission it offers the settings', () async {
      phone.contactsAllowed = false;
      await assistant.handle('打給阿明');
      expect(buttons(), ['打開設定']);
      await tap('打開設定');
      expect(phone.settingsOpened, 1);
      expect(shown().title, '需要通訊錄權限', reason: 'the card stays');
    });

    test('spoken numbers and emergency services are dialed', () async {
      await assistant.handle('撥一一九');
      await assistant.handle('叫救護車');
      await assistant.handle('幫我報警');
      expect(phone.dialed, ['119', '119', '110']);
    });
  });

  group('where am I', () {
    test('shows the address and opens the map', () async {
      await assistant.handle('我在哪裡');
      expect(shown().title, '你在這裡');
      expect(shown().detail, '彰化縣彰化市中山路三段185巷16號');
      expect(buttons(), ['打開地圖']);

      await tap('打開地圖');
      expect(phone.maps.single.latitude, 24.08123);
      expect(shown().title, '你在這裡', reason: 'the card stays');
    });

    test('offers to send it to the emergency contact', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('我在哪裡');
      expect(buttons(), ['打開地圖', '傳給 女兒']);

      await tap('傳給 女兒');
      final (number, body) = phone.texts.single;
      expect(number, '0911-111-111');
      expect(body, contains('彰化縣彰化市中山路三段185巷16號'));
      expect(body, contains('query=24.08123,120.55861'));
      expect(shown().title, '把位置傳給 女兒');
    });

    test('without an address it shows the coordinates', () async {
      phone.location = const LocationFound(
        Place(latitude: 24.08123, longitude: 120.55861),
      );
      await assistant.handle('我在哪裡');
      expect(shown().detail, '24.0812, 120.5586');
    });

    test('explains what is missing when the location is unavailable', () async {
      phone.location = const LocationDenied();
      await assistant.handle('我在哪裡');
      expect(shown().title, '需要定位權限');
      await tap('打開設定');
      expect(phone.settingsOpened, 1);

      phone.location = const LocationOff();
      await assistant.handle('我在哪裡');
      expect(shown().title, '定位沒有打開');
      await tap('打開定位');
      expect(phone.locationSettingsOpened, 1);

      phone.location = const LocationUnavailable();
      await assistant.handle('我在哪裡');
      expect(shown().title, '現在找不到位置');
    });
  });

  group('sending my location', () {
    test('to a named contact opens a text message to them', () async {
      phone.contacts = [...phone.contacts, daughter];
      await assistant.handle('把我的位置傳給女兒');
      final (number, body) = phone.texts.single;
      expect(number, '0911-111-111');
      expect(body, startsWith('我在這裡：彰化縣'));
      expect(phone.lineShares, isEmpty);
      expect(shown().title, '把位置傳給 女兒');
    });

    test('a name with several matches asks which one', () async {
      phone.contacts = phone.contacts.skip(1).toList();
      await assistant.handle('傳位置給阿明');
      expect(shown().title, '要傳給哪一位？');
      expect(phone.texts, isEmpty);
      await assistant.choose(shown().choices.first);
      expect(phone.texts.single.$1, '0922');
    });

    test('with no one named it goes to the emergency contact', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('分享我的位置');
      expect(phone.texts.single.$1, '0911-111-111');
    });

    test('with no one to send to, LINE asks who gets it', () async {
      await assistant.handle('分享我的位置');
      expect(phone.lineShares.single, contains('我在這裡：'));
      expect(phone.texts, isEmpty);
      expect(shown().title, '選一位朋友傳位置');
    });

    test('"用 LINE" always goes through LINE', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('用LINE傳我的位置');
      expect(phone.lineShares, hasLength(1));
      expect(phone.texts, isEmpty);
    });

    test('a phone without LINE falls back to a text message', () async {
      phone.hasLine = false;
      await assistant.handle('分享我的位置');
      expect(phone.texts.single.$1, isNull);
      expect(shown().title, '選一位聯絡人傳位置');
    });

    test('an unknown name is reported', () async {
      await assistant.handle('把位置傳給阿嬤');
      expect(shown().title, '找不到「阿嬤」');
      expect(phone.texts, isEmpty);
    });
  });

  group('help', () {
    test('"救命" calls the emergency contact at once', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('救命！');
      expect(phone.dialed, ['0911-111-111']);
      expect(shown().title, '正在打給 女兒');
      expect(shown().tone, OutcomeTone.problem);
      expect(buttons(), ['打給 女兒', '打 119', '把位置傳給 女兒']);
    });

    test('the SOS button shows the same card without calling', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.showEmergency();
      expect(phone.dialed, isEmpty);
      expect(shown().title, '需要幫忙嗎？');
      expect(shown().heard, isNull);

      await tap('打 119');
      await tap('打給 女兒');
      expect(phone.dialed, ['119', '0911-111-111']);
      expect(shown().title, '需要幫忙嗎？', reason: 'the card stays');
    });

    test('sends an urgent location message to the contact', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.showEmergency();
      await tap('把位置傳給 女兒');
      final (number, body) = phone.texts.single;
      expect(number, '0911-111-111');
      expect(body, startsWith('我需要幫忙。我在這裡：'));
    });

    test('with no contact it never dials by itself', () async {
      await assistant.handle('我跌倒了');
      expect(phone.dialed, isEmpty);
      expect(buttons(), ['打 119', '用 LINE 傳我的位置', '設定緊急聯絡人']);

      await tap('設定緊急聯絡人');
      expect(shown().title, '緊急聯絡人');
      expect(shown().detail, '還沒設定');
      expect(buttons(), ['從通訊錄選']);
    });

    test('a phone that cannot call says so', () async {
      phone.canDial = false;
      await assistant.showEmergency();
      await tap('打 119');
      expect(shown().title, '這支手機沒辦法撥號');
    });
  });

  group('emergency contact', () {
    test('is set by name and remembered', () async {
      phone.contacts = [...phone.contacts, daughter];
      await assistant.handle('把女兒設成緊急聯絡人');
      expect(shown().title, '緊急聯絡人');
      expect(shown().detail, '女兒 0911-111-111');
      expect(shown().tone, OutcomeTone.done);
      expect(store.contact!.name, '女兒');

      final next = AssistantController(phone, store: store);
      addTearDown(next.dispose);
      await next.initialize();
      expect(next.emergencyContact!.number, '0911-111-111');
    });

    test('several matches ask which one, then save it', () async {
      phone.contacts = phone.contacts.skip(1).toList();
      await assistant.handle('緊急聯絡人改成阿明');
      expect(shown().title, '要設定哪一位？');
      await assistant.choose(shown().choices.last);
      expect(store.contact!.name, '陳志明');
      expect(phone.dialed, isEmpty, reason: 'choosing here must not call');
    });

    test('can be picked from the contact list', () async {
      await assistant.handle('設定緊急聯絡人');
      phone.picked = daughter;
      await tap('從通訊錄選');
      expect(shown().detail, '女兒 0911-111-111');
      expect(assistant.emergencyContact, daughter);
    });

    test('cancelling the picker changes nothing', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('我的緊急聯絡人是誰');
      expect(shown().detail, '女兒 0911-111-111');
      await tap('換一位');
      expect(shown().detail, '女兒 0911-111-111');
      expect(assistant.emergencyContact, daughter);
    });

    test('can be removed', () async {
      store.contact = daughter;
      await assistant.initialize();
      await assistant.handle('取消緊急聯絡人');
      expect(store.contact, isNull);
      expect(assistant.emergencyContact, isNull);
    });
  });

  group('messages', () {
    test('a text message opens to the contact with the words said', () async {
      phone.contacts = phone.contacts.take(1).toList();
      await assistant.handle('傳簡訊給阿明說我晚一點到');
      expect(phone.texts.single, ('0912 345 678', '我晚一點到'));
      expect(shown().title, '傳簡訊給 阿明');
      expect(shown().detail, '「我晚一點到」');
    });

    test('a LINE message lets the person pick who gets it', () async {
      await assistant.handle('用LINE跟女兒說我到了');
      expect(phone.lineShares, ['我到了']);
      expect(shown().title, '選一位朋友傳 LINE');
    });

    test('a phone that cannot text says so', () async {
      phone.canText = false;
      phone.contacts = phone.contacts.take(1).toList();
      await assistant.handle('傳簡訊給阿明');
      expect(shown().title, '這支手機沒辦法傳訊息');
    });
  });

  test('flashlight turns on with a one-tap off button', () async {
    await assistant.handle('開手電筒');
    expect(phone.torch, true);
    expect(buttons(), ['關掉手電筒']);

    await tap('關掉手電筒');
    expect(phone.torch, false);
    expect(shown().title, '手電筒關了');
    expect(buttons(), isEmpty);
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

  test('a light switched off in the control centre updates the card', () async {
    await assistant.handle('開手電筒');
    expect(assistant.outcome!.title, '手電筒開了');

    phone.torch = false; // switched off outside the app
    await assistant.syncTorch();
    expect(assistant.torchOn, false);
    expect(assistant.outcome!.title, '手電筒關了');
    expect(buttons(), isEmpty, reason: 'no off button left');
    expect(assistant.outcome!.heard, '開手電筒');
  });

  test('a light switched on outside the app is noticed', () async {
    phone.torch = true;
    await assistant.syncTorch();
    expect(assistant.torchOn, true);
    expect(assistant.outcome, isNull);

    await assistant.handle('關掉');
    expect(phone.torch, false);
  });

  test('when the phone cannot tell, nothing changes', () async {
    await assistant.handle('開手電筒');
    phone
      ..canReadTorch = false
      ..torch = false;
    await assistant.syncTorch();
    expect(assistant.torchOn, true);
    expect(assistant.outcome!.title, '手電筒開了');
  });

  test('navigation, songs and weather open the right place', () async {
    await assistant.handle('帶我去台北車站');
    expect(phone.places, ['台北車站']);
    await assistant.handle('我想聽鄧麗君的歌');
    await assistant.handle('今天會下雨嗎');
    expect(phone.searches, ['鄧麗君的歌', '今天天氣']);
  });

  test('time and both calendars are answered on screen', () async {
    await assistant.handle('現在幾點');
    expect(shown().title, '現在是下午 3:05');

    await assistant.handle('今天禮拜幾');
    expect(shown().title, '今天 11 月 10 日');
    expect(shown().detail, '星期二 · 農曆十月初二');

    await assistant.handle('今天農曆幾號');
    expect(shown().title, '農曆十月初二');
    expect(shown().detail, '丙午年 · 星期二');
  });

  test('unknown requests explain what can be said', () async {
    await assistant.handle('今天心情不錯');
    expect(shown().title, '這句我還不會');
    assistant.clear();
    expect(assistant.outcome, isNull);
  });

  test('a failing phone action becomes a readable problem', () async {
    final broken = AssistantController(_Broken());
    addTearDown(broken.dispose);
    await broken.handle('幫我開LINE');
    expect(broken.outcome!.title, '這件事沒有做成');
    expect(broken.working, false);
  });
}

class _Broken extends FakePhone {
  @override
  Future<bool> openApp(PhoneApp app) => throw StateError('no platform');
}
