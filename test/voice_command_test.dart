import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/voice_command.dart';

Matcher opens(PhoneApp app) =>
    isA<OpenAppCommand>().having((c) => c.app, 'app', app);
Matcher calls(String name) =>
    isA<CallContactCommand>().having((c) => c.name, 'name', name);
Matcher dials(String number) =>
    isA<DialNumberCommand>().having((c) => c.number, 'number', number);
Matcher torch({required bool? on}) =>
    isA<FlashlightCommand>().having((c) => c.on, 'on', on);
Matcher goesTo(String place) =>
    isA<NavigateCommand>().having((c) => c.place, 'place', place);
Matcher searches(String query) =>
    isA<VideoSearchCommand>().having((c) => c.query, 'query', query);

void main() {
  void expectCommand(String transcript, Matcher matcher) =>
      expect(parseVoiceCommand(transcript), matcher, reason: transcript);

  test('opens apps however LINE is written', () {
    expectCommand('幫我開LINE', opens(PhoneApp.line));
    expectCommand('幫我開 Line。', opens(PhoneApp.line));
    expectCommand('打開ＬＩＮＥ', opens(PhoneApp.line));
    expectCommand('LINE', opens(PhoneApp.line));
    expectCommand('開賴', opens(PhoneApp.line));
    expectCommand('我要看YouTube', opens(PhoneApp.youtube));
    expectCommand('幫我上臉書', opens(PhoneApp.facebook));
    expectCommand('打開地圖', opens(PhoneApp.maps));
    expectCommand('看簡訊', opens(PhoneApp.messages));
  });

  test('calls a contact by name', () {
    expectCommand('幫我打電話給阿明', calls('阿明'));
    expectCommand('幫我打電話予阿明', calls('阿明'));
    expectCommand('打給女兒好嗎', calls('女兒'));
    expectCommand('幫我給阿明打個電話', calls('阿明'));
    expectCommand('敲電話予阿母', calls('阿母'));
    expectCommand('打電話給王小明的手機', calls('王小明'));
    expectCommand('打电话给妈妈', calls('媽媽'));
    expectCommand('聯絡陳老師', calls('陳老師'));
  });

  test('asks who to call when no one is named', () {
    expectCommand('幫我打電話', calls(''));
  });

  test('a contact named 賴 does not open LINE', () {
    expectCommand('打電話給賴先生', calls('賴先生'));
  });

  test('dials spoken numbers', () {
    expectCommand('打119', dials('119'));
    expectCommand('撥一一九', dials('119'));
    expectCommand('打電話給零九一二三四五六七八', dials('0912345678'));
  });

  test('turns the flashlight on and off', () {
    expectCommand('打開手電筒', torch(on: true));
    expectCommand('幫我開手電筒', torch(on: true));
    expectCommand('手電筒關掉', torch(on: false));
    expectCommand('把电筒关掉', torch(on: false));
    expectCommand('開電火', torch(on: true));
  });

  test('understands the ways people switch the flashlight off', () {
    expectCommand('手電筒禁掉', torch(on: false));
    expectCommand('共電火禁掉', torch(on: false));
    expectCommand('手電筒不用了', torch(on: false));
    expectCommand('不用手電筒了', torch(on: false));
    expectCommand('手電筒熄掉', torch(on: false));
    expectCommand('手電筒收起來', torch(on: false));
    expectCommand('不要開手電筒', torch(on: false));
    expectCommand('手电筒灭掉', torch(on: false));
  });

  test('dark rooms and power cuts ask for light', () {
    expectCommand('好暗，幫我開手電筒', torch(on: true));
    expectCommand('停電了開手電筒', torch(on: true));
    expectCommand('點電火', torch(on: true));
  });

  test('just naming the flashlight switches it over', () {
    expectCommand('手電筒', torch(on: null));
    expectCommand('手電筒好了', torch(on: null));
  });

  test('a short "關掉" reaches the flashlight only while it is on', () {
    for (final words in ['關掉', '關燈', '幫我關起來', '不用了']) {
      expect(
        parseVoiceCommand(words, torchOn: true),
        torch(on: false),
        reason: words,
      );
      expect(parseVoiceCommand(words), isA<UnknownCommand>(), reason: words);
    }
    // Other requests still work while the light is on.
    expect(parseVoiceCommand('打給阿明', torchOn: true), calls('阿明'));
  });

  test('navigates to a place', () {
    expectCommand('帶我去台北車站', goesTo('台北車站'));
    expectCommand('幫我導航到彰化火車站', goesTo('彰化火車站'));
    expectCommand('去台北車站要怎麼走', goesTo('台北車站'));
    expectCommand('郵局在哪裡', goesTo('郵局'));
    expectCommand('開地圖帶我去台北車站', goesTo('台北車站'));
    expectCommand('幫我開導航', opens(PhoneApp.maps));
  });

  test('daily phrases that are not places are not navigation', () {
    expectCommand('我要去睡覺', isA<UnknownCommand>());
    expectCommand('我要去看醫生', isA<UnknownCommand>());
  });

  test('asking where I am is not a trip to "me"', () {
    expectCommand('我在哪裡', isA<UnknownCommand>());
    expectCommand('這裡在哪裡？', isA<UnknownCommand>());
  });

  test('answers time, date and weather questions', () {
    expectCommand('現在幾點', isA<TimeCommand>());
    expectCommand('今天禮拜幾', isA<DateCommand>());
    expectCommand('今天幾號', isA<DateCommand>());
    expectCommand('今天會下雨嗎', isA<WeatherCommand>());
  });

  test('searches YouTube for songs', () {
    expectCommand('我想聽鄧麗君的歌', searches('鄧麗君的歌'));
    expectCommand('放一首望春風', searches('望春風'));
  });

  test('unknown requests stay unknown', () {
    expectCommand('', isA<UnknownCommand>());
    expectCommand('今天心情不錯', isA<UnknownCommand>());
  });

  test('normalization keeps names but drops punctuation and spaces', () {
    expect(normalizeTranscript('幫我 開 LINE！'), '幫我開line');
    expect(spokenDigits('零九一二'), '0912');
    expect(spokenDigits('阿明'), isNull);
  });
}
