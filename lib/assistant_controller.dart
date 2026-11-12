import 'package:flutter/material.dart';

import 'contact_matcher.dart';
import 'emergency_store.dart';
import 'lunar_date.dart';
import 'phone_actions.dart';
import 'place.dart';
import 'voice_command.dart';

enum OutcomeTone { done, info, problem }

enum ButtonKind { primary, urgent, quiet }

/// A step that may replace the card on screen. Null keeps the current one.
typedef OutcomeStep = Future<AssistantOutcome?> Function();

/// A follow-up button shown under an outcome.
class OutcomeButton {
  const OutcomeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.primary,
  });

  final IconData icon;
  final String label;
  final OutcomeStep onPressed;
  final ButtonKind kind;
}

class AssistantOutcome {
  const AssistantOutcome({
    required this.tone,
    required this.icon,
    required this.title,
    this.detail,
    this.heard,
    this.choices = const [],
    this.onChoice,
    this.buttons = const [],
    this.showExamples = false,
  });

  final OutcomeTone tone;
  final IconData icon;
  final String title;
  final String? detail;

  /// What Breeze heard, shown small under the result. Null when the card
  /// did not come from speech.
  final String? heard;

  /// Contacts to pick from when a name fits more than one.
  final List<ContactEntry> choices;
  final Future<AssistantOutcome?> Function(ContactEntry contact)? onChoice;
  final List<OutcomeButton> buttons;

  /// Show what can be said, after a request that was not understood.
  final bool showExamples;
}

/// Turns what was heard into a phone action and keeps the result for the UI.
class AssistantController extends ChangeNotifier {
  AssistantController(
    this.actions, {
    EmergencyStore? store,
    DateTime Function()? now,
  }) : store = store ?? MemoryEmergencyStore(),
       _now = now ?? DateTime.now;

  final PhoneActions actions;
  final EmergencyStore store;
  final DateTime Function() _now;
  AssistantOutcome? outcome;

  /// Who is called first in an emergency.
  ContactEntry? emergencyContact;
  bool working = false;

  /// Whether this app last switched the flashlight on, so it can still be
  /// switched off after its card is gone.
  bool torchOn = false;
  bool _disposed = false;

  /// The words behind the cards being shown, if they came from speech.
  String? _heard;

  /// Loads the saved emergency contact.
  Future<void> initialize() async {
    try {
      emergencyContact = await store.load();
    } catch (_) {
      // Without it the help card offers to choose one.
    }
    _notify();
  }

  Future<void> handle(String transcript) {
    final heard = transcript.trim();
    return _work(() {
      _heard = heard;
      return _run(parseVoiceCommand(heard, torchOn: torchOn));
    }, fresh: true);
  }

  /// Catches up with the light after it was switched outside the app, for
  /// example from the control centre, so the screen does not keep saying
  /// "手電筒開了" over a dark light.
  Future<void> syncTorch() async {
    if (working) return;
    final on = await actions.torchIsOn();
    if (_disposed || working || on == null || on == torchOn) return;
    torchOn = on;
    final shown = outcome;
    if (!on && shown != null && shown.icon == Icons.flashlight_on_rounded) {
      outcome = AssistantOutcome(
        tone: OutcomeTone.done,
        icon: Icons.flashlight_off_rounded,
        title: '手電筒關了',
        heard: shown.heard,
      );
    }
    _notify();
  }

  /// The off button that stays on screen while the light is on.
  Future<void> switchTorchOff() => _work(() async {
    _heard = null;
    return _torch(on: false);
  });

  /// The help card behind the SOS button. It calls no one by itself.
  Future<void> showEmergency() => _work(() async {
    _heard = null;
    return _help();
  }, fresh: true);

  /// Picks one of the contacts offered by the current card.
  Future<void> choose(ContactEntry contact) async {
    final onChoice = outcome?.onChoice;
    if (onChoice != null) await _work(() => onChoice(contact));
  }

  Future<void> press(OutcomeButton button) => _work(button.onPressed);

  void clear() {
    if (outcome == null) return;
    outcome = null;
    _notify();
  }

  Future<void> _work(OutcomeStep step, {bool fresh = false}) async {
    if (_disposed || working) return;
    working = true;
    if (fresh) outcome = null;
    _notify();
    try {
      final next = await step();
      if (next != null) outcome = next;
    } catch (_) {
      outcome = _problem(
        Icons.error_outline_rounded,
        '這件事沒有做成',
        detail: '請再試一次',
      );
    } finally {
      working = false;
      _notify();
    }
  }

  Future<AssistantOutcome?> _run(VoiceCommand command) async {
    switch (command) {
      case OpenAppCommand(:final app):
        return await actions.openApp(app)
            ? _done(_appIcon(app), _words('已打開', app.label))
            : _problem(Icons.search_off_rounded, _words('手機裡找不到', app.label));
      case OpenNamedAppCommand(:final name, :final certain):
        final label = await actions.openNamedApp(name);
        if (label != null) {
          return _done(Icons.apps_rounded, _words('已打開', label));
        }
        return certain
            ? _problem(
                Icons.search_off_rounded,
                '找不到「$name」',
                detail: '手機裡沒有這個 App',
              )
            : _unknown();
      case CallContactCommand(name: ''):
        return _info(Icons.call_rounded, '要打給誰？', detail: '例如：打予阿明');
      case CallContactCommand(:final name):
        return _withContact(name, '要打給哪一位？', _call);
      case DialNumberCommand(:final number):
        return await actions.dial(number)
            ? _done(Icons.call_rounded, '撥打 $number')
            : _cannotDial();
      case FlashlightCommand(:final on):
        // Just "手電筒" switches it over.
        return _torch(on: on ?? !torchOn);
      case NavigateCommand(:final place):
        return await actions.navigate(place)
            ? _done(Icons.near_me_rounded, '帶你去$place')
            : _problem(Icons.wrong_location_rounded, '打不開地圖');
      case WhereAmICommand():
        return _whereAmI();
      case ShareLocationCommand(viaLine: true):
        return _sendLocation(viaLine: true);
      case ShareLocationCommand(name: ''):
        return _sendLocation(to: emergencyContact);
      case ShareLocationCommand(:final name):
        return _withContact(
          name,
          '要傳給哪一位？',
          (contact) => _sendLocation(to: contact),
        );
      case SendMessageCommand(viaLine: true, :final body):
        return await actions.shareOnLine(body)
            ? _done(Icons.chat_rounded, '選一位朋友傳 LINE', detail: '「$body」')
            : _problem(Icons.search_off_rounded, '手機裡找不到 LINE');
      case SendMessageCommand(name: ''):
        return _info(Icons.sms_rounded, '要傳給誰？', detail: '例如：傳簡訊給阿明');
      case SendMessageCommand(:final name, :final body):
        return _withContact(name, '要傳給哪一位？', (contact) => _text(contact, body));
      case EmergencyCommand():
        final contact = emergencyContact;
        final dialed = contact != null && await actions.dial(contact.number);
        return _help(dialed: dialed);
      case SetEmergencyContactCommand(name: ''):
        return _contactCard();
      case SetEmergencyContactCommand(:final name):
        return _withContact(name, '要設定哪一位？', _saveContact);
      case ClearEmergencyContactCommand():
        await store.save(null);
        emergencyContact = null;
        return _done(Icons.person_off_rounded, '已取消緊急聯絡人');
      case VideoSearchCommand(:final query):
        return await actions.searchVideo(query)
            ? _done(Icons.smart_display_rounded, '在 YouTube 找「$query」')
            : _problem(Icons.search_off_rounded, '打不開 YouTube');
      case WeatherCommand():
        return await actions.searchWeb('今天天氣')
            ? _done(Icons.wb_sunny_rounded, '幫你查天氣')
            : _problem(Icons.cloud_off_rounded, '現在查不到天氣');
      case TimeCommand():
        return _info(Icons.schedule_rounded, '現在是${_clock(_now())}');
      case DateCommand(:final lunar):
        final today = _now();
        final moon = LunarDate(today);
        final solar = '${today.month} 月 ${today.day} 日';
        final weekday = '星期${_weekdays[today.weekday - 1]}';
        return lunar
            ? _info(
                Icons.calendar_month_rounded,
                '農曆${moon.monthDay}',
                detail: '${moon.year}年 · $weekday',
              )
            : _info(
                Icons.calendar_month_rounded,
                '今天 $solar',
                detail: '$weekday · 農曆${moon.monthDay}',
              );
      case UnknownCommand():
        return _unknown();
    }
  }

  /// Finds [name] in the contacts and continues with that person. Asks which
  /// one when several fit.
  Future<AssistantOutcome?> _withContact(
    String name,
    String question,
    Future<AssistantOutcome?> Function(ContactEntry contact) then,
  ) async {
    final access = await actions.loadContacts();
    if (!access.granted) {
      return AssistantOutcome(
        tone: OutcomeTone.problem,
        icon: Icons.contacts_rounded,
        title: '需要通訊錄權限',
        detail: '才能照名字找到人',
        heard: _heard,
        buttons: [_settingsButton],
      );
    }
    final matches = matchContacts(name, access.contacts, limit: 3);
    if (matches.isEmpty) {
      return _problem(
        Icons.person_search_rounded,
        '找不到「$name」',
        detail: '通訊錄裡沒有這個名字',
      );
    }
    if (matches.length == 1) return then(matches.single);
    return AssistantOutcome(
      tone: OutcomeTone.info,
      icon: Icons.people_alt_rounded,
      title: question,
      heard: _heard,
      choices: matches,
      onChoice: then,
    );
  }

  Future<AssistantOutcome?> _call(ContactEntry contact) async =>
      await actions.dial(contact.number)
      ? _done(Icons.call_rounded, '打給 ${contact.name}', detail: contact.number)
      : _cannotDial();

  Future<AssistantOutcome?> _text(ContactEntry contact, String body) async =>
      await actions.composeSms(number: contact.number, body: body)
      ? _done(
          Icons.sms_rounded,
          '傳簡訊給 ${contact.name}',
          detail: body.isEmpty ? contact.number : '「$body」',
        )
      : _cannotText();

  /// The help card: call the emergency contact or 119, or send the location.
  AssistantOutcome _help({bool dialed = false}) {
    final contact = emergencyContact;
    return AssistantOutcome(
      tone: OutcomeTone.problem,
      icon: Icons.sos_rounded,
      title: dialed && contact != null ? '正在打給 ${contact.name}' : '需要幫忙嗎？',
      heard: _heard,
      buttons: [
        if (contact != null)
          OutcomeButton(
            icon: Icons.call_rounded,
            label: '打給 ${contact.name}',
            kind: ButtonKind.urgent,
            onPressed: () => _dial(contact.number),
          ),
        OutcomeButton(
          icon: Icons.local_hospital_rounded,
          label: '打 119',
          kind: ButtonKind.urgent,
          onPressed: () => _dial('119'),
        ),
        OutcomeButton(
          icon: Icons.share_location_rounded,
          label: contact == null ? '用 LINE 傳我的位置' : '把位置傳給 ${contact.name}',
          kind: ButtonKind.quiet,
          onPressed: () => _sendLocation(to: contact, urgent: true),
        ),
        if (contact == null)
          OutcomeButton(
            icon: Icons.person_add_alt_1_rounded,
            label: '設定緊急聯絡人',
            kind: ButtonKind.quiet,
            onPressed: () async => _contactCard(),
          ),
      ],
    );
  }

  /// Keeps the card when the call starts, so its other buttons stay at hand.
  Future<AssistantOutcome?> _dial(String number) async =>
      await actions.dial(number) ? null : _cannotDial();

  Future<AssistantOutcome?> _whereAmI() async {
    final result = await actions.locate();
    if (result is! LocationFound) return _locationProblem(result);
    final place = result.place;
    final contact = emergencyContact;
    return AssistantOutcome(
      tone: OutcomeTone.info,
      icon: Icons.location_on_rounded,
      title: '你在這裡',
      detail: place.label,
      heard: _heard,
      buttons: [
        OutcomeButton(
          icon: Icons.map_rounded,
          label: '打開地圖',
          onPressed: () async => await actions.openMap(place)
              ? null
              : _problem(Icons.wrong_location_rounded, '打不開地圖'),
        ),
        if (contact != null)
          OutcomeButton(
            icon: Icons.share_location_rounded,
            label: '傳給 ${contact.name}',
            kind: ButtonKind.quiet,
            onPressed: () => _sendPlace(place, to: contact),
          ),
      ],
    );
  }

  Future<AssistantOutcome?> _sendLocation({
    ContactEntry? to,
    bool viaLine = false,
    bool urgent = false,
  }) async {
    final result = await actions.locate();
    if (result is! LocationFound) return _locationProblem(result);
    return _sendPlace(result.place, to: viaLine ? null : to, urgent: urgent);
  }

  /// Writes the message; the person presses send. Without a contact, LINE's
  /// own screen asks who gets it.
  Future<AssistantOutcome?> _sendPlace(
    Place place, {
    ContactEntry? to,
    bool urgent = false,
  }) async {
    final text = place.message(urgent: urgent);
    if (to != null) {
      return await actions.composeSms(number: to.number, body: text)
          ? _done(Icons.sms_rounded, '把位置傳給 ${to.name}', detail: place.label)
          : _cannotText();
    }
    if (await actions.shareOnLine(text)) {
      return _done(Icons.send_rounded, '選一位朋友傳位置', detail: place.label);
    }
    // No LINE on this phone: a text message with no one filled in.
    return await actions.composeSms(body: text)
        ? _done(Icons.sms_rounded, '選一位聯絡人傳位置', detail: place.label)
        : _cannotText();
  }

  AssistantOutcome _locationProblem(LocationResult result) => switch (result) {
    LocationDenied() => AssistantOutcome(
      tone: OutcomeTone.problem,
      icon: Icons.location_disabled_rounded,
      title: '需要定位權限',
      detail: '才能知道你在哪裡',
      heard: _heard,
      buttons: [_settingsButton],
    ),
    LocationOff() => AssistantOutcome(
      tone: OutcomeTone.problem,
      icon: Icons.location_off_rounded,
      title: '定位沒有打開',
      heard: _heard,
      buttons: [
        OutcomeButton(
          icon: Icons.settings_rounded,
          label: '打開定位',
          onPressed: () async {
            await actions.openLocationSettings();
            return null;
          },
        ),
      ],
    ),
    LocationUnavailable() || LocationFound() => _problem(
      Icons.location_searching_rounded,
      '現在找不到位置',
      detail: '到窗邊或戶外再試一次',
    ),
  };

  /// Shows who the emergency contact is and offers the contact list.
  AssistantOutcome _contactCard() {
    final contact = emergencyContact;
    return AssistantOutcome(
      tone: OutcomeTone.info,
      icon: Icons.contact_emergency_rounded,
      title: '緊急聯絡人',
      detail: contact == null ? '還沒設定' : '${contact.name} ${contact.number}',
      heard: _heard,
      buttons: [
        OutcomeButton(
          icon: Icons.contacts_rounded,
          label: contact == null ? '從通訊錄選' : '換一位',
          onPressed: () async {
            final picked = await actions.pickContact();
            return picked == null ? null : _saveContact(picked);
          },
        ),
      ],
    );
  }

  Future<AssistantOutcome?> _saveContact(ContactEntry contact) async {
    await store.save(contact);
    emergencyContact = contact;
    return _done(
      Icons.verified_user_rounded,
      '緊急聯絡人',
      detail: '${contact.name} ${contact.number}',
    );
  }

  Future<AssistantOutcome?> _torch({required bool on}) async {
    if (!await actions.setTorch(on: on)) {
      return on
          ? _problem(Icons.flashlight_off_rounded, '這支手機開不了手電筒')
          : _problem(
              Icons.flashlight_off_rounded,
              '手電筒關不掉',
              detail: '從螢幕上方往下滑，按手電筒關掉',
            );
    }
    torchOn = on;
    return AssistantOutcome(
      tone: OutcomeTone.done,
      icon: on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
      title: on ? '手電筒開了' : '手電筒關了',
      heard: _heard,
      buttons: [
        if (on)
          OutcomeButton(
            icon: Icons.flashlight_off_rounded,
            label: '關掉手電筒',
            onPressed: () => _torch(on: false),
          ),
      ],
    );
  }

  OutcomeButton get _settingsButton => OutcomeButton(
    icon: Icons.settings_rounded,
    label: '打開設定',
    onPressed: () async {
      await actions.openSettings();
      return null;
    },
  );

  AssistantOutcome _unknown() => AssistantOutcome(
    tone: OutcomeTone.info,
    icon: Icons.hearing_rounded,
    title: '這句我還不會',
    heard: _heard,
    showExamples: true,
  );

  AssistantOutcome _cannotDial() =>
      _problem(Icons.phone_disabled_rounded, '這支手機沒辦法撥號');

  AssistantOutcome _cannotText() =>
      _problem(Icons.sms_failed_rounded, '這支手機沒辦法傳訊息');

  AssistantOutcome _done(IconData icon, String title, {String? detail}) =>
      _card(OutcomeTone.done, icon, title, detail);

  AssistantOutcome _info(IconData icon, String title, {String? detail}) =>
      _card(OutcomeTone.info, icon, title, detail);

  AssistantOutcome _problem(IconData icon, String title, {String? detail}) =>
      _card(OutcomeTone.problem, icon, title, detail);

  AssistantOutcome _card(
    OutcomeTone tone,
    IconData icon,
    String title,
    String? detail,
  ) => AssistantOutcome(
    tone: tone,
    icon: icon,
    title: title,
    detail: detail,
    heard: _heard,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

IconData _appIcon(PhoneApp app) => switch (app) {
  PhoneApp.line => Icons.chat_rounded,
  PhoneApp.youtube => Icons.smart_display_rounded,
  PhoneApp.facebook => Icons.facebook_rounded,
  PhoneApp.maps => Icons.map_rounded,
  PhoneApp.messages => Icons.sms_rounded,
};

/// Puts a space before Latin names only: "已打開 LINE", "已打開地圖".
String _words(String verb, String name) =>
    RegExp(r'^[A-Za-z]').hasMatch(name) ? '$verb $name' : '$verb$name';

String _clock(DateTime time) {
  final hour = time.hour;
  final period = hour < 5
      ? '凌晨'
      : hour < 11
      ? '早上'
      : hour < 13
      ? '中午'
      : hour < 18
      ? '下午'
      : '晚上';
  final shown = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $shown:${time.minute.toString().padLeft(2, '0')}';
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
