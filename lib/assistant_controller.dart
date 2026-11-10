import 'package:flutter/material.dart';

import 'contact_matcher.dart';
import 'phone_actions.dart';
import 'voice_command.dart';

enum OutcomeTone { done, info, problem }

/// A follow-up button shown under an outcome.
enum OutcomeAction { torchOff, openSettings }

class AssistantOutcome {
  const AssistantOutcome({
    required this.tone,
    required this.icon,
    required this.title,
    this.detail,
    this.heard,
    this.choices = const [],
    this.action,
    this.showExamples = false,
  });

  final OutcomeTone tone;
  final IconData icon;
  final String title;
  final String? detail;

  /// What Breeze heard, shown small under the result.
  final String? heard;
  final List<ContactEntry> choices;
  final OutcomeAction? action;

  /// Show what can be said, after a request that was not understood.
  final bool showExamples;
}

/// Turns what was heard into a phone action and keeps the result for the UI.
class AssistantController extends ChangeNotifier {
  AssistantController(this.actions, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final PhoneActions actions;
  final DateTime Function() _now;
  AssistantOutcome? outcome;
  bool working = false;
  bool _disposed = false;

  Future<void> handle(String transcript) async {
    if (_disposed) return;
    final heard = transcript.trim();
    working = true;
    outcome = null;
    _notify();
    try {
      outcome = await _run(parseVoiceCommand(heard), heard);
    } catch (_) {
      outcome = AssistantOutcome(
        tone: OutcomeTone.problem,
        icon: Icons.error_outline_rounded,
        title: '這件事沒有做成',
        detail: '請再講一次',
        heard: heard,
      );
    } finally {
      working = false;
      _notify();
    }
  }

  Future<void> call(ContactEntry contact) async {
    final heard = outcome?.heard;
    outcome = await actions.dial(contact.number)
        ? AssistantOutcome(
            tone: OutcomeTone.done,
            icon: Icons.call_rounded,
            title: '打給 ${contact.name}',
            detail: contact.number,
            heard: heard,
          )
        : AssistantOutcome(
            tone: OutcomeTone.problem,
            icon: Icons.phone_disabled_rounded,
            title: '這支手機沒辦法撥號',
            heard: heard,
          );
    _notify();
  }

  Future<void> runAction(OutcomeAction action) async {
    switch (action) {
      case OutcomeAction.torchOff:
        final heard = outcome?.heard;
        outcome = await _torch(on: false, heard: heard);
        _notify();
      case OutcomeAction.openSettings:
        await actions.openSettings();
    }
  }

  void clear() {
    if (outcome == null) return;
    outcome = null;
    _notify();
  }

  Future<AssistantOutcome> _run(VoiceCommand command, String heard) async {
    AssistantOutcome done(IconData icon, String title, {String? detail}) =>
        AssistantOutcome(
          tone: OutcomeTone.done,
          icon: icon,
          title: title,
          detail: detail,
          heard: heard,
        );
    AssistantOutcome info(IconData icon, String title, {String? detail}) =>
        AssistantOutcome(
          tone: OutcomeTone.info,
          icon: icon,
          title: title,
          detail: detail,
          heard: heard,
        );
    AssistantOutcome problem(IconData icon, String title, {String? detail}) =>
        AssistantOutcome(
          tone: OutcomeTone.problem,
          icon: icon,
          title: title,
          detail: detail,
          heard: heard,
        );

    switch (command) {
      case OpenAppCommand(:final app):
        return await actions.openApp(app)
            ? done(_appIcon(app), _words('已打開', app.label))
            : problem(
                Icons.search_off_rounded,
                _words('手機裡找不到', app.label),
              );
      case CallContactCommand(name: ''):
        return info(Icons.call_rounded, '要打給誰？', detail: '例如：打予阿明');
      case CallContactCommand(:final name):
        final access = await actions.loadContacts();
        if (!access.granted) {
          return AssistantOutcome(
            tone: OutcomeTone.problem,
            icon: Icons.contacts_rounded,
            title: '需要通訊錄權限',
            detail: '才能照名字幫你打電話',
            heard: heard,
            action: OutcomeAction.openSettings,
          );
        }
        final matches = matchContacts(name, access.contacts, limit: 3);
        if (matches.isEmpty) {
          return problem(
            Icons.person_search_rounded,
            '找不到「$name」',
            detail: '通訊錄裡沒有這個名字',
          );
        }
        if (matches.length > 1) {
          return AssistantOutcome(
            tone: OutcomeTone.info,
            icon: Icons.people_alt_rounded,
            title: '要打給哪一位？',
            heard: heard,
            choices: matches,
          );
        }
        final contact = matches.single;
        return await actions.dial(contact.number)
            ? done(
                Icons.call_rounded,
                '打給 ${contact.name}',
                detail: contact.number,
              )
            : problem(Icons.phone_disabled_rounded, '這支手機沒辦法撥號');
      case DialNumberCommand(:final number):
        return await actions.dial(number)
            ? done(Icons.call_rounded, '撥打 $number')
            : problem(Icons.phone_disabled_rounded, '這支手機沒辦法撥號');
      case FlashlightCommand(:final on):
        return _torch(on: on, heard: heard);
      case NavigateCommand(:final place):
        return await actions.navigate(place)
            ? done(Icons.near_me_rounded, '帶你去$place')
            : problem(Icons.wrong_location_rounded, '打不開地圖');
      case VideoSearchCommand(:final query):
        return await actions.searchVideo(query)
            ? done(Icons.smart_display_rounded, '在 YouTube 找「$query」')
            : problem(Icons.search_off_rounded, '打不開 YouTube');
      case WeatherCommand():
        return await actions.searchWeb('今天天氣')
            ? done(Icons.wb_sunny_rounded, '幫你查天氣')
            : problem(Icons.cloud_off_rounded, '現在查不到天氣');
      case TimeCommand():
        return info(Icons.schedule_rounded, '現在是${_clock(_now())}');
      case DateCommand():
        final today = _now();
        return info(
          Icons.calendar_month_rounded,
          '今天 ${today.month} 月 ${today.day} 日',
          detail: '星期${_weekdays[today.weekday - 1]}',
        );
      case UnknownCommand():
        return AssistantOutcome(
          tone: OutcomeTone.info,
          icon: Icons.hearing_rounded,
          title: '這句我還不會',
          heard: heard,
          showExamples: true,
        );
    }
  }

  Future<AssistantOutcome> _torch({required bool on, String? heard}) async {
    if (!await actions.setTorch(on: on)) {
      return AssistantOutcome(
        tone: OutcomeTone.problem,
        icon: Icons.flashlight_off_rounded,
        title: '這支手機開不了手電筒',
        heard: heard,
      );
    }
    return AssistantOutcome(
      tone: OutcomeTone.done,
      icon: on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
      title: on ? '手電筒開了' : '手電筒關了',
      heard: heard,
      action: on ? OutcomeAction.torchOff : null,
    );
  }

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
