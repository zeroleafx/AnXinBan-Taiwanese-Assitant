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

/// Open an app that is not one of [PhoneApp], by the name that was said.
final class OpenNamedAppCommand extends VoiceCommand {
  const OpenNamedAppCommand(this.name, {required this.certain});
  final String name;

  /// False for a bare "開…", which may not be about an app ("開冷氣").
  final bool certain;
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

final class WhereAmICommand extends VoiceCommand {
  const WhereAmICommand();
}

/// Send the current location. With no [name] it goes to the emergency
/// contact, or to someone picked in LINE.
final class ShareLocationCommand extends VoiceCommand {
  const ShareLocationCommand({this.name = '', this.viaLine = false});
  final String name;
  final bool viaLine;
}

/// Write a text message for the person to send. [body] keeps the wording as
/// it was said.
final class SendMessageCommand extends VoiceCommand {
  const SendMessageCommand({
    this.name = '',
    this.body = '',
    this.viaLine = false,
  });
  final String name;
  final String body;
  final bool viaLine;
}

/// A call for help.
final class EmergencyCommand extends VoiceCommand {
  const EmergencyCommand();
}

/// Choose who is called in an emergency. An empty [name] shows the current
/// choice and offers the contact list.
final class SetEmergencyContactCommand extends VoiceCommand {
  const SetEmergencyContactCommand(this.name);
  final String name;
}

final class ClearEmergencyContactCommand extends VoiceCommand {
  const ClearEmergencyContactCommand();
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
  const DateCommand({this.lunar = false});

  /// The lunar calendar date was asked for.
  final bool lunar;
}

final class UnknownCommand extends VoiceCommand {
  const UnknownCommand();
}

/// [torchOn] says whether this app has the flashlight on, so that a short
/// "關掉" or "關燈" right after switching it on still reaches the light.
VoiceCommand parseVoiceCommand(String transcript, {bool torchOn = false}) {
  final spoken = _Spoken(transcript);
  final text = spoken.text;
  if (text.isEmpty) return const UnknownCommand();

  // Help comes first, so nothing below can swallow it.
  final contact = _parseEmergencyContact(text);
  if (contact != null) return contact;
  if (_emergencyWords.hasMatch(text)) return const EmergencyCommand();
  final place = _parsePlace(text);
  if (place == null) {
    // "帶我去消防隊" is a trip; "叫救護車" is a call.
    for (final MapEntry(key: words, value: number)
        in _emergencyNumbers.entries) {
      if (words.hasMatch(text)) return DialNumberCommand(number);
    }
  }

  if (_torchWords.any(text.contains)) {
    return FlashlightCommand(on: _switchTo(text));
  }

  final share = _parseShareLocation(text);
  if (share != null) return share;
  final bare = _bare(text);
  if (_whereAmI.any((pattern) => pattern.hasMatch(bare))) {
    return const WhereAmICommand();
  }
  final message = _parseMessage(spoken);
  if (message != null) return message;

  // Apps first, so "用 LINE 打給阿明" opens LINE instead of the phone dialer.
  final app = _findApp(text, _apps.keys.where((a) => a != PhoneApp.maps));
  if (app != null) return OpenAppCommand(app);

  final call = _parseCall(text);
  if (call != null) return call;

  if (place != null) {
    return place.isEmpty
        ? const OpenAppCommand(PhoneApp.maps)
        : NavigateCommand(place);
  }
  if (_findApp(text, const [PhoneApp.maps]) != null) {
    return const OpenAppCommand(PhoneApp.maps);
  }
  if (_lunarWords.hasMatch(text)) return const DateCommand(lunar: true);
  if (_timeWords.hasMatch(text)) return const TimeCommand();
  if (_dateWords.hasMatch(text)) return const DateCommand();
  if (_weatherWords.hasMatch(text)) return const WeatherCommand();

  final video = _video.firstMatch(text);
  if (video != null) {
    final query = _trim(video.group(1)!, leading: _videoLead);
    if (query.isNotEmpty) return VideoSearchCommand(query);
  }

  for (final (pattern, certain) in _openNamed) {
    final name = pattern.firstMatch(bare)?.group(1);
    if (name != null) return OpenNamedAppCommand(name, certain: certain);
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
String normalizeTranscript(String text) => _Spoken(text).text;

/// A transcript with its normalized form, and the way back from a place in
/// the normalized text to the words as they were said.
class _Spoken {
  _Spoken(this.original) {
    final out = StringBuffer();
    var offset = 0;
    for (var rune in original.runes) {
      final start = offset;
      offset += rune > 0xFFFF ? 2 : 1;
      if (rune >= 0xFF01 && rune <= 0xFF5E) rune -= 0xFEE0;
      final char = String.fromCharCode(rune);
      if (_dropped.hasMatch(char)) continue;
      final folded = (_simplified[char] ?? char).toLowerCase();
      out.write(folded);
      for (var i = 0; i < folded.length; i++) {
        _offsets.add(start);
      }
    }
    text = out.toString();
  }

  final String original;
  late final String text;
  final _offsets = <int>[];

  /// The original wording of the last [length] normalized characters.
  String tail(int length) => length <= 0 || length > text.length
      ? ''
      : original.substring(_offsets[text.length - length]).trim();
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

VoiceCommand? _parseEmergencyContact(String raw) {
  final text = raw.replaceAll('連絡', '聯絡');
  if (!text.contains(_contactWord)) return null;
  if (_clearContact.hasMatch(text)) return const ClearEmergencyContactCommand();
  for (final pattern in _setContact) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final name = _trim(match.group(1)!, leading: _nameLead);
    return SetEmergencyContactCommand(_whoWords.contains(name) ? '' : name);
  }
  // "打給緊急聯絡人" is a call for help.
  if (_callWords.hasMatch(text.replaceAll(_contactWord, ''))) {
    return const EmergencyCommand();
  }
  return const SetEmergencyContactCommand('');
}

VoiceCommand? _parseShareLocation(String text) {
  for (final pattern in _shareLocation) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final who = match.group(1) ?? '';
    // "告訴我我在哪裡" asks; it does not send anything.
    if (_people.contains(who)) return null;
    // LINE cannot be opened to one person, so a name is of no use there.
    if (_lineWords.hasMatch(text)) {
      return const ShareLocationCommand(viaLine: true);
    }
    final name = _trim(who, leading: _nameLead);
    return ShareLocationCommand(name: _anyone.contains(name) ? '' : name);
  }
  return null;
}

VoiceCommand? _parseMessage(_Spoken spoken) {
  final text = spoken.text;
  final sms = _sms.firstMatch(text);
  if (sms != null) {
    return SendMessageCommand(
      name: _trim(sms.group(1)!, leading: _nameLead),
      body: spoken.tail(sms.group(2)?.length ?? 0),
    );
  }
  final line = _lineMessage.firstMatch(text);
  if (line != null && !_notMessages.contains(line.group(1))) {
    return SendMessageCommand(
      body: spoken.tail(line.group(1)!.length),
      viaLine: true,
    );
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

  final name = _trim(target, leading: _nameLead);
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

/// Drops polite openings and sentence-final particles: "請問我在哪裡啊" is
/// "我在哪裡".
String _bare(String value) {
  var text = value;
  var changed = true;
  while (changed) {
    changed = false;
    for (final word in _politeLead) {
      if (text.length > word.length && text.startsWith(word)) {
        text = text.substring(word.length);
        changed = true;
      }
    }
    for (final word in _politeTail) {
      if (text.length > word.length && text.endsWith(word)) {
        text = text.substring(0, text.length - word.length);
        changed = true;
      }
    }
  }
  return text;
}

const _apps = {
  PhoneApp.line: ['line', '賴', '萊恩'],
  PhoneApp.youtube: ['youtube', '油管', '優兔'],
  PhoneApp.facebook: ['facebook', 'fb', '臉書', '臉冊'],
  PhoneApp.messages: ['簡訊', '短信', '訊息'],
  PhoneApp.maps: ['googlemaps', 'googlemap', 'google地圖', '谷歌地圖', '地圖'],
};
const _openVerbs = '打開|開啟|開|啟動|進入|叫出|點開|用|看|上';

/// Any other app: (pattern, whether it is surely about an app).
final _openNamed = [
  (RegExp(r'^(?:打開|開啟|啟動|點開|進入|叫出)(?:一下)?(?:我的|手機的)?(.{1,12})$'), true),
  (RegExp(r'^(.{1,12}?)(?:打開|開啟|開起來)$'), true),
  (RegExp(r'^開(?:一下)?(?:我的)?(.{1,12})$'), false),
];

const _contactWord = '緊急聯絡人';
final _clearContact = RegExp(r'(?:取消|刪除|刪掉|清除|清掉|移除|不要)(?:我的)?緊急聯絡人');
final _setContact = [
  // 把女兒設成緊急聯絡人
  RegExp(r'把(.+?)(?:設定成|設定為|設定做|設成|設為|設做|當作|當成|當做|加到|加入|設定|當|設|做)(?:我的)?緊急聯絡人'),
  // 設女兒為緊急聯絡人
  RegExp(r'(?:設定|設|選|改|換|加)(?:成|為)?(.+?)(?:當作|當成|當做|做|當|為|成)(?:我的)?緊急聯絡人'),
  // 緊急聯絡人改成女兒
  RegExp(r'緊急聯絡人(?:設定成|設定為|設成|設為|改成|改為|換成|就是|設定|是|換|改|設|用)(.+)$'),
];
final _callWords = RegExp(r'打|撥|敲|聯絡|call|找|叫');
const _whoWords = {'', '誰', '哪位', '哪一位', '啥人', '什麼人'};

final _emergencyWords = RegExp(
  r'救命|救我|救人|求救|sos|緊急狀況|緊急情況|緊急事件|很緊急|跌倒|摔倒|跋倒|爬不起來|站不起來',
);
final _emergencyNumbers = {
  RegExp(r'救護車|消防|火災|失火|著火'): '119',
  RegExp(r'報警|叫警察|找警察|警察局|派出所'): '110',
};

const _torchWords = ['手電筒', '手電仔', '手電', '電筒', '閃光燈', '電火'];
// Taiwanese switches a light off with 禁 ("電火禁掉"). 暗 is not here:
// "好暗，開手電筒" asks for light.
const _switchOffWords = [
  '關', '熄', '禁', '滅', '不要', '不用', '免', '收起', '拿掉', '切掉', '夠了', //
];
const _switchOnWords = ['開', '亮', '點', '照'];

const _place = r'(?:位置|定位|地點)';
const _send = r'(?:傳|分享|送|寄|發|報)';
const _toWhom = r'(?:給|予|乎|互)';
const _where = r'(?:在|佇)(?:哪裡|哪兒|哪|佗位|叨位)';
const _now = r'(?:現在|這馬|目前)?(?:人)?';
final _shareLocation = [
  // 把我的位置傳給女兒
  RegExp('$_place$_send(?:$_toWhom(.+)|(?:出去|一下)?)\$'),
  // 傳位置給阿明、分享我的位置
  RegExp('$_send(?:一下)?(?:我現在的|我目前的|現在的|目前的|我的|我)?$_place(?:$_toWhom(.+))?\$'),
  // 跟女兒說我在哪裡
  RegExp('(?:跟|和|佮|給|予|向)(.+?)(?:說|講|報告|報)(?:一下)?我(?:的位置|$_now$_where)'),
  // 告訴女兒我在哪裡
  RegExp('(?:告訴|通知)(.+?)我(?:的位置|$_now$_where)'),
];
final _lineWords = RegExp(r'line|用賴|傳賴|賴傳');
const _anyone = {'', '家人', '家裡的人', '厝內的人', '大家', '別人', '朋友'};

const _whereWords = r'(?:哪裡|哪兒|哪|佗位|叨位|什麼地方|甚麼地方|啥物所在)';
final _whereAmI = [
  RegExp('^(?:我|我們|阮|咱)?$_now(?:是)?(?:在|佇|踮)$_whereWords\$'),
  RegExp('^(?:這裡|這邊|這個地方|這|遮)(?:是|在)$_whereWords\$'),
  RegExp(r'^(?:看|查|找)?(?:我的位置|我現在的位置|現在位置|目前位置|我的定位|定位)(?:在哪裡|在哪)?$'),
];

final _sms = RegExp(
  r'(?:傳|發|寄|送|寫)(?:一?[個封則通條])?(?:簡訊|訊息|短信)(?:給|予|乎|互)(.+?)(?:(?:說|講|寫)(.+))?$',
);
// "用 LINE 講電話" is not a message, so "用" needs someone to tell.
final _lineMessage = RegExp(
  r'(?:(?:傳|發)(?:line|賴)(?:訊息)?(?:給|予|跟|和|佮)?.*?|'
  r'用(?:line|賴)(?:傳訊息|傳)?(?:給|予|跟|和|佮).+?)(?:說|講)(.+)$',
);
const _notMessages = {'電話', '視訊', '話', '一下'};

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

/// Words before a person's name that are not part of it: "打給我女兒".
const _nameLead = ['給', '予', '乎', '互', '一下', '我的', '我們', '我'];

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

final _lunarWords = RegExp(r'農曆|舊曆|陰曆|農民曆|初幾');
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
const _politeLead = [
  '請問', '請你', '請', '麻煩你', '麻煩', '拜託', //
  '可不可以幫我', '可以幫我', '幫我', '幫忙', '你知道', '告訴我', '跟我說',
];
const _politeTail = [
  '好不好', '好嗎', '可以嗎', '可不可以', '謝謝你', '謝謝', '拜託', //
  '啦', '啊', '喔', '哦', '呢', '吧', '嘛', '欸', '耶', '唷', '咧', '矣', '嗎',
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
  '传': '傳', '说': '說', '讲': '講', '紧': '緊', '护': '護', '车': '車', //
  '农': '農', '历': '曆', '设': '設', '发': '發', '诉': '訴',
};
