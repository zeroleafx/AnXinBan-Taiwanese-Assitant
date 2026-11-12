/// Turns a Breeze transcript into a phone command.
///
/// Breeze-ASR-26 writes Taiwanese speech as Mandarin text (sometimes with
/// Taiwanese Han characters such as 予、欲、敲), so the patterns below accept
/// both, plus a few Simplified forms.
library;

enum PhoneApp { line, youtube, facebook, maps, messages }

extension PhoneAppLabel on PhoneApp {
  String get label => switch (this) {
    PhoneApp.line => 'LINE',
    PhoneApp.youtube => 'YouTube',
    PhoneApp.facebook => 'Facebook',
    PhoneApp.maps => '地圖',
    PhoneApp.messages => '簡訊',
  };
}

sealed class VoiceCommand {
  const VoiceCommand();
}

final class OpenAppCommand extends VoiceCommand {
  const OpenAppCommand(this.app);
  final PhoneApp app;
}

/// Call someone from the contacts. [name] is empty when no one was named.
final class CallContactCommand extends VoiceCommand {
  const CallContactCommand(this.name);
  final String name;
}

final class DialNumberCommand extends VoiceCommand {
  const DialNumberCommand(this.number);
  final String number;
}

final class FlashlightCommand extends VoiceCommand {
  const FlashlightCommand({this.on});

  /// Null when the words say neither on nor off: the light is switched over.
  final bool? on;
}

final class NavigateCommand extends VoiceCommand {
  const NavigateCommand(this.place);
  final String place;
}

final class VideoSearchCommand extends VoiceCommand {
  const VideoSearchCommand(this.query);
  final String query;
}

final class WeatherCommand extends VoiceCommand {
  const WeatherCommand();
}

final class TimeCommand extends VoiceCommand {
  const TimeCommand();
}

final class DateCommand extends VoiceCommand {
  const DateCommand();
}

final class UnknownCommand extends VoiceCommand {
  const UnknownCommand();
}

/// [torchOn] says whether this app has the flashlight on, so that a short
/// "關掉" or "關燈" right after switching it on still reaches the light.
VoiceCommand parseVoiceCommand(String transcript, {bool torchOn = false}) {
  final text = normalizeTranscript(transcript);
  if (text.isEmpty) return const UnknownCommand();

  if (_torchWords.any(text.contains)) {
    return FlashlightCommand(on: _switchTo(text));
  }
  // Apps first, so "用 LINE 打給阿明" opens LINE instead of the phone dialer.
  final app = _findApp(text, _apps.keys.where((a) => a != PhoneApp.maps));
  if (app != null) return OpenAppCommand(app);

  final call = _parseCall(text);
  if (call != null) return call;

  final place = _parsePlace(text);
  if (place != null) {
    return place.isEmpty
        ? const OpenAppCommand(PhoneApp.maps)
        : NavigateCommand(place);
  }
  if (_findApp(text, const [PhoneApp.maps]) != null) {
    return const OpenAppCommand(PhoneApp.maps);
  }
  if (_timeWords.hasMatch(text)) return const TimeCommand();
  if (_dateWords.hasMatch(text)) return const DateCommand();
  if (_weatherWords.hasMatch(text)) return const WeatherCommand();

  final video = _video.firstMatch(text);
  if (video != null) {
    final query = _trim(video.group(1)!, leading: _videoLead);
    if (query.isNotEmpty) return VideoSearchCommand(query);
  }
  if (torchOn && _switchOffWords.any(text.contains)) {
    return const FlashlightCommand(on: false);
  }
  return const UnknownCommand();
}

/// Off wins over on, so "不要開" switches off. Null when neither is said.
bool? _switchTo(String text) {
  if (_switchOffWords.any(text.contains)) return false;
  if (_switchOnWords.any(text.contains)) return true;
  return null;
}

/// Lower-cases, folds full-width ASCII and a few Simplified characters, and
/// drops spaces and punctuation.
String normalizeTranscript(String text) {
  final out = StringBuffer();
  for (var rune in text.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) rune -= 0xFEE0;
    final char = String.fromCharCode(rune);
    if (_dropped.hasMatch(char)) continue;
    out.write((_simplified[char] ?? char).toLowerCase());
  }
  return out.toString();
}

/// Converts digit-by-digit numbers ("零九一二…", "一一九") to ASCII digits.
String? spokenDigits(String text) {
  final out = StringBuffer();
  for (final char in text.split('')) {
    final digit = _asciiDigit.hasMatch(char) ? char : _digitWords[char];
    if (digit == null) return null;
    out.write(digit);
  }
  return out.length >= 3 ? out.toString() : null;
}

PhoneApp? _findApp(String text, Iterable<PhoneApp> apps) {
  for (final app in apps) {
    for (final alias in _apps[app]!) {
      final name = RegExp.escape(alias);
      if (text == alias ||
          RegExp('(?:$_openVerbs)(?:一下)?(?:我的)?$name').hasMatch(text) ||
          RegExp('$name(?:打開|開啟|開起來|開)').hasMatch(text)) {
        return app;
      }
    }
  }
  return null;
}

VoiceCommand? _parseCall(String text) {
  String? target;
  for (final pattern in _callPatterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      target = match.group(1)!;
      break;
    }
  }
  final digits = _dialDigits.firstMatch(text);
  if (target == null && digits != null) target = digits.group(1)!;
  if (target == null) return null;

  final name = _trim(target, leading: _callLead);
  final number = spokenDigits(name);
  return number != null ? DialNumberCommand(number) : CallContactCommand(name);
}

/// Returns the destination, an empty string for "open navigation", or null
/// when the text is not about going somewhere.
String? _parsePlace(String text) {
  final match = _navigateTo.firstMatch(text) ?? _howToGet.firstMatch(text);
  if (match == null) return null;
  final place = _trim(match.group(1)!, leading: _placeLead);
  if (_notPlaces.any(place.startsWith)) return null;
  // "我在哪裡" asks where the speaker is; it is not a trip to "我".
  if (_people.contains(place)) return null;
  return place;
}

String _trim(String value, {required List<String> leading}) {
  var text = value;
  var changed = true;
  while (changed) {
    changed = false;
    for (final word in _fillers) {
      if (text.length > word.length && text.endsWith(word)) {
        text = text.substring(0, text.length - word.length);
        changed = true;
      }
    }
    for (final word in leading) {
      if (text.length > word.length && text.startsWith(word)) {
        text = text.substring(word.length);
        changed = true;
      }
    }
  }
  return _fillers.contains(text) || leading.contains(text) ? '' : text;
}

const _apps = {
  PhoneApp.line: ['line', '賴', '萊恩'],
  PhoneApp.youtube: ['youtube', '油管', '優兔'],
  PhoneApp.facebook: ['facebook', 'fb', '臉書', '臉冊'],
  PhoneApp.messages: ['簡訊', '短信', '訊息'],
  PhoneApp.maps: ['googlemaps', 'googlemap', 'google地圖', '谷歌地圖', '地圖'],
};
const _openVerbs = '打開|開啟|開|啟動|進入|叫出|點開|用|看|上';

const _torchWords = ['手電筒', '手電仔', '手電', '電筒', '閃光燈', '電火'];
// Taiwanese switches a light off with 禁 ("電火禁掉"). 暗 is not here:
// "好暗，開手電筒" asks for light.
const _switchOffWords = [
  '關', '熄', '禁', '滅', '不要', '不用', '免', '收起', '拿掉', '切掉', '夠了', //
];
const _switchOnWords = ['開', '亮', '點', '照'];

const _callVerb = r'(?:打|撥|敲)';
const _callSize = r'(?:一通|一個|個|通)?';
const _to = r'(?:給|予|乎|互|去|到)';
final _callPatterns = [
  // 給阿明打電話
  RegExp('(?:給|予|乎|互|跟|和|佮)(.+?)$_callVerb$_callSize電話'),
  // 打電話給阿明
  RegExp('$_callVerb$_callSize電話$_to?(.*)\$'),
  // 打給阿明
  RegExp('(?:$_callVerb|call)$_to(.+)\$'),
  // 聯絡阿明
  RegExp(r'(?:聯絡|連絡)(.+)$'),
];
final _dialDigits = RegExp(r'(?:打|撥)(?:一下)?([0-9零〇○洞一么幺二兩三四五六七八九]{3,})');
const _callLead = ['給', '予', '乎', '互', '去', '到', '一下', '跟', '和'];

final _navigateTo = RegExp(
  r'(?:帶我去|帶我到|載我去|載我到|導航到|導航去|導航至|導航|我想要去|我想欲去|我要去|我欲去|我想去|欲去|要去)(.*)$',
);
final _howToGet = RegExp(
  r'(.+?)(?:要)?(?:怎麼走|怎麼去|怎樣走|怎樣去|按怎行|按怎去|在哪裡|在哪|佇佗位|佗位)$',
);
const _placeLead = ['去', '到', '我要', '我想', '請問', '請', '幫我'];
const _notPlaces = [
  '睡覺', '睏', '洗澡', '洗身軀', '吃飯', '食飯', '上廁所', '便所', '運動', '散步', //
  '看醫生', '工作', '上班', '上課', '我的', '你的',
];

const _people = {'我', '我們', '你', '你們', '他', '她', '咱', '阮', '這', '這裡', '這邊'};

final _timeWords = RegExp(r'幾點|時間|時陣|幾點鐘');
final _dateWords = RegExp(r'幾號|日期|禮拜幾|星期幾|拜幾|今天是|今仔日是');
final _weatherWords = RegExp(r'天氣|下雨|落雨|氣溫|溫度|幾度|會冷|會熱');

final _video = RegExp(
  r'(?:我想要聽|我想聽|我要聽|我欲聽|想欲聽|我想要看|我想看|我要看|我欲看|想欲看|播放|播|放|唱)(.+)$',
);
const _videoLead = ['一首', '一條', '一下', '一些', '幾首', '點'];

const _fillers = [
  '好不好', '好嗎', '可以嗎', '可不可以', '謝謝你', '謝謝', '一下', //
  '的手機', '的電話', '手機', '電話', '拜託', //
  '啦', '啊', '喔', '哦', '呢', '吧', '嘛', '欸', '耶', '唷', '咧', '矣',
];

final _dropped = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

final _asciiDigit = RegExp(r'^[0-9]$');
const _digitWords = {
  '零': '0', '〇': '0', '○': '0', '洞': '0', //
  '一': '1', '么': '1', '幺': '1', '二': '2', '兩': '2', '三': '3', //
  '四': '4', '五': '5', '六': '6', '七': '7', '八': '8', '九': '9',
};

const _simplified = {
  '电': '電', '话': '話', '给': '給', '开': '開', '导': '導', '带': '帶', //
  '关': '關', '闪': '閃', '灯': '燈', '脸': '臉', '书': '書', '简': '簡', //
  '讯': '訊', '图': '圖', '听': '聽', '几': '幾', '点': '點', '号': '號', //
  '气': '氣', '时': '時', '间': '間', '拨': '撥', '联': '聯', '络': '絡', //
  '启': '啟', '进': '進', '载': '載', '样': '樣', '这': '這', '灭': '滅', //
  '帮': '幫', '请': '請', '礼': '禮', '温': '溫', '妈': '媽', '儿': '兒', //
};
