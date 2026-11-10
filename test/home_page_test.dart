import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/home_page.dart';
import 'package:an_xin_ban/main.dart';
import 'package:an_xin_ban/phone_actions.dart';
import 'package:an_xin_ban/recording_controller.dart';
import 'package:an_xin_ban/voice_command.dart';

class QuietBackend implements RecordingBackend {
  final _states = StreamController<RecordState>.broadcast();
  final _done = StreamController<void>.broadcast();
  @override
  Future<String?> retainLatest({String? keepPath}) async => keepPath;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<String?> stop() async => '/latest.m4a';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> play(String path) async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Stream<void> get playbackCompleted => _done.stream;
  @override
  Stream<RecordState> get states => _states.stream;
  @override
  Future<void> dispose() async {
    await _states.close();
    await _done.close();
  }
}

class Phone implements PhoneActions {
  final opened = <PhoneApp>[];
  final dialed = <String>[];
  @override
  Future<bool> openApp(PhoneApp app) async {
    opened.add(app);
    return true;
  }

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    return true;
  }

  @override
  Future<ContactsAccess> loadContacts() async => const ContactsAccess.granted([
    ContactEntry(name: '王小明', numbers: ['0912-345-678']),
    ContactEntry(name: '陳志明', numbers: ['0933-222-111']),
    ContactEntry(name: '林明華', numbers: ['0988-765-432']),
  ]);
  @override
  Future<bool> setTorch({required bool on}) async => true;
  @override
  Future<bool> navigate(String place) async => true;
  @override
  Future<bool> searchVideo(String query) async => true;
  @override
  Future<bool> searchWeb(String query) async => true;
  @override
  Future<void> openSettings() async {}
}

void main() {
  late Phone phone;
  late AssistantController assistant;
  late RecordingController recording;
  var heard = '';

  setUp(() {
    phone = Phone();
    assistant = AssistantController(phone);
    recording = RecordingController(
      QuietBackend(),
      transcribe: (_) async => heard,
    );
  });
  tearDown(() {
    assistant.dispose();
    recording.dispose();
  });

  Future<void> open(WidgetTester tester, Size size, {double text = 1}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      AnXinBanApp(
        home: HomePage(recording: recording, assistant: assistant),
      ),
    );
  }

  Future<void> say(WidgetTester tester, String words) async {
    heard = words;
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  // Overflow is reported as a test failure, so these also prove that every
  // state fits on one screen without scrolling.
  for (final (name, size) in [
    ('small phone', const Size(320, 568)),
    ('iPhone SE', const Size(375, 667)),
    ('iPhone 16', const Size(393, 852)),
  ]) {
    testWidgets('every state fits on a $name, even with large text', (
      tester,
    ) async {
      await open(tester, size, text: 1.6);
      expect(find.text('有啥物需要幫忙？'), findsOneWidget);
      expect(find.text('可以這樣講'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);

      await tester.tap(find.bySemanticsLabel('開始錄音'));
      await tester.pump();
      expect(find.text('正在聽…'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('停止錄音'));
      await tester.pump(const Duration(seconds: 1));

      await say(tester, '打給阿明');
      expect(find.text('要打給哪一位？'), findsOneWidget);
      await say(tester, '今天心情不錯');
      expect(find.text('這句我還不會'), findsOneWidget);
      await say(tester, '開手電筒');
      expect(find.text('關掉手電筒'), findsOneWidget);
    });
  }

  testWidgets('saying "開 LINE" opens LINE and says so', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '幫我開LINE');
    expect(phone.opened, [PhoneApp.line]);
    expect(find.text('已打開 LINE'), findsOneWidget);
    expect(find.text('「幫我開LINE」'), findsOneWidget);
  });

  testWidgets('tapping a contact choice calls that person', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '打給阿明');
    await tester.tap(find.text('陳志明'));
    await tester.pump();
    expect(phone.dialed, ['0933-222-111']);
    expect(find.text('打給 陳志明'), findsOneWidget);
  });

  testWidgets('a new recording clears the previous result', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '幫我開LINE');
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已打開 LINE'), findsNothing);
    expect(find.text('可以這樣講'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump(const Duration(seconds: 1));
  });
}
